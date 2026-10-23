/*
 * Elixos coprocessor firmware: the Goodix GT9895 touch controller of the
 * T-Display K230 (touch_k230.h).
 *
 * Bus and address are LilyGO's RT-Smart build's (LT-RT =
 * Xinyuan-LilyGO/T-Display-K230_canmv_rt @ abb07090,
 * canmv_k230/src/rtsmart/rtsmart/kernel/bsp/maix3/):
 *   configs/k230_canmv_v3p0_defconfig 241-243   GT9895 on "i2c3" at 0x5d
 *   drivers/interdrv/i2c/drv_i2c.c 413-429       I2C3 at 0x91408000, 400 kHz
 *                                                 (1213)
 *   drivers/extdrv/touch/gt9895.c 52-84, 99      the report at register
 *                                                 0x00010308, a 4-byte
 *                                                 big-endian address written,
 *                                                 then a repeated-start read
 *   canmv_k230/src/uboot/uboot/arch/riscv/dts/k230_canmv_v3p0.dts 120, 122,
 *     136, 139, 141                               the pads of IO23 (INT), IO24
 *                                                 (RST), IO35, IO36/IO37 (I2C3)
 * The report layout, the power-on and reset timing, the device check and
 * the clearing of the report after each read are LilyGO's Linux driver's
 * (LT-BSP = Xinyuan-LilyGO/T-Display-K230 @ 0ad78192,
 * k230_bsp/overlay/buildroot-overlay/linux/0034-gt9895-touch.patch, Goodix's
 * GPL "Berlin" driver, used here as a specification only):
 *   1661-1699   power on: RST low, IOVDD (IO35, the schematic's IO35_DISEN
 *               switch of TP_VDDIO) on, 3 ms, 15 ms (AVDD is not switched on
 *               this board), RST high, 4 ms, the device check, 100 ms
 *   1530-1560, 1490-1491
 *               the device check: 8 x 0xAA to 0x10000, read back, 3 tries
 *               5 ms apart
 *   2544-2578, 2619-2721, 2725-2778, 11011-11024
 *               26 bytes at the report address (an 8-byte header and two
 *               8-byte points and their checksum), status byte 0x80 for a
 *               touch, the number of points in byte 2, more points at +26,
 *               each point id << 4 | type, x and y little-endian at +2 and
 *               +4; header and points each followed by a u16 sum
 *   2780-2790   after a read, 0x00 written to the report address
 * LilyGO's RT-Smart driver reads 90 bytes there and never clears, resets or
 * checks; coproc/test/board_trace/ compiles it against the GT9895 model and
 * checks that it and this driver read the same address and decode the same
 * points (elixos-touch.patch has the differences).
 *
 * Coordinates: the controller reports 0..1060 x 0..2400 (LT-BSP
 * 0031-riscv-dts-canaan-add-rm69a10-display.patch 86-87, the panel-max-x/y
 * of LilyGO's Linux DT; LilyGO's launcher calibrates to the same,
 * k230_launcher/k230_phone_ui/src/main.c 72-75), same axes as the panel;
 * they are scaled to 568 x 1232. (LilyGO's RT-Smart driver divides x by 1024,
 * gt9895.c 44; which is right only the board can tell.)
 *
 * Events: the first finger (lowest index in the report) makes one
 * {down, X, Y}, then {move, X, Y} whenever its position changes, and {up,
 * X, Y} at its last position when the report has no finger. The report is
 * polled: the INT line (IO23) pulses on a report (falling edge in LilyGO's
 * Linux DT), which a poll every 20 ms could miss, so the status byte is
 * what tells.
 */
#include <string.h>

#include "board.h"
#include "k230_i2c.h"
#include "k230_io.h"
#include "k230_mmio.h"
#include "touch_k230.h"

#if !defined(COPROC_K230_DEVICES)
#error "COPROC_K230_DEVICES is a build parameter (coproc/CMakeLists.txt)"
#endif

#if COPROC_K230_DEVICES

#define I2C3_BASE 0x91408000u
#define GT9895_ADDR 0x5du
#define PIN_INT 23u
#define PIN_RST 24u
#define PIN_IOVDD 35u
#define PIN_SCL 36u
#define PIN_SDA 37u

/* Board DT: GPIO with IE, OE, drive 15 (IO23/24); I2C3 is function 1 of
 * IO36/IO37, IE, OE, drive 7; IO35 as the panel driver sets it. */
#define PAD_GPIO_DS15 (K230_PAD_IE | K230_PAD_OE | K230_PAD_DS(15) | K230_PAD_ST)
#define PAD_I2C3 (K230_PAD_SEL(1) | K230_PAD_GPIO)

#define REPORT_ADDR 0x00010308u
#define CONFIRM_ADDR 0x00010000u
#define CONFIRM_VALUE 0xaau
#define HEAD_LEN 8u
#define POINT_LEN 8u
#define FIRST_READ (HEAD_LEN + 2u * POINT_LEN + 2u)
#define MAX_TOUCH 10u
#define STATUS_TOUCH 0x80u
#define POINT_STYLUS_HOVER 0x01u
#define POINT_STYLUS 0x03u

#define RAW_WIDTH 1060u
#define RAW_HEIGHT 2400u

static int opened; /* 0 never, 1 open, < 0 the failure */
static int down;
static uint16_t last_x, last_y;

static void address(uint8_t *out, uint32_t reg)
{
    out[0] = (uint8_t) (reg >> 24);
    out[1] = (uint8_t) (reg >> 16);
    out[2] = (uint8_t) (reg >> 8);
    out[3] = (uint8_t) reg;
}

static int read_reg(uint32_t reg, uint8_t *data, size_t len)
{
    uint8_t out[4];
    address(out, reg);
    return k230_i2c_write_read(I2C3_BASE, GT9895_ADDR, out, sizeof out, data, len);
}

static int write_reg(uint32_t reg, const uint8_t *data, size_t len)
{
    uint8_t out[4 + 8];
    address(out, reg);
    memcpy(out + 4, data, len);
    return k230_i2c_write(I2C3_BASE, GT9895_ADDR, out, 4 + len);
}

/* brl_dev_confirm. */
static int confirm(void)
{
    uint8_t pattern[8];
    uint8_t back[8];
    memset(pattern, CONFIRM_VALUE, sizeof pattern);
    for (int tries = 0; tries < 3; tries++) {
        if (write_reg(CONFIRM_ADDR, pattern, sizeof pattern) != K230_I2C_OK
            || read_reg(CONFIRM_ADDR, back, sizeof back) != K230_I2C_OK) {
            return TOUCH_K230_NO_ANSWER;
        }
        if (memcmp(pattern, back, sizeof back) == 0) {
            return TOUCH_K230_OK;
        }
        k230_delay_us(5000);
    }
    return TOUCH_K230_CONFIRM_FAILED;
}

static int open_touch(void)
{
    k230_pad(PIN_INT, PAD_GPIO_DS15);
    k230_pad(PIN_RST, PAD_GPIO_DS15);
    k230_pad(PIN_IOVDD, K230_PAD_GPIO);
    k230_pad(PIN_SCL, PAD_I2C3);
    k230_pad(PIN_SDA, PAD_I2C3);
    k230_gpio_input(PIN_INT);
    k230_i2c_init(I2C3_BASE, k230_i2c3_clk_hz());

    /* brl_power_on. */
    k230_gpio_output(PIN_RST, 0);
    k230_gpio_output(PIN_IOVDD, 1);
    k230_delay_us(3000);
    k230_delay_us(15000);
    k230_gpio_set(PIN_RST, 1);
    k230_delay_us(4000);
    int result = confirm();
    if (result != TOUCH_K230_OK) {
        return result;
    }
    k230_delay_us(100000);
    return TOUCH_K230_OK;
}

int touch_k230_open(void)
{
    if (opened == 0) {
        int result = open_touch();
        opened = result == TOUCH_K230_OK ? 1 : result;
    }
    return opened == 1 ? TOUCH_K230_OK : opened;
}

/* checksum_cmp(CHECKSUM_MODE_U8_LE): a u16 sum of the bytes, then the sum
 * little-endian. */
static int checksum_ok(const uint8_t *data, size_t size)
{
    uint32_t sum = 0;
    for (size_t i = 0; i + 2 < size; i++) {
        sum += data[i];
    }
    return (sum & 0xffffu) == (uint32_t) (data[size - 2] | (data[size - 1] << 8));
}

static uint16_t scale(uint32_t raw, uint32_t range, uint32_t size)
{
    uint32_t value = raw * size / range;
    return (uint16_t) (value >= size ? size - 1 : value);
}

static int clear(void)
{
    uint8_t zero = 0;
    return write_reg(REPORT_ADDR, &zero, 1) == K230_I2C_OK ? TOUCH_K230_OK : TOUCH_K230_BUS_ERROR;
}

int touch_k230_poll(struct touch_k230_event *event)
{
    if (opened != 1) {
        return opened == 0 ? TOUCH_K230_NOT_OPEN : opened;
    }
    uint8_t report[HEAD_LEN + MAX_TOUCH * POINT_LEN + 2];
    if (read_reg(REPORT_ADDR, report, FIRST_READ) != K230_I2C_OK) {
        return TOUCH_K230_BUS_ERROR;
    }
    if (report[0] == 0x00 || !checksum_ok(report, HEAD_LEN)) {
        return 0;
    }
    if (!(report[0] & STATUS_TOUCH)) {
        /* A request or gesture event: nothing for Elixos, but done. */
        return clear() == TOUCH_K230_OK ? 0 : TOUCH_K230_BUS_ERROR;
    }
    unsigned count = report[2] & 0x0fu;
    if (count > MAX_TOUCH) {
        return 0;
    }
    if (count > 2
        && read_reg(REPORT_ADDR + FIRST_READ, report + FIRST_READ, (count - 2) * POINT_LEN) != K230_I2C_OK) {
        return TOUCH_K230_BUS_ERROR;
    }
    if (clear() != TOUCH_K230_OK) {
        return TOUCH_K230_BUS_ERROR;
    }
    if (count > 0) {
        const uint8_t *point = report + HEAD_LEN;
        uint8_t type = point[0] & 0x0fu;
        size_t checked = (type == POINT_STYLUS || type == POINT_STYLUS_HOVER) ? 2u * POINT_LEN + 2u
                                                                             : count * POINT_LEN + 2u;
        if (!checksum_ok(point, checked) || type == POINT_STYLUS || type == POINT_STYLUS_HOVER
            || (point[0] >> 4) >= MAX_TOUCH) {
            return 0;
        }
        uint16_t x = scale((uint32_t) (point[2] | (point[3] << 8)), RAW_WIDTH, TOUCH_K230_WIDTH);
        uint16_t y = scale((uint32_t) (point[4] | (point[5] << 8)), RAW_HEIGHT, TOUCH_K230_HEIGHT);
        if (down && x == last_x && y == last_y) {
            return 0;
        }
        event->action = down ? TOUCH_K230_MOVE : TOUCH_K230_DOWN;
        event->x = last_x = x;
        event->y = last_y = y;
        down = 1;
        return 1;
    }
    if (!down) {
        return 0;
    }
    down = 0;
    event->action = TOUCH_K230_UP;
    event->x = last_x;
    event->y = last_y;
    return 1;
}

#else

int touch_k230_open(void)
{
    return TOUCH_K230_NO_DEVICE;
}

int touch_k230_poll(struct touch_k230_event *event)
{
    (void) event;
    return TOUCH_K230_NO_DEVICE;
}

#endif
