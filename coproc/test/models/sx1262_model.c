/*
 * Test model of an SX1262 (sx1262_model.h).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gpio_model.h"
#include "sx1262_model.h"

#define MODE_STBY_RC 2
#define MODE_STBY_XOSC 3
#define MODE_RX 5
#define MODE_TX 6

#define MAX_FRAME 300
#define MAX_LOG 4096

struct entry {
    uint16_t len; /* 0: a reset pulse */
    uint8_t *bytes;
};

static struct {
    uint64_t (*now)(void);
    int powered;
    int nreset;
    int selected;
    uint64_t busy_until;
    int mode;
    uint8_t regs[0x1000];
    uint8_t buffer[256];
    uint8_t tx_base, rx_base;
    uint16_t irq, irq_mask, dio1_mask;
    uint8_t packet_params[9];
    uint32_t frf;
    uint8_t packet_type;
    int rx_continuous;
    uint8_t rx_len, rx_start;
    uint8_t status_pkt[3];
    uint8_t frame[MAX_FRAME];
    size_t pos;
    uint8_t sent[256];
    size_t sent_len;
    struct entry log[MAX_LOG];
    size_t logged;
} sx;

static void log_entry(const uint8_t *bytes, size_t len)
{
    if (sx.logged == MAX_LOG) {
        fprintf(stderr, "sx1262_model: command log full\n");
        exit(2);
    }
    struct entry *e = &sx.log[sx.logged++];
    e->len = (uint16_t) len;
    e->bytes = NULL;
    if (len) {
        e->bytes = malloc(len);
        memcpy(e->bytes, bytes, len);
    }
}

static void defaults(void)
{
    memset(sx.regs, 0, sizeof sx.regs);
    memset(sx.buffer, 0, sizeof sx.buffer);
    /* The version string LilyGO's RadioLib build looks for (SX1262.h 16). */
    memcpy(&sx.regs[0x320], "SX1261 V2D 2D02", 16);
    sx.regs[0x740] = 0x14; /* LoRa sync word, reset value */
    sx.regs[0x741] = 0x24;
    sx.regs[0x736] = 0x0d; /* IQ polarity setup */
    sx.regs[0x889] = 0x04; /* sensitivity */
    sx.regs[0x8d8] = 0xc8; /* TX clamp */
    sx.regs[0x8e7] = 0x18; /* OCP */
    sx.mode = MODE_STBY_RC;
    sx.irq = sx.irq_mask = sx.dio1_mask = 0;
    sx.tx_base = sx.rx_base = 0;
    sx.frf = 0;
    sx.rx_len = sx.rx_start = 0;
    sx.packet_type = 0;
    memset(sx.packet_params, 0, sizeof sx.packet_params);
}

void sx1262_model_init(uint64_t (*now)(void))
{
    for (size_t i = 0; i < sx.logged; i++) {
        free(sx.log[i].bytes);
    }
    memset(&sx, 0, sizeof sx);
    sx.now = now;
    sx.nreset = 1;
    defaults();
}

static void on_nreset(void *ctx, int level)
{
    (void) ctx;
    sx1262_model_nreset(level);
}

static void on_power(void *ctx, int level)
{
    (void) ctx;
    sx1262_model_power(level);
}

static int busy_pin(void *ctx)
{
    (void) ctx;
    return sx1262_model_busy();
}

static int dio1_pin(void *ctx)
{
    (void) ctx;
    return sx1262_model_dio1();
}

void sx1262_model_wire_gpio(void)
{
    gpio_model_listen(5, on_nreset, NULL);
    gpio_model_listen(44, on_power, NULL);
    gpio_model_drive(19, busy_pin, NULL);
    gpio_model_drive(20, dio1_pin, NULL);
}

void sx1262_model_power(int on)
{
    if (on && !sx.powered) {
        defaults();
        sx.busy_until = sx.now() + 1000;
    }
    sx.powered = on;
}

void sx1262_model_nreset(int level)
{
    if (!sx.nreset && level) {
        defaults();
        sx.busy_until = sx.now() + 1000;
        log_entry(NULL, 0);
    }
    sx.nreset = level;
}

static int alive(void)
{
    return sx.powered && sx.nreset;
}

int sx1262_model_busy(void)
{
    return !alive() || sx.now() < sx.busy_until;
}

int sx1262_model_dio1(void)
{
    return alive() && (sx.irq & sx.dio1_mask) != 0;
}

static uint8_t status(void)
{
    return (uint8_t) ((sx.mode << 4) | (1u << 1));
}

/* Where a read command's data starts in the frame (RadioLib: after the
 * command bytes and one status byte), 0 for writes. */
static size_t data_index(uint8_t op)
{
    switch (op) {
        case 0x1d: return 4; /* ReadRegister aH aL NOP */
        case 0x1e: return 3; /* ReadBuffer offset NOP */
        case 0xc0: /* GetStatus */
        case 0x11: /* GetPacketType */
        case 0x12: /* GetIrqStatus */
        case 0x13: /* GetRxBufferStatus */
        case 0x14: /* GetPacketStatus */
        case 0x15: /* GetRssiInst */
        case 0x17: /* GetDeviceErrors */
            return 2;
        default: return 0;
    }
}

static uint8_t read_data(uint8_t op, size_t k)
{
    switch (op) {
        case 0x1d: {
            uint16_t addr = (uint16_t) ((sx.frame[1] << 8) | sx.frame[2]);
            return sx.regs[(addr + k) & 0xfff];
        }
        case 0x1e: return sx.buffer[(sx.frame[1] + k) & 0xff];
        case 0xc0: return status();
        case 0x11: return sx.packet_type;
        case 0x12: return k == 0 ? (uint8_t) (sx.irq >> 8) : (uint8_t) sx.irq;
        case 0x13: return k == 0 ? sx.rx_len : sx.rx_start;
        case 0x14: return k < 3 ? sx.status_pkt[k] : 0;
        default: return 0;
    }
}

uint8_t sx1262_model_exchange(uint8_t mosi)
{
    if (!alive() || !sx.selected) {
        return 0;
    }
    if (sx.pos == MAX_FRAME) {
        fprintf(stderr, "sx1262_model: command longer than %d bytes\n", MAX_FRAME);
        exit(2);
    }
    size_t i = sx.pos++;
    sx.frame[i] = mosi;
    size_t at = data_index(sx.frame[0]);
    if (i == 0 || at == 0 || i < at) {
        return status();
    }
    return read_data(sx.frame[0], i - at);
}

static void execute(const uint8_t *f, size_t n)
{
    uint64_t busy = 5;
    switch (f[0]) {
        case 0x80: sx.mode = (n > 1 && f[1]) ? MODE_STBY_XOSC : MODE_STBY_RC; break;
        case 0x8a: if (n > 1) sx.packet_type = f[1]; break;
        case 0x8f:
            if (n > 2) {
                sx.tx_base = f[1];
                sx.rx_base = f[2];
            }
            break;
        case 0x0d:
            for (size_t k = 3; k < n; k++) {
                sx.regs[(((f[1] << 8) | f[2]) + k - 3) & 0xfff] = f[k];
            }
            break;
        case 0x0e:
            for (size_t k = 2; k < n; k++) {
                sx.buffer[(f[1] + k - 2) & 0xff] = f[k];
            }
            break;
        case 0x08:
            if (n > 4) {
                sx.irq_mask = (uint16_t) ((f[1] << 8) | f[2]);
                sx.dio1_mask = (uint16_t) ((f[3] << 8) | f[4]);
            }
            break;
        case 0x02:
            if (n > 2) sx.irq &= (uint16_t) ~((f[1] << 8) | f[2]);
            break;
        case 0x8c:
            memcpy(sx.packet_params, f + 1, n - 1 < sizeof sx.packet_params ? n - 1 : sizeof sx.packet_params);
            break;
        case 0x86:
            if (n > 4) sx.frf = ((uint32_t) f[1] << 24) | ((uint32_t) f[2] << 16) | ((uint32_t) f[3] << 8) | f[4];
            break;
        case 0x83: sx.mode = MODE_TX; break;
        case 0x82:
            sx.mode = MODE_RX;
            sx.rx_continuous = n > 3 && f[1] == 0xff && f[2] == 0xff && f[3] == 0xff;
            break;
        case 0x89: busy = 3500; break;
        case 0x98: busy = 1000; break;
        default: break;
    }
    sx.busy_until = sx.now() + busy;
}

void sx1262_model_select(int asserted)
{
    if (asserted && !sx.selected) {
        sx.pos = 0;
    } else if (!asserted && sx.selected && sx.pos > 0) {
        if (alive()) {
            log_entry(sx.frame, sx.pos);
            execute(sx.frame, sx.pos);
        }
    }
    sx.selected = asserted;
}

static void raise(uint16_t flags)
{
    sx.irq |= flags & sx.irq_mask;
}

static void land(const uint8_t *packet, size_t len)
{
    for (size_t k = 0; k < len; k++) {
        sx.buffer[(sx.rx_base + k) & 0xff] = packet[k];
    }
    sx.rx_len = (uint8_t) len;
    sx.rx_start = sx.rx_base;
    /* A finite timeout is single mode: back to standby (fallback STBY_RC). */
    if (!sx.rx_continuous) {
        sx.mode = MODE_STBY_RC;
    }
}

void sx1262_model_receive(const uint8_t *packet, size_t len, uint8_t rssi_pkt, uint8_t snr_pkt, uint8_t signal_rssi)
{
    if (!alive() || sx.mode != MODE_RX) {
        return;
    }
    sx.status_pkt[0] = rssi_pkt;
    sx.status_pkt[1] = snr_pkt;
    sx.status_pkt[2] = signal_rssi;
    land(packet, len);
    raise(SX_IRQ_RX_DONE | SX_IRQ_HEADER_VALID);
}

void sx1262_model_receive_crc_error(const uint8_t *packet, size_t len)
{
    if (!alive() || sx.mode != MODE_RX) {
        return;
    }
    land(packet, len);
    raise(SX_IRQ_RX_DONE | SX_IRQ_HEADER_VALID | SX_IRQ_CRC_ERR);
}

int sx1262_model_finish_tx(void)
{
    if (!alive() || sx.mode != MODE_TX) {
        return 0;
    }
    size_t len = sx.packet_params[3];
    for (size_t k = 0; k < len; k++) {
        sx.sent[k] = sx.buffer[(sx.tx_base + k) & 0xff];
    }
    sx.sent_len = len;
    sx.mode = MODE_STBY_RC;
    raise(SX_IRQ_TX_DONE);
    return 1;
}

size_t sx1262_model_sent(uint8_t *packet)
{
    memcpy(packet, sx.sent, sx.sent_len);
    return sx.sent_len;
}

int sx1262_model_mode(void)
{
    return sx.mode;
}

uint8_t sx1262_model_register(uint16_t addr)
{
    return sx.regs[addr & 0xfff];
}

uint32_t sx1262_model_frequency(void)
{
    return sx.frf;
}

uint16_t sx1262_model_irq(void)
{
    return sx.irq;
}

size_t sx1262_model_commands(void)
{
    return sx.logged;
}

const uint8_t *sx1262_model_command(size_t index, size_t *len)
{
    if (index >= sx.logged) {
        return NULL;
    }
    *len = sx.log[index].len;
    return sx.log[index].len ? sx.log[index].bytes : (const uint8_t *) "";
}

int sx1262_model_write_trace(const char *path)
{
    FILE *out = fopen(path, "w");
    if (out == NULL) {
        perror(path);
        return -1;
    }
    for (size_t i = 0; i < sx.logged; i++) {
        if (sx.log[i].len == 0) {
            fprintf(out, "RESET\n");
            continue;
        }
        fprintf(out, "C");
        for (size_t k = 0; k < sx.log[i].len; k++) {
            fprintf(out, " %02X", sx.log[i].bytes[k]);
        }
        fprintf(out, "\n");
    }
    return fclose(out);
}
