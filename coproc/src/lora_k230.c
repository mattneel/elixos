/*
 * Elixos coprocessor firmware: the SX1262 LoRa module (HPDTEK HPD16A) of the
 * T-Display K230 (lora_k230.h).
 *
 * Wiring and bus are LilyGO's RT-Smart build's (LT-RT =
 * Xinyuan-LilyGO/T-Display-K230_canmv_rt @ abb07090,
 * canmv_k230/src/rtsmart/mpp/userapps/sample/sample_display/ui_brookesia/
 * src/app_examples/phone/lora/):
 *   Lora.cpp 23-30, 42-43     CS IO14, SCK IO15, MOSI IO16, MISO IO17,
 *                              NRESET IO5, BUSY IO19 (DIO1 IO20 per the
 *                              schematic; LilyGO polls the IRQ register)
 *   Lora.cpp 669-676           the module's LDO enable IO44, high = on
 *   lora_lib/k230Hal.cpp 189-207, 253
 *                              IO14-17 as QSPI0 (pad function 3), IO5/19/20
 *                              as GPIO; `spi1` (QSPI0 at 0x91582000,
 *                              drv_spi.c 429) at 5 MHz, mode 0
 *   sample_display/fpioa/rt_fpioa.c 106-113, 266, 410
 *                              the pad words
 * The command sequence is LilyGO's RadioLib build (lora_lib/, MIT, RadioLib
 * by Jan Gromes) as Lora.cpp 788-805 configures the SX1262 SKU:
 * begin(915, 125, 10, 6, 0x12, 22, 16, 3.3, false), then setCRC(false):
 * modules/SX126x/SX126x.cpp 12-91 (begin), 190-221 (reset), 2153-2189
 * (findChip), 1653-1704 (setTCXO), 2081-2138 (config), SX1262.cpp 8-29,
 * 53-119 (frequency, image calibration, power). Elixos takes the frequency
 * from its configuration and keeps the rest. coproc/test/board_trace/
 * compiles that RadioLib build against an SX1262 model on the build host and
 * checks our command stream against it but for the documented differences
 * (elixos-lora.patch):
 *   1. receiving is continuous (SetRx timeout 0xFFFFFF) with every receive
 *      IRQ on DIO1, and DIO1 (IO20) is polled before any SPI traffic;
 *      LilyGO re-arms a 10 s receive every 100 ms and polls the IRQ register;
 *   2. a send starts from standby (RadioLib's transmit() does, SX126x.cpp
 *      224-226) and its end is cleared and followed by receiving again
 *      (finishTransmit, 573-579, then startReceive);
 *   3. a packet is read at the start pointer GetRxBufferStatus reports (as
 *      LilyGO's Linux RadioLib does, LT-BSP RadioLib SX126x.cpp 556-565),
 *      not at offset 0.
 */
#include <string.h>

#include "board.h"
#include "k230_io.h"
#include "k230_mmio.h"
#include "k230_spi.h"
#include "lora_k230.h"

#if !defined(COPROC_K230_DEVICES)
#error "COPROC_K230_DEVICES is a build parameter (coproc/CMakeLists.txt)"
#endif

#if COPROC_K230_DEVICES

#define QSPI0_BASE 0x91582000u
#define SPI_HZ 5000000u

#define PIN_NRESET 5u
#define PIN_CS 14u
#define PIN_SCK 15u
#define PIN_MOSI 16u
#define PIN_MISO 17u
#define PIN_BUSY 19u
#define PIN_DIO1 20u
#define PIN_POWER 44u

/* rt_fpioa.c defaults (106, 107, 112-113, 410) with function 3 (QSPI0). */
#define PAD_QSPI0_CS0 (K230_PAD_SEL(3) | K230_PAD_OE | K230_PAD_PU | K230_PAD_DS(7))
#define PAD_QSPI0_CLK (K230_PAD_SEL(3) | K230_PAD_OE | K230_PAD_DS(7))
#define PAD_QSPI0_DATA (K230_PAD_SEL(3) | K230_PAD_GPIO)
/* IO44 as the vendor U-Boot DT leaves it (GPIO, pull-up; LT-RT
 * canmv_k230/src/uboot/uboot/arch/riscv/dts/k230_canmv_v3p0.dts 156). */
#define PAD_POWER (K230_PAD_GPIO | K230_PAD_PU)

/* RadioLib's SX126x.h opcodes and values. */
#define OP_SET_STANDBY 0x80u
#define OP_READ_REGISTER 0x1du
#define OP_WRITE_REGISTER 0x0du
#define OP_GET_STATUS 0xc0u
#define OP_GET_PACKET_TYPE 0x11u
#define OP_GET_IRQ_STATUS 0x12u
#define OP_GET_RX_BUFFER_STATUS 0x13u
#define OP_GET_PACKET_STATUS 0x14u
#define OP_CLEAR_IRQ_STATUS 0x02u
#define OP_SET_DIO_IRQ_PARAMS 0x08u
#define OP_SET_BUFFER_BASE 0x8fu
#define OP_SET_PACKET_PARAMS 0x8cu
#define OP_SET_MODULATION_PARAMS 0x8bu
#define OP_WRITE_BUFFER 0x0eu
#define OP_READ_BUFFER 0x1eu
#define OP_SET_TX 0x83u
#define OP_SET_RX 0x82u

#define IRQ_TX_DONE 0x0001u
#define IRQ_RX_DONE 0x0002u
#define IRQ_HEADER_ERR 0x0020u
#define IRQ_CRC_ERR 0x0040u
#define IRQ_TIMEOUT 0x0200u
#define IRQ_ALL 0x43ffu
/* RADIOLIB_SX126X_IRQ_RX_DEFAULT: RX_DONE | TIMEOUT | CRC_ERR | HEADER_ERR. */
#define IRQ_RX_DEFAULT 0x0262u

#define REG_VERSION 0x0320u
#define REG_SYNC_WORD 0x0740u
#define REG_IQ_CONFIG 0x0736u
#define REG_SENSITIVITY 0x0889u
#define REG_TX_CLAMP 0x08d8u
#define REG_OCP 0x08e7u

/* LilyGO's SX1262 configuration (Lora.cpp 789-798, SX126x.cpp 79). */
#define LORA_SF 10u
#define LORA_BW_CODE 0x04u /* 125 kHz */
#define LORA_BW_KHZ 125u
#define LORA_CR 0x02u /* 4/6 */
#define LORA_SYNC_WORD 0x12u
#define LORA_POWER_DBM 22u
#define LORA_PREAMBLE 16u
#define TCXO_3V3 0x07u
#define TCXO_DELAY 0x000140u /* 5000 us / 15.625 us */
#define OCP_140MA 0x38u

#define BUSY_POLL_US 10u
#define BUSY_LIMIT_US 1000000u

static struct k230_spi spi;
static int opened; /* 0 never, 1 open, < 0 the failure */
static uint32_t open_freq;
static int sending;
/* The packet parameters RadioLib keeps: CRC (0 off, 1 on). */
static uint8_t crc_type;

static int wait_busy(void)
{
    for (uint32_t waited = 0; k230_gpio_get(PIN_BUSY); waited += BUSY_POLL_US) {
        if (waited >= BUSY_LIMIT_US) {
            return LORA_K230_BUSY_TIMEOUT;
        }
        k230_delay_us(BUSY_POLL_US);
    }
    return LORA_K230_OK;
}

/* RadioLib's SPIparseStatus (SX126x.cpp 2140-2151). */
static int parse_status(uint8_t status)
{
    uint8_t command = status & 0x0eu;
    if (command == 0x06u || command == 0x08u || command == 0x0au) {
        return LORA_K230_FAILED;
    }
    if (status == 0x00u || status == 0xffu) {
        return LORA_K230_NOT_FOUND;
    }
    return LORA_K230_OK;
}

/* Module::SPItransferStream (Module.cpp 319-444): BUSY low before, the
 * transfer, then 1 us and BUSY low again; the status is the second byte. */
static int transfer(const uint8_t *out, uint8_t *in, size_t len, int wait_after)
{
    int result = wait_busy();
    if (result != LORA_K230_OK) {
        return result;
    }
    if (k230_spi_transfer(&spi, out, in, len) != K230_SPI_OK) {
        return LORA_K230_SPI_TIMEOUT;
    }
    if (wait_after) {
        k230_delay_us(1);
        result = wait_busy();
        if (result != LORA_K230_OK) {
            return result;
        }
    }
    return parse_status(in[1]);
}

static int command(const uint8_t *out, size_t len)
{
    uint8_t in[LORA_K230_MAX_PACKET + 3];
    return transfer(out, in, len, 1);
}

#define COMMAND(...)                                                  \
    do {                                                              \
        static const uint8_t bytes_[] = { __VA_ARGS__ };              \
        int result_ = command(bytes_, sizeof bytes_);                 \
        if (result_ != LORA_K230_OK) {                                \
            return result_;                                           \
        }                                                             \
    } while (0)

#define CHECK(call)                     \
    do {                                \
        int result_ = (call);           \
        if (result_ != LORA_K230_OK) {  \
            return result_;             \
        }                               \
    } while (0)

/* A read command: `head` bytes, then the status byte, then `n` data bytes. */
static int read_command(const uint8_t *head, size_t head_len, uint8_t *data, size_t n)
{
    uint8_t out[LORA_K230_MAX_PACKET + 4] = { 0 };
    uint8_t in[LORA_K230_MAX_PACKET + 4];
    memcpy(out, head, head_len);
    int result = transfer(out, in, head_len + 1 + n, 1);
    memcpy(data, in + head_len + 1, n);
    return result;
}

static int get_status(void)
{
    uint8_t head[] = { OP_GET_STATUS };
    uint8_t status;
    return read_command(head, 1, &status, 1);
}

static int read_register(uint16_t addr, uint8_t *data, size_t n)
{
    uint8_t head[] = { OP_READ_REGISTER, (uint8_t) (addr >> 8), (uint8_t) addr };
    return read_command(head, 3, data, n);
}

/* readRegister with RADIOLIB_SPI_PARANOID: a GetStatus after it
 * (SX126x.cpp 1806). */
static int read_register_checked(uint16_t addr, uint8_t *value)
{
    CHECK(read_register(addr, value, 1));
    return get_status();
}

static int write_register(uint16_t addr, uint8_t value)
{
    uint8_t out[] = { OP_WRITE_REGISTER, (uint8_t) (addr >> 8), (uint8_t) addr, value };
    return command(out, sizeof out);
}

static int get_packet_type(void)
{
    uint8_t head[] = { OP_GET_PACKET_TYPE };
    uint8_t type;
    return read_command(head, 1, &type, 1);
}

static int standby(void)
{
    COMMAND(OP_SET_STANDBY, 0x00);
    return LORA_K230_OK;
}

/* SX126x::reset (SX126x.cpp 190-221): the pulse, then SetStandby until the
 * radio takes it, every 10 ms for 1 s. A BUSY line stuck high has used up
 * that second by itself. */
static int reset(void)
{
    k230_gpio_output(PIN_NRESET, 0);
    k230_delay_us(1000);
    k230_gpio_set(PIN_NRESET, 1);
    int result = LORA_K230_OK;
    for (int tries = 0; tries <= 100; tries++) {
        result = standby();
        if (result != LORA_K230_FAILED && result != LORA_K230_NOT_FOUND) {
            return result;
        }
        k230_delay_us(10000);
    }
    return result;
}

/* SX126x::findChip (SX126x.cpp 2153-2189): up to 10 resets until the
 * version string reads "SX1261". Elixos gives up at once when a reset
 * itself failed (that took RadioLib's full second already) instead of
 * spending 10 s with the VM blocked. */
static int find_chip(void)
{
    for (int i = 0; i < 10; i++) {
        int result = reset();
        if (result != LORA_K230_OK) {
            return result;
        }
        uint8_t version[16];
        (void) read_register(REG_VERSION, version, sizeof version);
        if (memcmp(version, "SX1261", 6) == 0) {
            return LORA_K230_OK;
        }
        k230_delay_us(10000);
    }
    return LORA_K230_NOT_FOUND;
}

/* SX126x::setTCXO(3.3) (SX126x.cpp 1653-1704). */
static int set_tcxo(void)
{
    CHECK(standby());
    uint8_t head[] = { 0x17 };
    uint8_t errors[2];
    CHECK(read_command(head, 1, errors, 2));
    if ((((uint16_t) errors[0] << 8) | errors[1]) & 0x0020u) {
        COMMAND(0x07, 0x00, 0x00);
    }
    COMMAND(0x97, TCXO_3V3, (uint8_t) (TCXO_DELAY >> 16), (uint8_t) (TCXO_DELAY >> 8), (uint8_t) TCXO_DELAY);
    return LORA_K230_OK;
}

/* SX126x::config(LoRa) (SX126x.cpp 2081-2138), with begin()'s defaults
 * (SF 9 for the CAD parameters). */
static int config(void)
{
    COMMAND(OP_SET_BUFFER_BASE, 0x00, 0x00);
    COMMAND(0x8a, 0x01);
    COMMAND(0x93, 0x20);
    COMMAND(0x88, 0x03, 9 + 13, 0x0a, 0x00, 0x00, 0x00, 0x00);
    COMMAND(OP_CLEAR_IRQ_STATUS, 0x43, 0xff);
    COMMAND(OP_SET_DIO_IRQ_PARAMS, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
    /* Calibrate all blocks without waiting for BUSY, then 5 ms. */
    static const uint8_t calibrate[] = { 0x89, 0x7f };
    uint8_t in[2];
    CHECK(transfer(calibrate, in, sizeof calibrate, 0));
    k230_delay_us(5000);
    return get_status();
}

/* fixInvertedIQ (SX126x.cpp 2057-2075) and setPacketParams (1943-1948)
 * for a standard IQ, explicit-header LoRa packet of `len` bytes. */
static int set_packet_params(uint8_t len)
{
    uint8_t iq;
    CHECK(read_register_checked(REG_IQ_CONFIG, &iq));
    CHECK(write_register(REG_IQ_CONFIG, iq | 0x04u));
    uint8_t out[] = { OP_SET_PACKET_PARAMS, (uint8_t) (LORA_PREAMBLE >> 8), (uint8_t) LORA_PREAMBLE, 0x00, len,
                      crc_type, 0x00 };
    return command(out, sizeof out);
}

/* setModulationParams (SX126x.cpp 1920-1929): LDRO on when a symbol lasts
 * 16 ms or more. */
static int set_modulation(uint8_t sf, uint8_t bw_code, unsigned bw_khz, uint8_t cr)
{
    CHECK(get_packet_type());
    uint8_t ldro = ((1u << sf) / bw_khz) >= 16 ? 1 : 0;
    uint8_t out[] = { OP_SET_MODULATION_PARAMS, sf, bw_code, cr, ldro };
    return command(out, sizeof out);
}

/* SX1262::setFrequency (SX1262.cpp 53-97) and setFrequencyRaw
 * (SX126x.cpp 1991-1995): frf = f * 2^25 / 32 MHz. */
static int set_frequency(uint32_t freq_hz)
{
    unsigned mhz = freq_hz / 1000000u;
    uint8_t band[2] = { 0, 0 };
    if (mhz >= 902 && mhz <= 928) {
        band[0] = 0xe1, band[1] = 0xe9;
    } else if (mhz >= 863 && mhz <= 870) {
        band[0] = 0xd7, band[1] = 0xdb;
    } else if (mhz >= 779 && mhz <= 787) {
        band[0] = 0xc1, band[1] = 0xc5;
    } else if (mhz >= 470 && mhz <= 510) {
        band[0] = 0x75, band[1] = 0x81;
    } else if (mhz >= 430 && mhz <= 440) {
        band[0] = 0x6b, band[1] = 0x6f;
    } else {
        /* calibrateImageRejection(f - 4, f + 4) (SX126x.cpp 1844-1850):
         * floor((f - 5) / 4) made odd, ceil((f + 5) / 4) made odd. */
        uint32_t low_khz = freq_hz / 1000u - 5000u;
        uint32_t high_khz = freq_hz / 1000u + 5000u;
        uint8_t low = (uint8_t) (low_khz / 4000u);
        uint8_t high = (uint8_t) ((high_khz + 3999u) / 4000u);
        band[0] = (low % 2) ? low : (uint8_t) (low - 1);
        band[1] = (high % 2) ? high : (uint8_t) (high + 1);
    }
    uint8_t calibrate[] = { 0x98, band[0], band[1] };
    CHECK(command(calibrate, sizeof calibrate));
    uint32_t frf = (uint32_t) (((uint64_t) freq_hz << 25) / 32000000u);
    uint8_t out[] = { 0x86, (uint8_t) (frf >> 24), (uint8_t) (frf >> 16), (uint8_t) (frf >> 8), (uint8_t) frf };
    return command(out, sizeof out);
}

/* SX126x::begin and SX1262::begin as Lora.cpp 800-802 call them. */
static int begin(uint32_t freq_hz)
{
    CHECK(find_chip());
    crc_type = 0x01;
    CHECK(reset());
    CHECK(standby());
    CHECK(set_tcxo());
    CHECK(config());
    /* setCodingRate(6) at begin()'s SF 9 / 500 kHz. */
    CHECK(set_modulation(9, 0x06, 500, LORA_CR));
    /* setSyncWord(0x12): (sw & 0xF0) | 0x4, (sw & 0x0F) << 4 | 0x4. */
    CHECK(get_packet_type());
    uint8_t sync[] = { OP_WRITE_REGISTER, (uint8_t) (REG_SYNC_WORD >> 8), (uint8_t) REG_SYNC_WORD,
                       (uint8_t) ((LORA_SYNC_WORD & 0xf0u) | 0x04u), (uint8_t) (((LORA_SYNC_WORD & 0x0fu) << 4) | 0x04u) };
    CHECK(command(sync, sizeof sync));
    /* setPreambleLength(16). */
    CHECK(get_packet_type());
    CHECK(set_packet_params(0xff));
    /* DC-DC regulator, 140 mA current limit, DIO2 as RF switch. */
    COMMAND(0x96, 0x01);
    CHECK(write_register(REG_OCP, OCP_140MA));
    COMMAND(0x9d, 0x01);
    /* setCRC(2), invertIQ(false). */
    CHECK(get_packet_type());
    CHECK(set_packet_params(0xff));
    CHECK(get_packet_type());
    CHECK(set_packet_params(0xff));
    /* SX1262::begin: setSpreadingFactor(10), setBandwidth(125). */
    CHECK(set_modulation(LORA_SF, 0x06, 500, LORA_CR));
    CHECK(set_modulation(LORA_SF, LORA_BW_CODE, LORA_BW_KHZ, LORA_CR));
    CHECK(set_frequency(freq_hz));
    /* fixPaClamping (SX126x.cpp 2015-2031). */
    uint8_t clamp;
    CHECK(read_register_checked(REG_TX_CLAMP, &clamp));
    CHECK(write_register(REG_TX_CLAMP, clamp | 0x1eu));
    /* setOutputPower(22) (SX1262.cpp 99-119): PA config 4/7/0/1, 22 dBm with
     * a 200 us ramp, the current limit kept. */
    uint8_t ocp;
    CHECK(read_register_checked(REG_OCP, &ocp));
    COMMAND(0x95, 0x04, 0x07, 0x00, 0x01);
    COMMAND(0x8e, LORA_POWER_DBM, 0x04);
    CHECK(write_register(REG_OCP, ocp));
    /* Lora.cpp 802: setCRC(false). */
    crc_type = 0x00;
    CHECK(get_packet_type());
    return set_packet_params(0xff);
}

/* startReceive(0xFFFFFF, RX_DEFAULT, RX_DEFAULT, 0) (SX126x.cpp 585-596,
 * 663-689): continuous, every receive IRQ on DIO1. */
static int start_receive(void)
{
    COMMAND(OP_SET_DIO_IRQ_PARAMS, (uint8_t) (IRQ_RX_DEFAULT >> 8), (uint8_t) IRQ_RX_DEFAULT,
            (uint8_t) (IRQ_RX_DEFAULT >> 8), (uint8_t) IRQ_RX_DEFAULT, 0x00, 0x00, 0x00, 0x00);
    COMMAND(OP_SET_BUFFER_BASE, 0x00, 0x00);
    COMMAND(OP_CLEAR_IRQ_STATUS, 0x43, 0xff);
    CHECK(get_packet_type());
    CHECK(set_packet_params(0xff));
    COMMAND(OP_SET_RX, 0xff, 0xff, 0xff);
    return LORA_K230_OK;
}

static int open_radio(uint32_t freq_hz)
{
    /* k230Hal::init (k230Hal.cpp 189-207): the pads; Lora.cpp 669-676: the
     * module's power. */
    k230_pad(PIN_NRESET, K230_PAD_GPIO);
    k230_pad(PIN_CS, PAD_QSPI0_CS0);
    k230_pad(PIN_SCK, PAD_QSPI0_CLK);
    k230_pad(PIN_MOSI, PAD_QSPI0_DATA);
    k230_pad(PIN_MISO, PAD_QSPI0_DATA);
    k230_pad(PIN_BUSY, K230_PAD_GPIO);
    k230_pad(PIN_DIO1, K230_PAD_GPIO);
    k230_pad(PIN_POWER, PAD_POWER);
    k230_gpio_input(PIN_BUSY);
    k230_gpio_input(PIN_DIO1);
    k230_gpio_output(PIN_POWER, 1);
    k230_spi_init(&spi, QSPI0_BASE, k230_ssi1_clk_hz(), SPI_HZ);
    sending = 0;
    CHECK(begin(freq_hz));
    return start_receive();
}

int lora_k230_open(uint32_t freq_hz)
{
    if (freq_hz < 150000000u || freq_hz > 960000000u) {
        return LORA_K230_BADARG;
    }
    if (opened == 1 && open_freq == freq_hz) {
        return LORA_K230_OK;
    }
    int result = open_radio(freq_hz);
    opened = result == LORA_K230_OK ? 1 : result;
    open_freq = freq_hz;
    return result;
}

/* standby (SX126x.cpp 224-226), then startTransmit (508-571). */
int lora_k230_send(const uint8_t *packet, size_t len)
{
    if (opened != 1) {
        return LORA_K230_NOT_OPEN;
    }
    if (len == 0 || len > LORA_K230_MAX_PACKET) {
        return LORA_K230_BADARG;
    }
    if (sending) {
        return LORA_K230_BUSY;
    }
    CHECK(standby());
    CHECK(get_packet_type());
    CHECK(set_packet_params((uint8_t) len));
    COMMAND(OP_SET_DIO_IRQ_PARAMS, 0x02, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00);
    COMMAND(OP_SET_BUFFER_BASE, 0x00, 0x00);
    uint8_t out[LORA_K230_MAX_PACKET + 2] = { OP_WRITE_BUFFER, 0x00 };
    memcpy(out + 2, packet, len);
    CHECK(command(out, len + 2));
    COMMAND(OP_CLEAR_IRQ_STATUS, 0x43, 0xff);
    /* fixSensitivity (SX126x.cpp 1997-2013): bit 2 set below 500 kHz. */
    uint8_t sensitivity;
    CHECK(read_register_checked(REG_SENSITIVITY, &sensitivity));
    CHECK(get_packet_type());
    CHECK(write_register(REG_SENSITIVITY, sensitivity | 0x04u));
    COMMAND(OP_SET_TX, 0x00, 0x00, 0x00);
    sending = 1;
    return LORA_K230_OK;
}

static int get_irq(uint16_t *irq)
{
    uint8_t head[] = { OP_GET_IRQ_STATUS };
    uint8_t data[2];
    CHECK(read_command(head, 1, data, 2));
    *irq = (uint16_t) ((data[0] << 8) | data[1]);
    return LORA_K230_OK;
}

/* readData (SX126x.cpp 691-731), getSNR (1340-1354), getRSSI(true)
 * (1326-1331). */
static int read_packet(struct lora_k230_event *event)
{
    CHECK(get_status());
    uint16_t irq;
    CHECK(get_irq(&irq));
    int bad = (irq & (IRQ_CRC_ERR | IRQ_HEADER_ERR)) != 0;
    CHECK(get_packet_type());
    uint8_t head[] = { OP_GET_RX_BUFFER_STATUS };
    uint8_t buffer[2];
    CHECK(read_command(head, 1, buffer, 2));
    uint8_t read[] = { OP_READ_BUFFER, buffer[1] };
    CHECK(read_command(read, 2, event->data, buffer[0]));
    event->len = buffer[0];
    COMMAND(OP_SET_BUFFER_BASE, 0x00, 0x00);
    COMMAND(OP_CLEAR_IRQ_STATUS, 0x43, 0xff);
    if (bad) {
        event->kind = LORA_K230_CRC_ERROR;
        event->len = 0;
        return LORA_K230_OK;
    }
    uint8_t status_head[] = { OP_GET_PACKET_STATUS };
    uint8_t status[3];
    CHECK(get_packet_type());
    CHECK(read_command(status_head, 1, status, 3));
    event->snr_pkt = (int8_t) status[1];
    CHECK(read_command(status_head, 1, status, 3));
    event->signal_rssi = status[2];
    event->kind = LORA_K230_PACKET;
    return LORA_K230_OK;
}

int lora_k230_poll(struct lora_k230_event *event)
{
    event->kind = LORA_K230_NOTHING;
    event->len = 0;
    if (opened != 1) {
        return LORA_K230_NOT_OPEN;
    }
    if (!k230_gpio_get(PIN_DIO1)) {
        return LORA_K230_OK;
    }
    uint16_t irq;
    CHECK(get_irq(&irq));
    if (sending && (irq & IRQ_TX_DONE)) {
        sending = 0;
        /* finishTransmit (SX126x.cpp 573-579). */
        COMMAND(OP_CLEAR_IRQ_STATUS, 0x43, 0xff);
        CHECK(standby());
        CHECK(start_receive());
        event->kind = LORA_K230_SENT;
        return LORA_K230_OK;
    }
    if (irq & IRQ_RX_DONE) {
        return read_packet(event);
    }
    /* A header error or a timeout without a packet. */
    COMMAND(OP_CLEAR_IRQ_STATUS, 0x43, 0xff);
    if (irq & IRQ_HEADER_ERR) {
        event->kind = LORA_K230_CRC_ERROR;
    }
    return LORA_K230_OK;
}

#else

int lora_k230_open(uint32_t freq_hz)
{
    (void) freq_hz;
    return LORA_K230_NO_DEVICE;
}

int lora_k230_send(const uint8_t *packet, size_t len)
{
    (void) packet;
    (void) len;
    return LORA_K230_NO_DEVICE;
}

int lora_k230_poll(struct lora_k230_event *event)
{
    event->kind = LORA_K230_NOTHING;
    event->len = 0;
    return LORA_K230_NO_DEVICE;
}

#endif
