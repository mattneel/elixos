/*
 * Elixos coprocessor firmware: the RM69A10 panel on the K230 (M33).
 *
 * Brings up the 568 x 1232 AMOLED over the K230's display block exactly as
 * LilyGO's bare-metal U-Boot logo path does, then lets the VO scan the §12
 * framebuffer out by itself: the VO's OSD4 layer reads the region's pixels
 * (RGB565, stride 1136) every frame and the DSI host streams them to the
 * panel in video mode, so a commit reaches the panel without any push. The
 * status band is OSD5, a 568 x 28 layer over rows 0-27 fed from a buffer of
 * this firmware (panel_k230_status).
 *
 * The register sequence is the one of (docs/notes/k230-panel.md has the
 * line-by-line map):
 *   Xinyuan-LilyGO/T-Display-K230 @ 0ad78192bab04585ae51bb847695fdc74658f134,
 *   k230_bsp/overlay/buildroot-overlay/boot/uboot/u-boot-2022.10-overlay/
 *   board/canaan/common/logo/ with CONFIG_K230_BARE_DISP_LOGO_RM69A10:
 *     k230_logo.c 353-354 (power domain, then st7701_init), 144-193 the
 *     power domain, 316-334 the timing and D-PHY parameters;
 *     st7701.c 847-879 the order, 27-73 reset and enable, 75-106 the DCS
 *     list, 778-844 the DSI/VO/PHY attributes;
 *     display_logo.c 28-272 DSI host, pixel clock and display reset,
 *     278-603 VO, 692-725 the OSD4 scan-out, 802-1075 the 2-lane D-PHY;
 *   plus board/canaan/common/k230_board_common.c 363-411 (k230_gpio).
 * This file is not a copy of that code (it is GPL U-Boot code): it is our own
 * implementation of the same register accesses, in the same order, with the
 * same values and delays. coproc/test/panel_trace/ compiles the vendor files
 * against a register model on the build host and checks that the trace of
 * panel_k230_open() is the vendor's, but for these documented differences
 * (coproc/test/panel_trace/elixos.patch):
 *   1. IO22, IO25 and IO35 are muxed as GPIO outputs (the board DT's values,
 *      T-Display-K230_canmv_rt @ abb07090,
 *      canmv_k230/src/uboot/uboot/arch/riscv/dts/k230_canmv_v3p0.dts
 *      118/124/136) and IO35 (IO35_DISEN, the panel supply switch on the
 *      schematic) is driven high 10 ms before the reset pulse; the vendor's
 *      U-Boot relies on its own pinmux and never drives IO35.
 *   2. A GPIO made an output gets its data bit set or cleared in the data
 *      register's own value; k230_gpio('o') writes the direction register's
 *      value into the data register, driving every other output of the bank.
 *   3. The VO scaler coefficient tables (vo_table.h, GPL-2.0, 320 writes) are
 *      not loaded: only the video layers 0-2 scale and they stay disabled.
 *   4. OSD4 scans RGB565 (format 2, Linux canaan_vo.c) from COPROC_FB_ADDR +
 *      4096 with stride 1136, instead of XRGB8888 (format 3) from 0x1f000000.
 * Status reads the vendor ignores fail here (power domain) or are reported
 * after the vendor's whole sequence has run (D-PHY).
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "board.h"
#include "k230_mmio.h"
#include "panel_k230.h"

#if !defined(COPROC_PANEL_K230) || !defined(COPROC_FB_ADDR)
#error "COPROC_PANEL_K230 and COPROC_FB_ADDR are build parameters (coproc/CMakeLists.txt)"
#endif

/* Register blocks (display_logo.h 348-354, platform.h 76/96/106). */
#define CLK_BASE 0x91100000u
#define RST_BASE 0x91101000u
#define PWR_BASE 0x91103000u
#define IOMUX_BASE 0x91105000u
#define GPIO_BASE 0x9140B000u
#define VO_BASE 0x90840000u
#define DSI_BASE 0x90850000u
#define TXPHY_BASE 0x90850400u

/* DesignWare MIPI DSI host registers (display_logo.h 296-336). */
#define DSI_PWR_UP 0x04
#define DSI_CLKMGR_CFG 0x08
#define DSI_DPI_VCID 0x0c
#define DSI_DPI_COLOR_CODING 0x10
#define DSI_PCKHDL_CFG 0x2c
#define DSI_GEN_VCID 0x30
#define DSI_MODE_CFG 0x34
#define DSI_VID_MODE_CFG 0x38
#define DSI_VID_PKT_SIZE 0x3c
#define DSI_VID_NUM_CHUNKS 0x40
#define DSI_VID_NULL_SIZE 0x44
#define DSI_VID_HSA_TIME 0x48
#define DSI_VID_HBP_TIME 0x4c
#define DSI_VID_HLINE_TIME 0x50
#define DSI_VID_VSA_LINES 0x54
#define DSI_VID_VBP_LINES 0x58
#define DSI_VID_VFP_LINES 0x5c
#define DSI_VID_VACTIVE_LINES 0x60
#define DSI_CMD_MODE_CFG 0x68
#define DSI_GEN_HDR 0x6c
#define DSI_GEN_PLD_DATA 0x70
#define DSI_LPCLK_CTRL 0x94
#define DSI_PHY_TMR_LPCLK_CFG 0x98
#define DSI_PHY_TMR_CFG 0x9c
#define DSI_PHY_RSTZ 0xa0
#define DSI_PHY_IF_CFG 0xa4
#define DSI_PHY_STATUS 0xb0
#define DSI_PHY_TST_CTRL0 0xb4
#define DSI_PHY_TST_CTRL1 0xb8
#define DSI_INT_MSK0 0xc4
#define DSI_INT_MSK1 0xc8

/* The K230's TX D-PHY wrapper. */
#define TXDPHY_CFG0 0x00
#define TXDPHY_CFG1 0x04
#define TXDPHY_PLL_CFG0 0x08
#define TXDPHY_PLL_CFG1 0x10
#define TXDPHY_SELECT_PHY1 0x400000u

/* VO registers (display_logo.h 6-280). */
#define VO_SOFT_RST_CTL 0x000
#define VO_REG_LOAD_CTL 0x004
#define VO_DMA_SW_CTL 0x008
#define VO_DMA_RD_CTL_OUT 0x00c
#define VO_DMA_ARB_MODE 0x010
#define VO_DISP_XZONE_CTL 0x0c0
#define VO_DISP_YZONE_CTL 0x0c4
#define VO_DISP_HSYNC_CTL 0x100
#define VO_DISP_HSYNC1_CTL 0x104
#define VO_DISP_VSYNC1_CTL 0x108
#define VO_DISP_HSYNC2_CTL 0x10c
#define VO_DISP_VSYNC2_CTL 0x110
#define VO_DISP_ENABLE 0x118
#define VO_DISP_TOTAL_SIZE 0x11c
#define VO_OSD_RGB2YUV_CTL 0x340
#define VO_DISP_YUV2RGB_CTL 0x380
#define VO_DISP_MIX_LAYER_GLB_EN 0x3c0
#define VO_DISP_MIX_LAYER_GLB_ALPHA0 0x3c4
#define VO_DISP_MIX_LAYER_GLB_ALPHA1 0x3c8
#define VO_DISP_MIX_SEL 0x3cc
#define VO_DISP_BACKGROUND 0x3d0
#define VO_DISP_DITH_CTL 0x3d4
#define VO_DISP_CLUT_CTL 0x3d8
#define VO_DISP_IRQ0_CTL 0x3e0
#define VO_DISP_IRQ1_CTL 0x3e4
#define VO_DISP_IRQ2_CTL 0x3e8
#define VO_DISP_DRAW_FRAME_CMD 0x780
#define VO_LOAD 0x11u

/* The OSD layers: 0-2 at 0x280 + 0x40 n, 3-7 at 0x850 + 0x30 (n - 3). */
#define OSD_INFO 0x00
#define OSD_SIZE 0x04
#define OSD_VLU_ADDR0 0x08
#define OSD_ALP_ADDR0 0x0c
#define OSD_VLU_ADDR1 0x10
#define OSD_ALP_ADDR1 0x14
#define OSD_DMA_CTRL 0x18
#define OSD_STRIDE 0x1c
#define OSD_ADDR_SEL_MODE 0x20
#define OSD_FORMAT_RGB565 0x02u
#define FB_OSD 4u
#define STATUS_OSD 5u

static uintptr_t osd(unsigned n, unsigned reg)
{
    return VO_BASE + (n <= 2 ? 0x280u + 0x40u * n : 0x850u + 0x30u * (n - 3)) + reg;
}

/* The layer's position registers (VO_DISP_OSD<n>_XCTL; YCTL is + 4). */
static uintptr_t osd_xctl(unsigned n)
{
    return VO_BASE + (n <= 2 ? 0x0e8u + 8u * n : 0x820u + 8u * (n - 3));
}

/* The VO's enable bit of an OSD layer: OSD4 is bit 8, OSD5 bit 9. */
static uint32_t osd_enable_bit(unsigned n)
{
    return 1u << (n + 4);
}

/* Video layers 0-2: their configuration, burst length and address mode. */
static uintptr_t layer_cfg(unsigned l)
{
    return VO_BASE + (l <= 1 ? 0xa00u + 0x20u * l : 0x200u + 0x40u * (l - 2));
}

static uintptr_t layer_blenth(unsigned l)
{
    return VO_BASE + (l <= 1 ? 0x144u + 0x94u * l : 0x218u + 0x40u * (l - 2));
}

static uintptr_t layer_addr_sel(unsigned l)
{
    return VO_BASE + (l <= 1 ? 0xa1cu + 0x20u * l : 0x224u + 0x40u * (l - 2));
}

/* ---- the board's numbers (k230_logo.c 316-334, st7701.c 786) ---------- */

/* Pixel clock 594 MHz / (14 + 1) = 39.6 MHz: 39.6e6 / (748 * 1268) = 41.8 Hz. */
#define PIXCLK_DIV 14u
#define PCLK_KHZ 39600u
/* Lane rate: 24 bits x 39.6 MHz / 2 lanes = 475.2 Mbit/s = 24 MHz x 99 / 5. */
#define PHY_KHZ 475200u
#define HTOTAL 748u
#define HACT 568u
#define HSA 40u
#define HBP 40u
#define VTOTAL 1268u
#define VACT 1232u
#define VSA 16u
#define VBP 16u
#define VFP 4u
/* D-PHY PLL: M = 97 + 2, N = 4 + 1, VCO range 0x19; hsfreqrange 0x87. */
#define PLL_M 97u
#define PLL_N 4u
#define PLL_VCO 0x19u
#define HSFREQ 0x87u
/* PHY_IF_CFG: stop-wait time 0x28 << 8, lanes - 1. */
#define DSI_LANES_FIELD 1u
#define LP_DIV 8u
#define VTTH_LINE 10u
#define BACKGROUND 0xffffffu

/* The pads (board DT: function 0 = GPIO, IE, OE, drive strength, Schmitt). */
#define PAD_GPIO_OUT(ds) ((1u << 8) | (1u << 7) | ((uint32_t) (ds) << 1) | 1u)
#define PIN_LCD_RST 22u
#define PIN_LCD_EN 25u
#define PIN_DISP_EN 35u

/* ---- register helpers ----------------------------------------------------- */

static void wr(uintptr_t addr, uint32_t value)
{
    k230_mmio_write32(addr, value);
}

static uint32_t rd(uintptr_t addr)
{
    return k230_mmio_read32(addr);
}

static void delay_ms(uint32_t ms)
{
    k230_delay_us(ms * 1000u);
}

/* reg with bits hi..lo replaced by value (value is not masked). */
static uint32_t field(uint32_t reg, unsigned hi, unsigned lo, uint32_t value)
{
    uint32_t mask = (~0u << lo) & (~0u >> (31 - hi));
    return (reg & ~mask) | (value << lo);
}

/* ---- power, pads, GPIO ------------------------------------------------------ */

static int power_display_domain(void)
{
    /* disp_lpi_ctl: power-up request and its write enable; disp_lpi_state. */
    wr(PWR_BASE + 0x3c, rd(PWR_BASE + 0x3c) | (1u << 1) | (1u << 17));
    k230_delay_us(500);
    return (rd(PWR_BASE + 0x40) & (1u << 1)) ? PANEL_K230_OK : PANEL_K230_POWER_TIMEOUT;
}

static uintptr_t gpio_data(unsigned pin)
{
    return GPIO_BASE + (pin / 32) * 0x1000u;
}

static void gpio_set(unsigned pin, int level)
{
    uint32_t bit = 1u << (pin % 32);
    uint32_t data = rd(gpio_data(pin));
    wr(gpio_data(pin), level ? data | bit : data & ~bit);
}

static void gpio_output(unsigned pin, int level)
{
    uintptr_t direction = gpio_data(pin) + 4;
    wr(direction, rd(direction) | (1u << (pin % 32)));
    gpio_set(pin, level);
}

static void panel_power_and_reset(void)
{
    wr(IOMUX_BASE + 4 * PIN_LCD_RST, PAD_GPIO_OUT(15));
    wr(IOMUX_BASE + 4 * PIN_LCD_EN, PAD_GPIO_OUT(7));
    wr(IOMUX_BASE + 4 * PIN_DISP_EN, PAD_GPIO_OUT(7));
    gpio_output(PIN_DISP_EN, 1);
    delay_ms(10);

    gpio_output(PIN_LCD_RST, 1);
    delay_ms(200);
    gpio_set(PIN_LCD_RST, 0);
    delay_ms(200);
    gpio_set(PIN_LCD_RST, 1);
    delay_ms(200);
    gpio_output(PIN_LCD_EN, 1);
}

static void display_reset(void)
{
    wr(RST_BASE + 0x90, 0);
    delay_ms(20);
    wr(RST_BASE + 0x90, 0xffffffffu);
    delay_ms(20);
    wr(VO_BASE + VO_SOFT_RST_CTL, 0x0f);
    wr(VO_BASE + VO_DMA_SW_CTL, 0);
    wr(VO_BASE + VO_REG_LOAD_CTL, 0);
    delay_ms(10);
}

static void set_pixel_clock(void)
{
    uint32_t reg = field(rd(CLK_BASE + 0x78), 10, 3, PIXCLK_DIV);
    wr(CLK_BASE + 0x78, reg | (1u << 31));
}

/* ---- D-PHY ------------------------------------------------------------------ */

struct phy_code {
    uint8_t code;
    uint8_t value;
};

/* hsfreqrange, slew rate calibration, mpll_prog, prg_on_lane0. */
static const struct phy_code phy0_codes[] = {
    { 0x0c, 0x03 }, { 0x44, HSFREQ }, { 0xa0, 0x40 }, { 0xa4, 0x11 },
    { 0xa4, 0x85 }, { 0xa3, 0x01 }, { 0x1f, 0x01 }, { 0x4a, 0x40 },
};
/* The same for PHY1, which also drives the clock lane (0x30). */
static const struct phy_code phy1_codes[] = {
    { 0x44, HSFREQ }, { 0x30, 0xff }, { 0xa0, 0x40 }, { 0xa4, 0x11 },
    { 0xa4, 0x85 }, { 0xa3, 0x01 }, { 0x1f, 0x01 }, { 0x4a, 0x40 },
};
/* PLL lock thresholds and lock select. */
static const struct phy_code pll_codes[] = {
    { 0x14, 0x02 }, { 0x15, 0x60 }, { 0x16, 0x03 }, { 0x1d, 0x01 },
};

static void phy_test_write(uint8_t code, uint8_t value)
{
    wr(DSI_BASE + DSI_PHY_TST_CTRL1, 0x10000u + code);
    wr(DSI_BASE + DSI_PHY_TST_CTRL0, 2);
    wr(DSI_BASE + DSI_PHY_TST_CTRL0, 0);
    wr(DSI_BASE + DSI_PHY_TST_CTRL1, value);
    wr(DSI_BASE + DSI_PHY_TST_CTRL0, 2);
    wr(DSI_BASE + DSI_PHY_TST_CTRL0, 0);
}

static void phy_test_writes(const struct phy_code *codes, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        phy_test_write(codes[i].code, codes[i].value);
    }
}

/* Both PHYs' cfgclkfreqrange = 0x28. */
static void phy_cfgclk(void)
{
    uint32_t reg = field(rd(TXPHY_BASE + TXDPHY_CFG0), 7, 2, 0x28);
    wr(TXPHY_BASE + TXDPHY_CFG0, field(reg, 13, 8, 0x28));
}

static void phy_pll(void)
{
    uintptr_t cfg0 = TXPHY_BASE + TXDPHY_PLL_CFG0;
    uintptr_t cfg1 = TXPHY_BASE + TXDPHY_PLL_CFG1;
    uint32_t reg = field(rd(cfg1), 9, 9, 1); /* shadow_clear pulse */
    wr(cfg1, reg);
    wr(cfg1, field(reg, 9, 9, 0));
    wr(cfg1, field(rd(cfg1), 1, 0, 1)); /* clksel */
    wr(cfg0, field(field(rd(cfg0), 26, 17, PLL_M), 30, 27, PLL_N));
    wr(cfg1, field(rd(cfg1), 16, 11, PLL_VCO));
    wr(cfg0, field(rd(cfg0), 6, 0, 0x10)); /* cpbias_cntrl */
    wr(cfg0, field(rd(cfg0), 9, 8, 0)); /* gmp_cntrl */
    wr(cfg0, field(rd(cfg0), 16, 11, 0)); /* int_cntrl */
    wr(cfg1, field(rd(cfg1), 8, 3, 0x8)); /* prop_cntrl */
    phy_test_writes(pll_codes, sizeof pll_codes / sizeof pll_codes[0]);
    reg = field(rd(cfg1), 10, 10, 1); /* update pulse */
    wr(cfg1, reg);
    delay_ms(20);
    wr(cfg1, field(reg, 10, 10, 0));
}

static void phy0_config(void)
{
    wr(TXPHY_BASE + TXDPHY_CFG1, 0);
    wr(DSI_BASE + DSI_PHY_RSTZ, 0xc);
    wr(DSI_BASE + DSI_PHY_TST_CTRL0, 1);
    wr(DSI_BASE + DSI_PHY_TST_CTRL0, 0);
    phy_test_writes(phy0_codes, sizeof phy0_codes / sizeof phy0_codes[0]);
    phy_cfgclk();
    phy_pll();
    wr(TXPHY_BASE + TXDPHY_CFG0, 0x28a0);
    wr(DSI_BASE + DSI_PHY_RSTZ, 0xc);
}

/* 0: PHY1's state machine reported 0x580 within 1000 polls 20 ms apart. */
static int phy1_config(void)
{
    wr(TXPHY_BASE + TXDPHY_CFG1, TXDPHY_SELECT_PHY1);
    wr(DSI_BASE + DSI_PHY_TST_CTRL0, 1);
    delay_ms(20);
    wr(DSI_BASE + DSI_PHY_TST_CTRL0, 0);
    phy_test_write(0x0c, 0x00);
    wr(TXPHY_BASE + TXDPHY_CFG1, TXDPHY_SELECT_PHY1);
    phy_test_writes(phy1_codes, sizeof phy1_codes / sizeof phy1_codes[0]);
    phy_cfgclk();
    wr(TXPHY_BASE + TXDPHY_CFG0, field(rd(TXPHY_BASE + TXDPHY_CFG0), 1, 1, 0)); /* PHY1 basedir */
    wr(DSI_BASE + DSI_PHY_RSTZ, 0x4);
    wr(DSI_BASE + DSI_PHY_RSTZ, 0xd);
    wr(DSI_BASE + DSI_PHY_RSTZ, 0xf);
    phy_test_write(0x03, 0x80);
    unsigned polls = 0;
    while (rd(DSI_BASE + DSI_PHY_TST_CTRL1) != 0x580) {
        phy_test_write(0x03, 0x80);
        delay_ms(20);
        if (++polls >= 1000) {
            return -1;
        }
    }
    return 0;
}

/* 0: PHY_STATUS read 0x1fbd (PLL locked, lanes in stop state) within 1 s. */
static int phy_wait_ready(void)
{
    unsigned polls = 0;
    while (rd(DSI_BASE + DSI_PHY_STATUS) != 0x1fbd) {
        if (++polls > 100000) {
            printf("elixos coproc: panel: D-PHY status 0x%04x, not 0x1fbd\n",
                (unsigned) rd(DSI_BASE + DSI_PHY_STATUS));
            return -1;
        }
        k230_delay_us(10);
    }
    return 0;
}

static int dphy_2lane(void)
{
    int failed = 0;
    wr(DSI_BASE + DSI_DPI_VCID, 0);
    phy0_config();
    failed |= phy1_config();
    (void) rd(TXPHY_BASE + TXDPHY_CFG1);
    wr(TXPHY_BASE + TXDPHY_CFG1, 0);
    wr(DSI_BASE + DSI_PHY_RSTZ, 0x5);
    wr(DSI_BASE + DSI_PHY_RSTZ, 0x7);
    failed |= phy_wait_ready();
    delay_ms(20);
    wr(DSI_BASE + DSI_LPCLK_CTRL, 1);
    (void) rd(TXPHY_BASE + TXDPHY_CFG1);
    wr(TXPHY_BASE + TXDPHY_CFG1, TXDPHY_SELECT_PHY1);
    failed |= phy_wait_ready();
    (void) rd(DSI_BASE + DSI_PHY_STATUS);
    return failed;
}

/* ---- DSI host --------------------------------------------------------------- */

/* Pixel clocks to lane byte clocks, rounded up (display_logo.c 55-67). */
static uint32_t lane_bytes(uint32_t pixels)
{
    uint64_t bytes = (uint64_t) pixels * PHY_KHZ / 8;
    return (uint32_t) (bytes / PCLK_KHZ + (bytes % PCLK_KHZ != 0));
}

static void dsi_setup(void)
{
    wr(DSI_BASE + DSI_PHY_IF_CFG, 0x2800u + DSI_LANES_FIELD);
    wr(DSI_BASE + DSI_CLKMGR_CFG, 0x100u + LP_DIV);
    wr(DSI_BASE + DSI_GEN_VCID, 0x303);
    wr(DSI_BASE + DSI_VID_PKT_SIZE, HACT);
    wr(DSI_BASE + DSI_VID_NUM_CHUNKS, 0);
    wr(DSI_BASE + DSI_VID_NULL_SIZE, 0);
    wr(DSI_BASE + DSI_VID_HSA_TIME, lane_bytes(HSA));
    wr(DSI_BASE + DSI_VID_HBP_TIME, lane_bytes(HBP));
    wr(DSI_BASE + DSI_VID_HLINE_TIME, lane_bytes(HTOTAL));
    wr(DSI_BASE + DSI_VID_VSA_LINES, VSA);
    wr(DSI_BASE + DSI_VID_VBP_LINES, VBP);
    wr(DSI_BASE + DSI_VID_VFP_LINES, VFP);
    wr(DSI_BASE + DSI_VID_VACTIVE_LINES, VACT);
    /* Command mode, burst video settings, every command in LP. */
    wr(DSI_BASE + DSI_MODE_CFG, 1);
    wr(DSI_BASE + DSI_VID_MODE_CFG, 0x3f02);
    wr(DSI_BASE + DSI_CMD_MODE_CFG, 0x10f7f01);
    wr(DSI_BASE + DSI_PCKHDL_CFG, 0x1c);
    wr(DSI_BASE + DSI_PWR_UP, 1);
}

/* Video mode, 24-bit DPI, commands in HS, continuous clock, then start. */
static void dsi_start(void)
{
    wr(DSI_BASE + DSI_DPI_COLOR_CODING, 0x005);
    wr(DSI_BASE + DSI_PHY_TMR_CFG, 0x320068);
    wr(DSI_BASE + DSI_PHY_TMR_LPCLK_CFG, 0x2e0080);
    wr(DSI_BASE + DSI_INT_MSK0, 0xffffffffu);
    wr(DSI_BASE + DSI_INT_MSK1, 0xffffffffu);
    wr(DSI_BASE + DSI_MODE_CFG, 0);
    wr(DSI_BASE + DSI_CMD_MODE_CFG, 0);
    wr(DSI_BASE + DSI_LPCLK_CTRL, 3);
    wr(DSI_BASE + DSI_LPCLK_CTRL, 1);
}

/* ---- the RM69A10's DCS list (st7701.c 75-106) ------------------------------ */

enum { DCS_LONG, DCS_SHORT };

struct dcs {
    uint8_t kind; /* DCS_LONG: long write 0x39; DCS_SHORT: 0x05 or 0x15 */
    uint8_t len;
    uint8_t wait_ms; /* after the packet's own 3 ms */
    uint8_t bytes[5];
};

static const struct dcs rm69a10_init[] = {
    { DCS_LONG, 2, 0, { 0xfe, 0xfd } }, /* manufacturer command page */
    { DCS_LONG, 2, 0, { 0x80, 0xfc } },
    { DCS_LONG, 2, 0, { 0xfe, 0x00 } }, /* back to the user page */
    { DCS_LONG, 5, 0, { 0x2a, 0x00, 0x00, 0x02, 0x37 } }, /* columns 0-567 */
    { DCS_LONG, 5, 0, { 0x2b, 0x00, 0x00, 0x04, 0xcf } }, /* rows 0-1231 */
    { DCS_LONG, 5, 0, { 0x31, 0x00, 0x03, 0x02, 0x34 } }, /* partial columns */
    { DCS_LONG, 5, 0, { 0x30, 0x00, 0x00, 0x04, 0xcf } }, /* partial rows */
    { DCS_SHORT, 1, 0, { 0x12 } }, /* partial mode on */
    { DCS_SHORT, 2, 0, { 0x35, 0x00 } }, /* tearing effect on (TE unconnected) */
    { DCS_SHORT, 2, 0, { 0x51, 0xfe } }, /* brightness 254 */
    { DCS_SHORT, 1, 120, { 0x11 } }, /* sleep out */
    { DCS_SHORT, 1, 10, { 0x29 } }, /* display on */
    { DCS_SHORT, 2, 0, { 0x3a, 0x77 } }, /* 24 bits per pixel */
};

static void dcs_send(const struct dcs *packet)
{
    uint32_t header;
    if (packet->kind == DCS_LONG) {
        for (unsigned i = 0; i < packet->len; i += 4) {
            uint32_t word = 0;
            for (unsigned j = 0; j < 4 && i + j < packet->len; j++) {
                word |= (uint32_t) packet->bytes[i + j] << (8 * j);
            }
            wr(DSI_BASE + DSI_GEN_PLD_DATA, word);
        }
        header = 0x39u | ((uint32_t) packet->len << 8);
    } else if (packet->len == 1) {
        header = 0x05u | ((uint32_t) packet->bytes[0] << 8);
    } else {
        header = 0x15u | ((uint32_t) packet->bytes[0] << 8) | ((uint32_t) packet->bytes[1] << 16);
    }
    wr(DSI_BASE + DSI_GEN_HDR, header);
    delay_ms(3);
    if (packet->wait_ms) {
        delay_ms(packet->wait_ms);
    }
}

/* ---- VO --------------------------------------------------------------------- */

struct reg_value {
    uint16_t offset;
    uint32_t value;
};

/* DMA arbitration, priorities and IDs, line buffers; everything off. */
static const struct reg_value vo_wrap[] = {
    { VO_DMA_SW_CTL, 0x11 }, { VO_DMA_RD_CTL_OUT, 0x88 }, { VO_DMA_ARB_MODE, 0 },
    { 0x14, 0x1010101 }, { 0x18, 0x1010101 }, { 0x1c, 0x1010101 }, { 0x20, 0x1010101 },
    { 0x24, 0x1010101 }, { 0x28, 0x1010101 }, { 0x2c, 0x1010101 }, { 0x30, 0x1010101 },
    { 0x34, 0x76543210 }, { 0x3c, 0x76543210 }, { 0x44, 0x76543210 }, { 0x4c, 0x76543210 },
    { 0x38, 0xfedcba98 }, { 0x40, 0xfedcba98 }, { 0x48, 0xfedcba98 }, { 0x50, 0xfedcba98 },
    { 0x80, 0x701 }, { 0x84, 0x701 }, { 0x88, 0x701 }, { 0x8c, 0x701 }, { 0x90, 0x701 },
    { 0x94, 0x701 }, { 0x98, 0x701 }, { 0x9c, 0x701 }, { 0xa0, 0x701 }, { 0xa4, 0x701 },
    { 0x800, 0x701 }, { 0x804, 0x701 }, { 0x808, 0x701 }, { 0x80c, 0x701 }, { 0x810, 0x701 },
    { VO_DISP_ENABLE, 0 },
};

/* Mixer: every layer opaque, in order; RGB end to end (no colour space
 * conversion); dithering on; VO interrupts off. */
static const struct reg_value vo_mix[] = {
    { VO_DISP_MIX_LAYER_GLB_EN, 0x7f },
    { VO_DISP_MIX_LAYER_GLB_ALPHA0, 0xffffffff },
    { VO_DISP_MIX_LAYER_GLB_ALPHA1, 0xffffffff },
    { 0x940, 0xffffffff },
    { VO_DISP_MIX_SEL, 0x3210 },
    { 0x950, 0xba987654 },
    { VO_DISP_YUV2RGB_CTL, 0 },
    { VO_DISP_CLUT_CTL, 0 },
    { VO_DISP_DITH_CTL, 1 },
    { VO_OSD_RGB2YUV_CTL, 0 },
    { VO_DISP_MIX_LAYER_GLB_EN, 0xff },
    { VO_DISP_IRQ0_CTL, 0 },
    { VO_DISP_IRQ1_CTL, 0 },
    { VO_DISP_IRQ2_CTL, 0 },
};

static void write_table(const struct reg_value *table, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        wr(VO_BASE + table[i].offset, table[i].value);
    }
}

/* The line interrupt at VTTH_LINE (VO_DISP_IRQ1_CTL: enable bit 20). */
static void vo_line_interrupt(void)
{
    wr(VO_BASE + VO_DISP_IRQ1_CTL, (1u << 20) | VTTH_LINE);
}

static void vo_setup(void)
{
    write_table(vo_wrap, sizeof vo_wrap / sizeof vo_wrap[0]);
    write_table(vo_mix, sizeof vo_mix / sizeof vo_mix[0]);
    /* OSD0-3: address mode, DMA byte map 1234 -> 4321, DMA requests. */
    for (unsigned n = 0; n < 4; n++) {
        wr(osd(n, OSD_ADDR_SEL_MODE), 0x100);
        wr(osd(n, OSD_DMA_CTRL), field(rd(osd(n, OSD_DMA_CTRL)), 5, 4, 3));
        wr(osd(n, OSD_DMA_CTRL), field(rd(osd(n, OSD_DMA_CTRL)), 3, 0, 0xf));
    }
    /* Video layers 0-2: UV and Y endianness, burst length, address mode. */
    for (unsigned l = 0; l < 3; l++) {
        wr(layer_cfg(l), field(rd(layer_cfg(l)), 18, 16, 2));
        wr(layer_cfg(l), field(rd(layer_cfg(l)), 13, 12, 1));
        wr(layer_blenth(l), 0xf);
        wr(layer_addr_sel(l), 0x100);
    }
    for (unsigned l = 0; l < 2; l++) {
        wr(layer_cfg(l), 7); /* outstanding requests */
    }
    vo_line_interrupt();
    vo_line_interrupt();

    /* Timing: syncs, the active window from the back porches, totals. */
    wr(VO_BASE + VO_DISP_HSYNC_CTL, 0x2u | (0x5u << 16));
    wr(VO_BASE + VO_DISP_HSYNC1_CTL, 0x2u | (0x5u << 16));
    wr(VO_BASE + VO_DISP_HSYNC2_CTL, 0x2u | (0x5u << 16));
    wr(VO_BASE + VO_DISP_VSYNC1_CTL, 0);
    wr(VO_BASE + VO_DISP_VSYNC2_CTL, 0);
    wr(VO_BASE + VO_DISP_XZONE_CTL, HBP + ((HACT + HBP - 1) << 16));
    wr(VO_BASE + VO_DISP_YZONE_CTL, VBP + ((VACT + VBP - 1) << 16));
    wr(VO_BASE + VO_DISP_TOTAL_SIZE, HTOTAL + (VTOTAL << 16));
    wr(VO_BASE + VO_DISP_DRAW_FRAME_CMD, (HACT - 1) + ((VACT - 1) << 16) + (1u << 15));
    wr(VO_BASE + VO_DISP_BACKGROUND, BACKGROUND);
    wr(VO_BASE + VO_REG_LOAD_CTL, VO_LOAD);
}

/*
 * Layer n shows `rows` rows of 568 RGB565 pixels from `addr` (stride 1136)
 * at the top of the active window; latched at the next frame.
 */
static void osd_show(unsigned n, uint32_t rows, uint32_t addr)
{
    uint32_t x = rd(VO_BASE + VO_DISP_XZONE_CTL) & 0x1fff;
    uint32_t y = rd(VO_BASE + VO_DISP_YZONE_CTL) & 0x1fff;
    wr(osd(n, OSD_INFO), OSD_FORMAT_RGB565);
    wr(osd(n, OSD_SIZE), PANEL_K230_WIDTH | (rows << 16));
    wr(osd_xctl(n), ((x + PANEL_K230_WIDTH - 1) << 16) + x);
    wr(osd_xctl(n) + 4, ((y + rows - 1) << 16) + y);
    wr(osd(n, OSD_VLU_ADDR0), addr);
    wr(osd(n, OSD_ALP_ADDR0), addr);
    wr(osd(n, OSD_VLU_ADDR1), addr);
    wr(osd(n, OSD_ALP_ADDR1), addr);
    wr(osd(n, OSD_STRIDE), PANEL_K230_STRIDE / 8);
    wr(osd(n, OSD_DMA_CTRL), 0x40);
    wr(osd(n, OSD_ADDR_SEL_MODE), 0x1100);
    wr(VO_BASE + VO_DISP_ENABLE, rd(VO_BASE + VO_DISP_ENABLE) | osd_enable_bit(n));
    wr(VO_BASE + VO_REG_LOAD_CTL, VO_LOAD);
}

/* ---- the panel -------------------------------------------------------------- */

static int bring_up(void)
{
    if (power_display_domain() != PANEL_K230_OK) {
        return PANEL_K230_POWER_TIMEOUT;
    }
    panel_power_and_reset();
    display_reset();
    set_pixel_clock();
    int dphy_failed = dphy_2lane();
    dsi_setup();
    for (size_t i = 0; i < sizeof rm69a10_init / sizeof rm69a10_init[0]; i++) {
        dcs_send(&rm69a10_init[i]);
    }
    vo_setup();
    osd_show(FB_OSD, PANEL_K230_HEIGHT, (uint32_t) (COPROC_FB_ADDR + 4096u));
    dsi_start();
    return dphy_failed ? PANEL_K230_DPHY_TIMEOUT : PANEL_K230_OK;
}

/* 1 until the first panel_k230_open(), then its result. */
static int opened = 1;
/* The status band OSD5 scans; the VO reads it from memory. */
static uint8_t status_pixels[PANEL_K230_STATUS_BYTES] __attribute__((aligned(64)));

int panel_k230_open(void)
{
    if (opened != 1) {
        return opened;
    }
    if (!COPROC_PANEL_K230) {
        opened = PANEL_K230_NO_PANEL;
        return opened;
    }
    opened = bring_up();
    switch (opened) {
        case PANEL_K230_OK:
            printf("elixos coproc: panel: RM69A10 568x1232 up, the VO scans 0x%08lx (RGB565, "
                   "2-lane DSI at 475.2 Mbit/s, 41.8 Hz)\n",
                (unsigned long) (COPROC_FB_ADDR + 4096u));
            break;
        case PANEL_K230_POWER_TIMEOUT:
            printf("elixos coproc: panel: the display power domain did not come up; the panel stays dark\n");
            break;
        default:
            printf("elixos coproc: panel: the D-PHY did not come up; the panel stays dark\n");
            break;
    }
    return opened;
}

int panel_k230_status(const void *pixels, size_t size)
{
    if (opened != PANEL_K230_OK) {
        return PANEL_K230_NOT_OPEN;
    }
    if (size == 0) {
        wr(VO_BASE + VO_DISP_ENABLE, rd(VO_BASE + VO_DISP_ENABLE) & ~osd_enable_bit(STATUS_OSD));
        wr(VO_BASE + VO_REG_LOAD_CTL, VO_LOAD);
        return PANEL_K230_OK;
    }
    if (pixels == NULL || size != PANEL_K230_STATUS_BYTES) {
        return PANEL_K230_BADARG;
    }
    memcpy(status_pixels, pixels, size);
    osd_show(STATUS_OSD, PANEL_K230_STATUS_ROWS, (uint32_t) (uintptr_t) status_pixels);
    return PANEL_K230_OK;
}
