/*
 * Host tests of the board drivers (touch_k230.c, lora_k230.c,
 * power_k230.c, uart_k230.c and the bus drivers under them) against the
 * register mock (k230_mmio_mock.c) and the device models of
 * coproc/test/models/. Built and run by coproc/test/board_trace/run.sh:
 *
 *   board_k230_test                       the unit tests below
 *   board_k230_test trace <device> <file> the scenario the vendor code also
 *                                         runs (golden_*.c), for the
 *                                         comparison: lora (the SX1262's
 *                                         commands), touch (the GT9895's I2C
 *                                         transfers), power (PMU registers)
 *
 * Built twice: COPROC_K230_DEVICES=1 (the board) and =0 (QEMU virt). Each
 * test runs in its own process: the drivers keep their state in statics, as
 * the firmware does across VM restarts.
 *
 * The clocks are set as Canaan documents them (PLL0 1.6 GHz,
 * sysctl_clk.h 109-112): I2C3 at 100 MHz (the vendor I2C driver's IC_CLK),
 * QSPI0 at 200 MHz (the U-Boot DT's def_200mhz for spi1).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "dw_i2c_model.h"
#include "dw_ssi_model.h"
#include "gpio_model.h"
#include "gt9895_model.h"
#include "k230_mmio_mock.h"
#include "lora_k230.h"
#include "pmu_model.h"
#include "power_k230.h"
#include "sx1262_model.h"
#include "touch_k230.h"
#include "uart_k230.h"

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: %s: check failed: %s\n", __FILE__, __LINE__, __func__, #cond); \
            exit(1);                                                                               \
        }                                                                                          \
    } while (0)

#define PLL0_CFG0 0x91102000u
#define PLL0_CFG1 0x91102004u
#define CMU_HS_SPI 0x91100020u
#define CMU_UART_I2C 0x9110002cu
#define IOMUX 0x91105000u
#define I2C3 0x91408000u
#define QSPI0 0x91582000u
#define PMU 0x91000000u
#define UART3 0x91403000u

#if COPROC_K230_DEVICES

/* The board as the tests start it: every pad at 0 (3.3 V banks, MSC 0),
 * clocks as documented. */
static void clocks(void)
{
    for (unsigned io = 0; io < 64; io++) {
        mock_poke(IOMUX + 4 * io, 0);
    }
    /* 24 MHz x 200 / 3 = 1.6 GHz. */
    mock_poke(PLL0_CFG0, 199u | (2u << 16));
    mock_poke(PLL0_CFG1, 0);
    /* QSPI0 = PLL0 / 4 / 2; UART3 / 1; I2C3 = PLL0 / 4 / 4. */
    mock_poke(CMU_HS_SPI, 1u << 3);
    mock_poke(CMU_UART_I2C, 3u << 24);
}

static size_t count(char kind, uint64_t addr)
{
    size_t n = 0;
    for (size_t i = 0; i < mock_event_count(); i++) {
        n += mock_events()[i].kind == kind && mock_events()[i].addr == addr;
    }
    return n;
}

static long last_write_index(uint64_t addr)
{
    for (size_t i = mock_event_count(); i-- > 0;) {
        if (mock_events()[i].kind == MOCK_WRITE && mock_events()[i].addr == addr) {
            return (long) i;
        }
    }
    return -1;
}

static uint32_t last_write(uint64_t addr)
{
    long i = last_write_index(addr);
    if (i < 0) {
        fprintf(stderr, "no write to 0x%08llx\n", (unsigned long long) addr);
        exit(1);
    }
    return mock_events()[i].value;
}

/* ---- LoRa ----------------------------------------------------------------- */

static void lora_board(unsigned fifo, int wired_power)
{
    mock_reset(&mock_nominal);
    clocks();
    gpio_model_attach();
    sx1262_model_init(mock_now_us);
    sx1262_model_wire_gpio();
    if (!wired_power) {
        /* The module's LDO never comes up. */
        gpio_model_listen(44, NULL, NULL);
    }
    dw_ssi_model_attach(QSPI0, fifo, 4);
}

static int command_is(size_t index, const uint8_t *bytes, size_t len)
{
    size_t n;
    const uint8_t *c = sx1262_model_command(index, &n);
    return c != NULL && n == len && memcmp(c, bytes, len) == 0;
}

/* The command `index` from the end (1 = the last). */
static const uint8_t *command_back(size_t back, size_t *len)
{
    return sx1262_model_command(sx1262_model_commands() - back, len);
}

static void lora_scenario(void)
{
    CHECK(lora_k230_open(915000000u) == LORA_K230_OK);
    static const uint8_t hello[] = "hello, deck";
    sx1262_model_receive(hello, sizeof hello - 1, 0x50, 0x1c, 0x52);
    struct lora_k230_event event;
    CHECK(lora_k230_poll(&event) == LORA_K230_OK);
    CHECK(event.kind == LORA_K230_PACKET);
    CHECK(event.len == sizeof hello - 1 && memcmp(event.data, hello, event.len) == 0);
    /* RadioLib on the same model (golden_lora): snr 7.00, rssi -41.0. */
    CHECK(event.snr_pkt == 28 && event.snr_pkt / 4 == 7);
    CHECK(event.signal_rssi == 0x52 && -(event.signal_rssi / 2) == -41);
    CHECK(lora_k230_send((const uint8_t *) "ping", 4) == LORA_K230_OK);
    CHECK(sx1262_model_finish_tx());
    CHECK(lora_k230_poll(&event) == LORA_K230_OK && event.kind == LORA_K230_SENT);
}

static void test_lora_open_configures_the_radio(void)
{
    lora_board(32, 1);
    CHECK(lora_k230_open(915000000u) == LORA_K230_OK);
    CHECK(dw_ssi_model_errors() == 0);
    /* Pads: QSPI0 on IO14-17, GPIO on IO5/19/20, IO44 pulled up. */
    CHECK(mock_peek(IOMUX + 4 * 14) == 0x18ce);
    CHECK(mock_peek(IOMUX + 4 * 15) == 0x188e);
    CHECK(mock_peek(IOMUX + 4 * 16) == 0x198f && mock_peek(IOMUX + 4 * 17) == 0x198f);
    CHECK(mock_peek(IOMUX + 4 * 5) == 0x18f && mock_peek(IOMUX + 4 * 19) == 0x18f && mock_peek(IOMUX + 4 * 20) == 0x18f);
    CHECK(mock_peek(IOMUX + 4 * 44) == 0x1cf);
    CHECK(gpio_model_output(44) == 1 && gpio_model_output(5) == 1);
    CHECK(gpio_model_output(19) == -1 && gpio_model_output(20) == -1);
    /* QSPI0: mode 0, 8 bits, 200 MHz / 5 MHz = 40 (drv_spi.c 99, 153). */
    CHECK(dw_ssi_model_ctrlr0() == 0x07 && dw_ssi_model_baudr() == 40);
    CHECK(last_write(QSPI0 + 0xf0) == 2);
    /* The radio: 915 MHz, LoRa SF10/125 kHz/4-6, 22 dBm, receiving. */
    CHECK(sx1262_model_frequency() == 0x39300000u);
    CHECK(sx1262_model_register(0x740) == 0x14 && sx1262_model_register(0x741) == 0x24);
    CHECK(sx1262_model_register(0x8e7) == 0x38);
    CHECK(sx1262_model_mode() == 5);
    size_t n;
    const uint8_t *rx = command_back(1, &n);
    CHECK(n == 4 && rx[0] == 0x82 && rx[1] == 0xff && rx[2] == 0xff && rx[3] == 0xff);
}

static void test_lora_frequency_is_configuration(void)
{
    static const struct {
        uint32_t hz;
        uint8_t band[2];
        uint32_t frf;
    } cases[] = {
        { 868000000u, { 0xd7, 0xdb }, 0x36400000u },
        { 923000000u, { 0xe1, 0xe9 }, 0x39b00000u },
        { 433000000u, { 0x6b, 0x6f }, 0x1b100000u },
        { 490000000u, { 0x75, 0x81 }, 0x1ea00000u },
        /* Outside the tables: calibrateImageRejection(146, 154): 35, 39. */
        { 150000000u, { 0x23, 0x27 }, 0x09600000u },
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        lora_board(32, 1);
        CHECK(lora_k230_open(cases[i].hz) == LORA_K230_OK);
        CHECK(sx1262_model_frequency() == cases[i].frf);
        int calibrated = 0;
        for (size_t c = 0; c < sx1262_model_commands(); c++) {
            uint8_t bytes[] = { 0x98, cases[i].band[0], cases[i].band[1] };
            calibrated |= command_is(c, bytes, 3);
        }
        CHECK(calibrated);
    }
    lora_board(32, 1);
    CHECK(lora_k230_open(149999999u) == LORA_K230_BADARG);
    CHECK(lora_k230_open(960000001u) == LORA_K230_BADARG);
    CHECK(sx1262_model_commands() == 0);
}

static void test_lora_reopen_keeps_receiving(void)
{
    lora_board(32, 1);
    CHECK(lora_k230_open(915000000u) == LORA_K230_OK);
    size_t commands = sx1262_model_commands();
    CHECK(lora_k230_open(915000000u) == LORA_K230_OK);
    CHECK(sx1262_model_commands() == commands);
    CHECK(lora_k230_open(868000000u) == LORA_K230_OK);
    CHECK(sx1262_model_commands() > commands && sx1262_model_frequency() == 0x36400000u);
}

static void test_lora_scenario_with_a_small_fifo(void)
{
    lora_board(8, 1);
    lora_scenario();
    CHECK(dw_ssi_model_errors() == 0);
}

static void test_lora_poll_without_dio1_talks_to_nobody(void)
{
    lora_board(32, 1);
    CHECK(lora_k230_open(915000000u) == LORA_K230_OK);
    size_t commands = sx1262_model_commands();
    struct lora_k230_event event;
    for (int i = 0; i < 5; i++) {
        CHECK(lora_k230_poll(&event) == LORA_K230_OK && event.kind == LORA_K230_NOTHING);
    }
    CHECK(sx1262_model_commands() == commands);
}

static void test_lora_crc_error_is_dropped_and_cleared(void)
{
    lora_board(32, 1);
    CHECK(lora_k230_open(915000000u) == LORA_K230_OK);
    sx1262_model_receive_crc_error((const uint8_t *) "garbled", 7);
    struct lora_k230_event event;
    CHECK(lora_k230_poll(&event) == LORA_K230_OK && event.kind == LORA_K230_CRC_ERROR && event.len == 0);
    CHECK(sx1262_model_irq() == 0 && sx1262_model_mode() == 5);
    CHECK(lora_k230_poll(&event) == LORA_K230_OK && event.kind == LORA_K230_NOTHING);
}

static void test_lora_long_packet_through_a_small_fifo(void)
{
    lora_board(8, 1);
    CHECK(lora_k230_open(915000000u) == LORA_K230_OK);
    uint8_t packet[LORA_K230_MAX_PACKET];
    for (size_t i = 0; i < sizeof packet; i++) {
        packet[i] = (uint8_t) (i * 7 + 1);
    }
    CHECK(lora_k230_send(packet, sizeof packet) == LORA_K230_OK);
    CHECK(dw_ssi_model_errors() == 0);
    CHECK(sx1262_model_mode() == 6);
    CHECK(lora_k230_send(packet, 1) == LORA_K230_BUSY);
    CHECK(sx1262_model_finish_tx());
    uint8_t sent[256];
    CHECK(sx1262_model_sent(sent) == sizeof packet && memcmp(sent, packet, sizeof packet) == 0);
    /* The same through the receive path: a full-size packet read back. */
    struct lora_k230_event event;
    CHECK(lora_k230_poll(&event) == LORA_K230_OK && event.kind == LORA_K230_SENT);
    CHECK(sx1262_model_mode() == 5);
    sx1262_model_receive(packet, sizeof packet, 0x40, 0xf8, 0x44);
    CHECK(lora_k230_poll(&event) == LORA_K230_OK && event.kind == LORA_K230_PACKET);
    CHECK(event.len == sizeof packet && memcmp(event.data, packet, sizeof packet) == 0);
    CHECK(event.snr_pkt == -8 && event.signal_rssi == 0x44);
    CHECK(dw_ssi_model_errors() == 0);
}

static void test_lora_refuses_bad_packets_and_calls_before_open(void)
{
    lora_board(32, 1);
    struct lora_k230_event event;
    CHECK(lora_k230_send((const uint8_t *) "x", 1) == LORA_K230_NOT_OPEN);
    CHECK(lora_k230_poll(&event) == LORA_K230_NOT_OPEN);
    CHECK(lora_k230_open(915000000u) == LORA_K230_OK);
    uint8_t big[LORA_K230_MAX_PACKET + 1] = { 0 };
    CHECK(lora_k230_send(big, 0) == LORA_K230_BADARG);
    CHECK(lora_k230_send(big, sizeof big) == LORA_K230_BADARG);
}

static void test_lora_without_the_module(void)
{
    lora_board(32, 0);
    CHECK(lora_k230_open(915000000u) == LORA_K230_BUSY_TIMEOUT);
    /* One reset, BUSY waited on for RadioLib's 1 s, then given up. */
    CHECK(mock_now_us() >= 1000000u && mock_now_us() < 1100000u);
    struct lora_k230_event event;
    CHECK(lora_k230_poll(&event) == LORA_K230_NOT_OPEN);
}

/* ---- touch ---------------------------------------------------------------- */

static void touch_board(int powered)
{
    mock_reset(&mock_nominal);
    clocks();
    gpio_model_attach();
    gt9895_model_init();
    if (powered) {
        gt9895_model_wire_gpio();
    }
    dw_i2c_model_attach(I2C3, gt9895_model_target());
}

static void touch_scenario(void)
{
    CHECK(touch_k230_open() == TOUCH_K230_OK);
    struct gt9895_point point = { .id = 0, .type = 0, .x = 530, .y = 1200, .w = 20 };
    gt9895_model_report(&point, 1);
    struct touch_k230_event event;
    CHECK(touch_k230_poll(&event) == 1);
    /* 530 x 568 / 1060 = 284, 1200 x 1232 / 2400 = 616. */
    CHECK(event.action == TOUCH_K230_DOWN && event.x == 284 && event.y == 616);
}

static void test_touch_open_powers_resets_and_confirms(void)
{
    touch_board(1);
    CHECK(touch_k230_open() == TOUCH_K230_OK);
    CHECK(dw_i2c_model_errors() == 0);
    CHECK(gt9895_model_resets() == 1);
    CHECK(gpio_model_output(35) == 1 && gpio_model_output(24) == 1 && gpio_model_output(23) == -1);
    /* Pads: I2C3 on IO36/IO37, GPIO with drive 15 on IO23/IO24. */
    CHECK(mock_peek(IOMUX + 4 * 36) == 0x98f && mock_peek(IOMUX + 4 * 37) == 0x98f);
    CHECK(mock_peek(IOMUX + 4 * 23) == 0x19f && mock_peek(IOMUX + 4 * 24) == 0x19f);
    /* I2C3: fast mode at 100 MHz: HCNT 60, LCNT 130 (drv_i2c.c 526-531). */
    CHECK(last_write(I2C3 + 0x00) == 0x65);
    CHECK(last_write(I2C3 + 0x1c) == 60 && last_write(I2C3 + 0x20) == 130);
    CHECK(last_write(I2C3 + 0x30) == 0x200 && last_write(I2C3 + 0x04) == 0x5d);
    /* The device check, then nothing else. */
    CHECK(gt9895_model_transfers() == 2);
    CHECK(strcmp(gt9895_model_transfer(0), "w 00 01 00 00 aa aa aa aa aa aa aa aa") == 0);
    CHECK(strcmp(gt9895_model_transfer(1), "w 00 01 00 00 r 8") == 0);
    /* brl_power_on's order and waits: RST low and IOVDD on, 3 + 15 ms, RST
     * high, 4 ms, the check, 100 ms. */
    const struct mock_event *e = mock_events();
    long rst_high = -1;
    for (size_t i = 0; i < mock_event_count(); i++) {
        if (e[i].kind == MOCK_WRITE && e[i].addr == 0x9140B000u && (e[i].value & (1u << 24))) {
            rst_high = (long) i;
            break;
        }
    }
    CHECK(rst_high > 3);
    CHECK(e[rst_high - 1].kind == MOCK_READ && e[rst_high - 1].addr == 0x9140B000u);
    CHECK(e[rst_high - 2].kind == MOCK_DELAY && e[rst_high - 2].value == 15000);
    CHECK(e[rst_high - 3].kind == MOCK_DELAY && e[rst_high - 3].value == 3000);
    /* IOVDD (IO35, GPIO1 bit 3) went on just before. */
    CHECK(e[rst_high - 4].kind == MOCK_WRITE && e[rst_high - 4].addr == 0x9140C000u
          && (e[rst_high - 4].value & (1u << 3)));
    CHECK(e[rst_high + 1].kind == MOCK_DELAY && e[rst_high + 1].value == 4000);
    CHECK(e[mock_event_count() - 1].kind == MOCK_DELAY && e[mock_event_count() - 1].value == 100000);
    /* Once per firmware boot. */
    size_t events = mock_event_count();
    CHECK(touch_k230_open() == TOUCH_K230_OK && mock_event_count() == events);
}

static void test_touch_down_move_up(void)
{
    touch_board(1);
    touch_scenario();
    struct touch_k230_event event;
    /* Each report is read and cleared. */
    CHECK(strcmp(gt9895_model_transfer(2), "w 00 01 03 08 r 26") == 0);
    CHECK(strcmp(gt9895_model_transfer(3), "w 00 01 03 08 00") == 0);
    CHECK(gt9895_model_byte(0x10308) == 0);
    /* Nothing new: one read, no event, no clear. */
    CHECK(touch_k230_poll(&event) == 0);
    CHECK(gt9895_model_transfers() == 5);
    /* The same position again: no event. */
    struct gt9895_point point = { .id = 0, .type = 0, .x = 530, .y = 1200, .w = 20 };
    gt9895_model_report(&point, 1);
    CHECK(touch_k230_poll(&event) == 0);
    /* Moved; the edge clamps to 567 x 1231. */
    point.x = 1060;
    point.y = 2400;
    gt9895_model_report(&point, 1);
    CHECK(touch_k230_poll(&event) == 1);
    CHECK(event.action == TOUCH_K230_MOVE && event.x == 567 && event.y == 1231);
    /* Lifted: up where it was. */
    gt9895_model_report(NULL, 0);
    CHECK(touch_k230_poll(&event) == 1);
    CHECK(event.action == TOUCH_K230_UP && event.x == 567 && event.y == 1231);
    gt9895_model_report(NULL, 0);
    CHECK(touch_k230_poll(&event) == 0);
    CHECK(dw_i2c_model_errors() == 0);
}

static void test_touch_many_fingers_and_bad_reports(void)
{
    touch_board(1);
    CHECK(touch_k230_open() == TOUCH_K230_OK);
    struct gt9895_point points[3] = {
        { .id = 2, .x = 100, .y = 200, .w = 9 },
        { .id = 0, .x = 300, .y = 400, .w = 9 },
        { .id = 1, .x = 500, .y = 600, .w = 9 },
    };
    gt9895_model_report(points, 3);
    struct touch_k230_event event;
    CHECK(touch_k230_poll(&event) == 1);
    CHECK(event.action == TOUCH_K230_DOWN && event.x == 100 * 568 / 1060 && event.y == 200 * 1232 / 2400);
    /* More than two points: the rest at 0x10308 + 26. */
    CHECK(strcmp(gt9895_model_transfer(3), "w 00 01 03 22 r 8") == 0);
    /* A broken header: ignored and left alone. */
    gt9895_model_report(points, 1);
    gt9895_model_corrupt_header();
    size_t transfers = gt9895_model_transfers();
    CHECK(touch_k230_poll(&event) == 0);
    CHECK(gt9895_model_transfers() == transfers + 1);
    /* A stylus point is not a finger. */
    struct gt9895_point pen = { .id = 0, .type = 3, .x = 10, .y = 10 };
    gt9895_model_report(&pen, 1);
    CHECK(touch_k230_poll(&event) == 0);
}

static void test_touch_without_the_controller(void)
{
    touch_board(0);
    CHECK(touch_k230_open() == TOUCH_K230_NO_ANSWER);
    CHECK(touch_k230_open() == TOUCH_K230_NO_ANSWER);
    struct touch_k230_event event;
    CHECK(touch_k230_poll(&event) == TOUCH_K230_NO_ANSWER);
    CHECK(dw_i2c_model_errors() == 0);
}

static void test_touch_poll_before_open(void)
{
    touch_board(1);
    struct touch_k230_event event;
    CHECK(touch_k230_poll(&event) == TOUCH_K230_NOT_OPEN);
    CHECK(mock_event_count() == 0);
}

/* ---- power ---------------------------------------------------------------- */

static void power_board(void)
{
    mock_reset(&mock_nominal);
    pmu_model_attach();
}

static void power_scenario(void)
{
    enum power_k230_key key;
    CHECK(power_k230_open() == POWER_K230_OK);
    CHECK(power_k230_poll(&key) == 0);
    pmu_model_key(1);
    CHECK(power_k230_poll(&key) == 1 && key == POWER_K230_PRESSED);
    pmu_model_key(0);
    CHECK(power_k230_poll(&key) == 1 && key == POWER_K230_RELEASED);
    CHECK(power_k230_off() == POWER_K230_STILL_ON);
}

static void test_power_key_and_poweroff(void)
{
    power_board();
    enum power_k230_key key;
    CHECK(power_k230_poll(&key) == POWER_K230_NOT_OPEN);
    CHECK(power_k230_open() == POWER_K230_OK);
    /* Isolation off; 96000 and 256 ticks; the key's edge routed, detected,
     * rising first; OUT0 follows the software register. */
    CHECK((mock_peek(0x91103158u) & (1u << 5)) == 0);
    CHECK(mock_peek(PMU + 0x58) == 96000 && mock_peek(PMU + 0x64) == 256);
    CHECK((mock_peek(PMU + 0x48) & 0xfff) == (1u << 9));
    CHECK((mock_peek(PMU + 0x4c) & 0x1fff) == (1u << 9));
    CHECK(((mock_peek(PMU + 0x50) >> 16) & 7) == 1);
    CHECK((mock_peek(PMU + 0xa4) & 0x1c) == 0x14);
    /* A release before any press is not reported (the key waits for a
     * rising edge). */
    pmu_model_key(0);
    CHECK(power_k230_poll(&key) == 0);
    pmu_model_key(1);
    CHECK(power_k230_poll(&key) == 1 && key == POWER_K230_PRESSED);
    CHECK(((mock_peek(PMU + 0x50) >> 16) & 7) == 3);
    CHECK(power_k230_poll(&key) == 0);
    pmu_model_key(0);
    CHECK(power_k230_poll(&key) == 1 && key == POWER_K230_RELEASED);
    CHECK(!pmu_model_cut());
    CHECK(power_k230_off() == POWER_K230_STILL_ON);
    CHECK(pmu_model_cut());
    CHECK(mock_peek(PMU + 0x3c) == 2);
    CHECK((mock_peek(PMU + 0x40) & 0xfff) == (1u << 11));
    const struct mock_event *last = &mock_events()[mock_event_count() - 1];
    CHECK(last->kind == MOCK_DELAY && last->value == 1000000);
}

/* ---- UART3 ---------------------------------------------------------------- */

static void test_uart3_divisor_from_the_programmed_clock(void)
{
    mock_reset(&mock_nominal);
    clocks();
    mock_poke(CMU_UART_I2C, (3u << 24) | (1u << 9));
    CHECK(uart_k230_init() == UART_K230_OK);
    /* The leaf divider back to 1/1 with bit 31 (sysctl_clk.c 2719-2721). */
    CHECK(last_write(CMU_UART_I2C) == ((3u << 24) | (1u << 31)));
    /* 1.6 GHz / 16 = 100 MHz: 868.06 = 54 x 16 + 4.06. */
    CHECK(last_write(UART3 + 0x00) == 54 && last_write(UART3 + 0x04) == 0 && last_write(UART3 + 0xc0) == 4);
    CHECK(last_write(UART3 + 0x0c) == 0x03 && last_write(UART3 + 0x08) == 0x81);
    CHECK(last_write(UART3 + 0x10) == 0 && last_write(UART3 + 0x1c) == 0);
    CHECK(count(MOCK_WRITE, UART3 + 0x04) == 2); /* IER 0, DLH: never enabled */
    CHECK(mock_peek(IOMUX + 4 * 50) == 0x88f && mock_peek(IOMUX + 4 * 51) == 0x90f);
    /* The divisor latch is open exactly around DLL/DLH/DLF. */
    CHECK(last_write_index(UART3 + 0xc0) < last_write_index(UART3 + 0x0c));
}

static void test_uart3_bypassed_pll(void)
{
    mock_reset(&mock_nominal);
    clocks();
    mock_poke(PLL0_CFG1, 1u << 19);
    /* 24 MHz / 16 = 1.5 MHz: 13.02 / 16 rounds to 0, so 1 and no fraction,
     * 93750 baud; the vendor only refuses a clock that is too fast. */
    CHECK(uart_k230_init() == UART_K230_OK);
    CHECK(last_write(UART3 + 0x00) == 1 && last_write(UART3 + 0xc0) == 0);
}

#else

static void test_no_devices_build_touches_nothing(void)
{
    mock_reset(&mock_nominal);
    struct touch_k230_event touch;
    struct lora_k230_event lora;
    enum power_k230_key key;
    CHECK(touch_k230_open() == TOUCH_K230_NO_DEVICE);
    CHECK(touch_k230_poll(&touch) == TOUCH_K230_NO_DEVICE);
    CHECK(lora_k230_open(915000000u) == LORA_K230_NO_DEVICE);
    CHECK(lora_k230_send((const uint8_t *) "x", 1) == LORA_K230_NO_DEVICE);
    CHECK(lora_k230_poll(&lora) == LORA_K230_NO_DEVICE && lora.kind == LORA_K230_NOTHING);
    CHECK(power_k230_open() == POWER_K230_NO_DEVICE);
    CHECK(power_k230_poll(&key) == POWER_K230_NO_DEVICE);
    CHECK(power_k230_off() == POWER_K230_NO_DEVICE);
    CHECK(mock_event_count() == 0);
}

#endif

static void run(const char *name, void (*test)(void))
{
    fflush(stdout);
    pid_t pid = fork();
    if (pid == 0) {
        test();
        exit(0);
    }
    int status = 0;
    if (pid < 0 || waitpid(pid, &status, 0) != pid || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        printf("FAIL %s\n", name);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

#define RUN(test) run(#test, test)

int main(int argc, char **argv)
{
    if (argc == 4 && strcmp(argv[1], "trace") == 0) {
#if COPROC_K230_DEVICES
        if (strcmp(argv[2], "lora") == 0) {
            lora_board(32, 1);
            lora_scenario();
            return sx1262_model_write_trace(argv[3]) == 0 ? 0 : 1;
        }
        if (strcmp(argv[2], "touch") == 0) {
            touch_board(1);
            touch_scenario();
            return gt9895_model_write_log(argv[3]) == 0 ? 0 : 1;
        }
        if (strcmp(argv[2], "power") == 0) {
            power_board();
            power_scenario();
            return mock_write_trace(argv[3]) == 0 ? 0 : 1;
        }
#endif
        fprintf(stderr, "unknown trace %s\n", argv[2]);
        return 2;
    }
    if (argc != 1) {
        fprintf(stderr, "usage: board_k230_test [trace lora|touch|power <file>]\n");
        return 2;
    }
#if COPROC_K230_DEVICES
    RUN(test_lora_open_configures_the_radio);
    RUN(test_lora_frequency_is_configuration);
    RUN(test_lora_reopen_keeps_receiving);
    RUN(test_lora_scenario_with_a_small_fifo);
    RUN(test_lora_poll_without_dio1_talks_to_nobody);
    RUN(test_lora_crc_error_is_dropped_and_cleared);
    RUN(test_lora_long_packet_through_a_small_fifo);
    RUN(test_lora_refuses_bad_packets_and_calls_before_open);
    RUN(test_lora_without_the_module);
    RUN(test_touch_open_powers_resets_and_confirms);
    RUN(test_touch_down_move_up);
    RUN(test_touch_many_fingers_and_bad_reports);
    RUN(test_touch_without_the_controller);
    RUN(test_touch_poll_before_open);
    RUN(test_power_key_and_poweroff);
    RUN(test_uart3_divisor_from_the_programmed_clock);
    RUN(test_uart3_bypassed_pll);
#else
    RUN(test_no_devices_build_touches_nothing);
#endif
    printf("board_k230_test (COPROC_K230_DEVICES=%d): %s\n", COPROC_K230_DEVICES, failures ? "FAILED" : "passed");
    return failures ? 1 : 0;
}
