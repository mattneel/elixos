# The T-Display K230 panel: vendor sources for the scan-out port (M33)

The coprocessor's display backend (`os/src/coproc_display_k230.erl`) does
the §12 bookkeeping and composes the status line; the one function that
needs the board is the scan-out, `coproc/src/panel_k230.c`. It is **not
ported**: `panel_open` returns `{error, dsi_not_ported}` and prints so on
UART3. This page pins the vendor sources a port starts from (researched
2026-10-23 by fetching each file at the commit given; line numbers as read).

A note for the port: the K230's VO block scans a framebuffer out of DDR by
itself (OSD layers with a base address and a stride). If an OSD format
accepts RGB565 little-endian, the VO can scan the §12 region's pixels in
place (`0x08101000`, stride 1136) and `panel_write` reduces to nothing
beyond the uncached view of the region; the vendor path below uses OSD4 in
XRGB8888 (format 3), so the RGB565 format code must be found first.

Every file below was fetched from raw.githubusercontent.com or the GitHub API at the pinned commit; line numbers are as read there. Claims not observed directly are marked `[INFERENCE]`; "my"/"I" below mean that research pass.

Repos and SHAs used:

| Tag | Repo | Commit |
| --- | --- | --- |
| **LT-RT** | https://github.com/Xinyuan-LilyGO/T-Display-K230_canmv_rt | `abb07090ad8a666ed7a5e097b3c714b918731645` |
| **LT-BSP** | https://github.com/Xinyuan-LilyGO/T-Display-K230 | `0ad78192bab04585ae51bb847695fdc74658f134` (its `k230_bsp/metadata/upstream_sdk_commit.txt` = `fc6cc2151d54cb307be47f81815023f7ffb0eae6`, `upstream_sdk_url.txt` = `https://github.com/kendryte/k230_linux_sdk.git`) |
| **CAN-LS** | https://github.com/kendryte/k230_linux_sdk | `fc6cc2151d54cb307be47f81815023f7ffb0eae6` |
| **CAN-SDK** | https://github.com/kendryte/k230_sdk | tag `v2.0` → tag object `1f512d04…` → commit `7e302f733311d284be255f0d81d3463b6ae6ee6d` |

Abbreviation: `U` = `k230_bsp/overlay/buildroot-overlay/boot/uboot/u-boot-2022.10-overlay/` in LT-BSP. `UO` = `buildroot-overlay/boot/uboot/u-boot-2022.10-overlay/` in CAN-LS.

---

## Q1. RM69A10 panel driver

### Where the driver lives (summary)

There are three independent, vendor-authored RM69A10 bring-ups. All of them send the same DCS list.

1. **RT-Smart MPP connector driver (LT-RT).** `canmv_k230/src/rtsmart/mpp/kernel/connector/src/rm69a10.c` (449 lines). It sends DCS through `connecter_dsi_send_pkg()`. All DSI/VO/PHY programming is delegated to the **closed** `canmv_k230/src/rtsmart/mpp/kernel/lib/libvo.a` (266854 bytes). The bridge functions are in `connector_comm.c` 145-203.
2. **Bare-metal U-Boot boot-logo path (LT-BSP), all open source.** It programs the DSI host, D-PHY, VO and an OSD layer by direct `writel` and scans an XRGB8888 framebuffer in DDR out over 2-lane DSI. **This is the port template.** Files:
   - `U/board/canaan/common/logo/display_logo.c` (1076 lines)
   - `display_logo.h`
   - `st7701.c` (880 lines; contains the RM69A10 path)
   - `k230_logo.c` (393 lines)
   - `vo_table.h` (not in the LilyGO overlay; it is in CAN-LS `UO/board/canaan/common/logo/vo_table.h`, 9809 bytes)
3. **Linux DRM (LT-BSP patches over CAN-LS kernel).** DT `panel-init-sequence` for `compatible = "canaan,universal"`, plus patches to `drivers/gpu/drm/canaan/canaan_dsi.c` and `canaan_phy.c`.

Upstream Canaan does not contain an RM69A10 driver:
- **CAN-SDK v2.0:** `src/big/mpp/kernel/connector/src/` lists `connector_comm.c, connector_dev.c, connector_dev.h, hx8399.c, ili9806.c, lt9611.c, nt35516.c, st7701.c, virtdev.c.c`. No rm69a10. `src/big/mpp/kernel/lib/` ships `libvo.a` as a binary, as in LT-RT.
- **CAN-LS `UO/board/canaan/common/logo/`:** `display_logo.c` (956 lines) has no `k230_dsi_config_2lan_phy` (only `k230_dsi_config_4lan_phy` at 903). `k230_logo.c` and `st7701.c` contain no "RM69"/"rm69". LilyGO added the 2-lane PHY and the RM69A10 path.
- **kendryte/k230_canmv:** not inspected separately. LT-RT `canmv_k230/` is LilyGO's fork of that tree.

### (a) DCS init command list

**Source 1: LT-RT `canmv_k230/src/rtsmart/mpp/kernel/connector/src/rm69a10.c`, function `rm69a10_568x1232_init` at lines 96-245.** These are the live lines; the rest of the function is commented out.

```c
114: k_u8 param00[]={0xFF,0x98,0x81,0x00};   // declared, send commented out (136)
115: k_u8 param01[]={0x11};                  // declared, send commented out (137)
116: k_u8 param1[]={0xFE,0xFD};
117: k_u8 param2[]={0x80,0xFC};
118: k_u8 param3[]={0xFE,0x00};
119: k_u8 param4[]={0x2A,0x00,0x00,0x02,0x37};
120: k_u8 param5[]={0x2B,0x00,0x00,0x04,0xCF};
121: k_u8 param6[]={0x31,0x00,0x03,0x02,0x34};
122: k_u8 param7[]={0x30,0x00,0x00,0x04,0xCF};
123: k_u8 param8[]={0x12,0x00};
124: k_u8 param9[]={0x35,0x00};
125: k_u8 param10[]={0x51,0xFE};
126: k_u8 param11[]={0x11};
127: k_u8 param12[]={0x29};
130: k_u8 param14[]={0x3A,0x77};//colmod
139-149: send param1..param10 in order
150:   connector_delay_us(2000);
151:   connecter_dsi_send_pkg(param11, sizeof(param11));   // 0x11 sleep out
152:   connector_delay_us(120000);
153:   connecter_dsi_send_pkg(param12, sizeof(param12));   // 0x29 display on
156:   connecter_dsi_send_pkg(param14, sizeof(param14));   // 0x3A 0x77
159:   ret=connecter_dsi_read_pkg(0x05);  162: ret=connecter_dsi_read_pkg(0x0C);
```

Other parts of the same file:
- Lines 39-94: `rm69a10_OLD_init`. This is an HX8399 sequence (`0xB9,0xFF,0x83,0x99`…) that is unused (dead code).
- Lines 166-244: a commented-out ST7701 sequence.

**Source 2: LT-BSP `U/board/canaan/common/logo/st7701.c`, function `rm69a10_568x1232_init` at lines 75-106.** This is the cleanest version.

```c
 77: uint8_t param1[] = {0xFE, 0xFD};
 78: uint8_t param2[] = {0x80, 0xFC};
 79: uint8_t param3[] = {0xFE, 0x00};
 80: uint8_t param4[] = {0x2A, 0x00, 0x00, 0x02, 0x37};   // CASET 0..567
 81: uint8_t param5[] = {0x2B, 0x00, 0x00, 0x04, 0xCF};   // RASET 0..1231
 82: uint8_t param6[] = {0x31, 0x00, 0x03, 0x02, 0x34};
 83: uint8_t param7[] = {0x30, 0x00, 0x00, 0x04, 0xCF};   // partial area
 84: uint8_t param8[] = {0x12};                           // partial mode on
 85: uint8_t param9[] = {0x35, 0x00};                     // TE on
 86: uint8_t param10[] = {0x51, 0xFE};                    // brightness
 87: uint8_t param11[] = {0x11};                          // sleep out
 88: uint8_t param12[] = {0x29};                          // display on
 89: uint8_t param13[] = {0x3A, 0x77};                    // COLMOD 24bpp
 91-98:  kd_dwc_lpdt_send_pkg(param1..param8)
 99-100: kd_dwc_lpdt_send_short_pkg(param9), (param10)
101: kd_dwc_lpdt_send_pkg(param11, sizeof(param11));
102: msleep(120);
103: kd_dwc_lpdt_send_pkg(param12, sizeof(param12));
104: msleep(10);
105: kd_dwc_lpdt_send_short_pkg(param13, sizeof(param13));
```

The comments after `//` are mine (standard MIPI DCS names), except "colmod" in source 1.

Packet encoding is in `display_logo.c`:
- `kd_dwc_lpdt_send_pkg` (197-239): for len ≥ 2 it writes 4-byte words to `GEN_PLD_DATA` (0x70), then `GEN_HDR` (0x6c) = `0x39 | (len<<8)` (DCS long write). For len 1 it writes `GEN_HDR = 0x05 | (buf[0]<<8)` (DCS short, no parameter). It ends with `msleep(3)` (237).
- `kd_dwc_lpdt_send_short_pkg` (241-257): len 1 → `0x05 | b0<<8`. Len 2 → `0x15 | b0<<8 | b1<<16` (DCS short write with 1 parameter).

**Source 3: LT-BSP Linux DT, patch `k230_bsp/overlay/buildroot-overlay/linux/0031-riscv-dts-canaan-add-rm69a10-display.patch` lines 35-49** (file `display-rm69a10-568x1232.dtsi`). Format is `<type> <delay-ms> <len> <payload>`:

```
39 00 02 FE FD
39 00 02 80 FC
39 00 02 FE 00
39 00 05 2A 00 00 02 37
39 00 05 2B 00 00 04 CF
39 00 05 31 00 03 02 34
39 00 05 30 00 00 04 CF
05 00 01 12
15 00 02 35 00
15 00 02 51 FE
05 78 01 11        (0x78 = 120 ms after sleep-out)
05 0A 01 29        (10 ms after display-on)
15 00 02 3A 77
```

Patch 0049 (lines 9-11) adds `canaan,dsi-command-backlight; default-brightness = <254>; max-brightness = <255>;`. Brightness is DCS 0x51 via `mipi_dsi_dcs_write(..., MIPI_DCS_SET_DISPLAY_BRIGHTNESS, &level, 1)` (patch lines 70-71). There is no PWM backlight.

#### Reset and power sequence

The reset is **IO22** in every source, and the panel enable is **IO25**. I found **no vendor source that drives IO35 for the panel**; details are below this section.

**RT-Smart, `rm69a10.c` 248-307:**
- `rm69a10_power_reset` uses `CONFIG_MPP_DSI_LCD_RESET_PIN`.
- `rm69a10_set_backlight` uses `CONFIG_MPP_DSI_LCD_BACKLIGHT_PIN`.
- `rm69a10_power_on(on)` lines 290-301: `k230_display_rst()`; reset high; `rt_thread_mdelay(g_blacklight_delay_ms)` (1 ms the first time, then 200, defines at 32-33); reset low; 10 ms; reset high; 20 ms; backlight GPIO high.
- Pin values:
  - LT-RT `canmv_k230/configs/k230_canmv_v3p0_defconfig` line 19: `CONFIG_MPP_DSI_LCD_RESET_PIN=22`.
  - The backlight pin is not set in that defconfig. `canmv_k230/src/rtsmart/mpp/Kconfig` 215-217 gives the default: `config MPP_DSI_LCD_BACKLIGHT_PIN … default 25` (reset default is 24, at 211-213).

**U-Boot, `st7701.c` 27-73 `st7701_hardware_init`:**
- Lines 30-35: `#ifdef CONFIG_K230_BARE_DISP_LOGO_RM69A10  #define GPIO_RST_PIN 22 … #define GPIO_LCD_BACKLIGHT_EN 25`.
- Sequence: `k230_gpio('o',22,high)`, 200 ms, low, 200 ms, high, 200 ms, then `k230_gpio('o',25,high)` (56-71).

**Linux:**
- Patch 0032 lines 43-46: `&lcd { dsi_reset-gpios = <&gpio0_ports 22 GPIO_ACTIVE_HIGH>; backlight_gpio-gpios = <&gpio0_ports 25 GPIO_ACTIVE_HIGH>; }`.
- Patch 0027 (`panel-canaan-universal.c` prepare): power_on = 1, 10 ms; reset 1, 10 ms; 0, 20 ms; 1, 20 ms; then `msleep(200)`; then send the init sequence.

**Board docs and schematic:**
- LT-BSP `k230_bsp/docs/HARDWARE_PINMAP.md` line 51: "RM69A10 AMOLED | `GPIO22` | Output | Reset". Line 52: "`GPIO25` | Output | Panel enable".
- Same file line 103: GPIO35 is "MAX98357A amplifier | `DOUT`/`DIN` | `GPIO35` / I2S data".
- LT-BSP patch 0058 lines 48-52 pinmux `K230_IO35` as `K230_IO35_IIS_D_OUT0_PDM_IN1`.
- LT-RT `k230_canmv_v3p0_defconfig` line 246: `CONFIG_WS2812_GPIO_PIN_NUM=35`.
- Schematic, LT-RT `schematic/T-Display K230_V1.0_NEW.pdf`, text from `pdftotext`:
  - Ball W12 `GPIO35/IIC1_SDA/IIS_D_OUT0/PDM_IN1/UART3_CTS` is on net **`IO35_DISEN`**.
  - On page 4 (MIPI/LCD-FPC sheet) `IO35_DISEN` appears next to `R99 10K`, `Q3`, net `DIS_EN` and `LCD_VDD`/`VBAT`.
  - Panel nets on page 2 are `LCD_RST` = ball L5 `GPIO22` and `LCD_EN` = ball M1 `GPIO25`.
  - The LCD FPC (J1) carries `LCD_RST` (pin 11), `LCD_VDD` (pins 13-14), `TP_*`, and DSI CLK/D0/D1 only. I saw no D2/D3 on the panel FPC: the panel is 2-lane, and D2/D3 go to LT9611.
- **`[INFERENCE]`** `IO35_DISEN` → Q3 is a discharge or display-power switch on the `LCD_VDD` rail. The flattened PDF text does not let me confirm its polarity or role. No vendor software drives GPIO35 for the display (Linux uses it as I2S data), so treat "IO35 = panel power" as **unconfirmed**.

### (b) Panel timing

The struct layouts are in:
- LT-RT `canmv_k230/src/rtsmart/mpp/include/comm/k_vo_comm.h` 223-237: `k_vo_display_resolution { pclk, phyclk, htotal, hdisplay, hsync_len, hback_porch, hfront_porch, vtotal, vdisplay, vsync_len, vback_porch, vfront_porch }` (units: kHz for both clocks).
- `k_connector_comm.h` 71-77: phy attr `{ n, m, voc, hs_freq }`.
- `k_connector_comm.h` 80-93: `k_connector_info { name, screen_test_mode, dsi_test_mode, bg_color, intr_line, pixclk_div, lan_num, work_mode, cmd_mode, phy_attr, resolution, type }`.

The three sources use different timings:

| Field | RT-Smart (LT-RT `canmv_k230/src/rtsmart/mpp/userapps/src/connector/mpi_connector.c` 32-45) | U-Boot (LT-BSP `U/board/canaan/common/logo/k230_logo.c` 316-334) | Linux (LT-BSP patch 0031, 50-62) |
| --- | --- | --- | --- |
| pclk | 39600 kHz | 39600 kHz | 49500000 Hz |
| phyclk field | 475200 | 475200 | auto (`canaan_dsi_clk_cfg`) |
| htotal / hact | 788 / 568 | 748 / 568 | (568+100+40+40 = 748) |
| hsync / hbp / hfp | 40 / 140 / 40 | 40 / 40 / 100 | 40 / 40 / 100 |
| vtotal / vact | 1268 / 1232 | 1268 / 1232 | (1268) |
| vsync / vbp / vfp | 4 / 16 / 16 | 16 / 16 / 4 | 16 / 16 / 4 |
| D-PHY {n, m, voc, hsfreq} | {4, 97, 0x19, 0x96} | {4, 97, 0x19, **0x87**} | auto; hsfreq derived (patch 0068) |
| lanes / mode | `K_DSI_2LAN`, `K_BURST_MODE`, `K_VO_LP_MODE` | same | `panel-dsi-lane = <2>` |
| intr_line / pixclk_div | 9 / 14 | 10 / 14 (`buff_num` = 1) | `vth_line = <10>` |
| frame rate (computed) | 39.6e6/(788·1268) ≈ 39.6 Hz | 39.6e6/(748·1268) ≈ 41.8 Hz | 49.5e6/(748·1268) ≈ 52.2 Hz |

The RT-Smart table labels this mode `RM69A10_MIPI_2LAN_568X1232_60FPS = 140` (`k_connector_comm.h` 67), but the numbers give about 40 Hz.

Raw table entries:
- RT-Smart 42-43: `{ 4, 97, 0x19, 0x96 }, { 39600, 475200, 788, 568, 40, 140, 40, 1268, 1232, 4, 16, 16 }`.
- U-Boot 330-333: `{ 4, 97, 0x19, 0x87 }, { 39600, 475200, 748, 568, 40, 40, 100, 1268, 1232, 16, 16, 4 }`. The U-Boot `k_connector_info` has a different field order (`display_logo.h` 438-452): `dsi_test_mode, bg_color, intr_line, pixclk_div, buff_num, lan_num, work_mode, cmd_mode, phy_attr, resolution, w_start, h_start`.

Lane rate: 24 bpp × pclk / 2 lanes. 39.6 MHz gives 475.2 Mbps/lane, which matches the `phyclk` 475200 field. 49.5 MHz gives 594 Mbps/lane.

Vendor notes on hsfreq:
- Patch 0068 lines 6-21: "0x96 … hsfreqrange 0x16 … 415-486 Mbps … RM69A10 moved to the 49.5 MHz timing, its 2-lane link runs at 594 Mbps … 0x96 shifted in 3 of 3 inits and 0x87 was stable in 3 of 3".
- Patch 0042 lines 10-11: "the 49.5 MHz RM69A10 timing can run at about 52 Hz".
- `k230_logo.c` 327-329: "RM69A10 uses a 594 Mbps two-lane link. Keep the U-Boot logo initialization aligned with the Linux D-PHY hsfreqrange value." This comment does not match the U-Boot table, which still has pclk 39.6 MHz (475 Mbps).

Pixel clock source:
- `k230_set_pixclk(div)` (`display_logo.c` 108-116) writes `CLK_BASE_ADDR+0x78` bits [10:3] = div and sets bit 31. Comment: "8M = pll1(2376) / 4 / 66".
- With div 14: 2376/4/14 = 42.4 MHz `[INFERENCE]`. The comment's formula does not exactly match the 39.6 MHz in the table.
- Linux computes this divider itself: patch 0068 context lines 98-102 do `ioremap(0x91100000)`, then `readl(dis_clk + 0x78)`.

### (c) DSI host, D-PHY and VO programming (open source, LT-BSP U-Boot)

**Base addresses**, `U/board/canaan/common/logo/display_logo.h` 348-354 (identical in CAN-LS `UO/.../display_logo.h` 348-354):

```
VO_BASE_ADDR    0x90840000
DSI_BASE_ADDR   0x90850000      (Synopsys DW MIPI DSI host)
TXPHY_BASE_ADDR 0x90850400      (K230 TX D-PHY wrapper)
RST_BASE_ADDR   0x91101000
CLK_BASE_ADDR   0x91100000
PWR_BASE_ADDR   0x91103000
STC_BASE_ADDR   0x91108000
```

**DSI host register offsets** (`display_logo.h` 296-338): `CLKMGR_CFG 0x08, DPI_VCID 0x0c, DPI_COLOR_CODING 0x10, PCKHDL_CFG 0x2c, GEN_VCID 0x30, MODE_CFG 0x34, VID_MODE_CFG 0x38, VID_PKT_SIZE 0x3c … VID_VACTIVE_LINES 0x60, CMD_MODE_CFG 0x68, GEN_HDR 0x6c, GEN_PLD_DATA 0x70, CMD_PKT_STATUS 0x74, LPCLK_CTRL 0x94, PHY_RSTZ 0xa0, PHY_IF_CFG 0xa4, PHY_STATUS 0xb0, PHY_TST_CTRL0 0xb4, PHY_TST_CTRL1 0xb8`.

**TXPHY register offsets:** `TXDPHY_CFG0 0x0, CFG1 0x4, PLL_CFG0 0x08, PLL_CFG1 0x10`.

**VO register offsets:** `VO_SOFT_RST_CTL 0x00, VO_REG_LOAD_CTL 0x04, VO_DISP_XZONE_CTL 0x0C0, YZONE 0x0C4, VO_DISP_ENABLE 0x118, VO_DISP_TOTAL_SIZE 0x11C, VO_OSD_RGB2YUV_CTL 0x340, VO_DISP_BACKGROUND 0x3D0, VO_DISP_OSD0..7_X/YCTL 0x0E8-0x0FC, 0x820-0x844`.

OSD indexing macros are at 268-280. OSD0-2 use stride 0x40 from `VO_OSD0_*`; OSD3+ use stride 0x30 from `VO_OSD3_*`.

**Call order**, `st7701.c` 847-879 `st7701_init()` (called from `k230_logo.c` 353-354 after `sysctl_pwr_set_power(SYSCTL_PD_DISP, true)`):

```
851-852 h_start = vbp; w_start = hbp
854 st7701_hardware_init()            // GPIO22 reset pulse, GPIO25 enable
856 k230_display_rst()                // display_logo.c 260-272
858 k230_set_pixclk(pixclk_div)       // 108-116
861 st7701_set_phy_freq → dwc_mipi_phy_config (1055-1075) → k230_dsi_config_2lan_phy (1013-1052)
863 st7701_dsi_resolution_init (778-805) → kd_dsi_set_attr (179-194), then rm69a10_568x1232_init (DCS, LP mode)
865 st7701_vo_resolution_init (809-826) → vo_init (505-544), kd_vo_set_vtth_intr, kd_vo_set_dev_param (587-596), kd_vo_enable (599-603)
869 vo_osd4_logo_test(info)           // display_logo.c 692-725
875 dwc_dsi_enable(1)                 // 167-176, last for RM69A10
```

**What each function writes** (all in `display_logo.c`):

- **`k230_display_rst` (260-272):** `0x91101090 ← 0`, 20 ms, `← 0xffffffff`, 20 ms. Then `VO_SOFT_RST_CTL ← 0x0f`, `VO_DMA_SW_CTL ← 0`, `VO_REG_LOAD_CTL ← 0`, 10 ms.
- **Power domain:** `sysctl_pwr_set_power(SYSCTL_PD_DISP, true)` is in `k230_logo.c` 104-193. It sets `disp_lpi_ctl` (SYSCTL_PWR + 0x3c) bits 1 and 17, and reads `disp_lpi_state` (+0x40) bit 1 (lines 133-139).
- **D-PHY:**
  - `dwc_mipi_phy_config` (1055-1075): `DSI+0xc ← 0`. If `K_DSI_2LAN` → `k230_dsi_config_2lan_phy(m, n, voc, hs_freq)`.
  - `k230_dsi_phy0_config` (872-909):
    - `TXDPHY_CFG1 ← 0`; `PHY_RSTZ ← 0xc`; test-clear pulse.
    - Test codes: `0x0c←3`, `0x44←hsfreq`, `0xa0←0x40`, `0xa4←0x11`, `0xa4←0x85`, `0xa3←1`, `0x1f←1`, `0x4a←0x40`.
    - `TXDPHY_CFG0` cfgclkfreqrange 0x28. Then `k230_dsi_phy_pll_config(m, n, vco)` (817-870): PLL_CFG0 M[26:17], N[30:27], cpbias 0x10; PLL_CFG1 vco[16:11], prop 0x8; test codes 0x14-0x16, 0x1D; bit 10 pulse.
    - Comment at 832-834: "M=m+2 … N=n+1 … fout = (1M/4N)*24".
    - Ends with `TXDPHY_CFG0 ← 0x28a0`, `PHY_RSTZ ← 0xc`.
  - `k230_dsi_phy1_config` (913-977): `TXDPHY_CFG1 ← 0x400000` (select PHY1), same test codes plus `0x30←0xff`, `PHY_RSTZ` 0x4/0xd/0xf, then polls `PHY_TST_CTRL1 == 0x580` (at most 1000 × 20 ms).
  - `k230_dsi_config_2lan_phy` (1013-1052): phy0 + phy1; `TXDPHY_CFG1 ← 0`; `PHY_RSTZ ← 0x5`, then `0x7`; poll `PHY_STATUS == 0x1fbd` (100000 × 10 µs timeout); 20 ms; `LPCLK_CTRL ← 1`; `TXDPHY_CFG1 ← 0x400000`; poll `0x1fbd` again.
- **DSI host:**
  - `kd_dsi_set_attr` (179-194):
    - `PHY_IF_CFG ← 0x2800 + lan_num` (lines 28-37; lan_num 1 = 2 lanes).
    - `CLKMGR_CFG ← 0x100 + lp_div` (lp_div = 8, `st7701.c` 786).
    - `GEN_VCID ← 0x303`.
    - `dwc_dsi_set_timing` (70-105): `VID_PKT_SIZE ← hact`. HSA/HBP/HLINE are converted to lane-byte cycles by `ceil(x·phyclk/8/pclk)` (55-67). VSA/VBP/VFP/VACT are written raw.
    - `dwc_dsi_set_lpdt_mode` (118-132): `MODE_CFG ← 1` (command mode); `VID_MODE_CFG ← 0x3f02` for RM69A10; `CMD_MODE_CFG ← 0x10f7f01` (all commands LP); `PCKHDL_CFG ← 0x1c`; `DSI+0x4 ← 1`.
  - `dwc_dsi_enable` → `dwc_dsi_init` (145-176):
    - `DPI_COLOR_CODING ← 0x005` (RM69A10 RGB888; 0x105 otherwise).
    - `0x9c ← 0x320068`, `0x98 ← 0x2e0080`, `0xc4/0xc8 ← 0xffffffff`.
    - `MODE_CFG ← 0` (video mode), `CMD_MODE_CFG ← 0` (HS commands), `LPCLK_CTRL ← 3`, then `LPCLK_CTRL ← 1`.
- **VO:**
  - `vo_init` (505-544) = `kd_vo_wrap_init` (328-363), then `kd_vo_set_config_mix` (386-424), then `kd_vo_table_init` (366-383, scaler coefficients from `vo_table.h`).
    - OSD0-3: addr-sel 0x100, DMA map `1234_TO_4321`, DMA request 0xf.
    - Layers 0-2: endian modes, blen 0xf, addr-sel 0x100.
    - Then outstanding; `vtth` interrupt.
    - For RM69A10, `config_mix` writes `VO_DISP_YUV2RGB_CTL ← 0` and `VO_OSD_RGB2YUV_CTL ← 0` (lines 401-416). That keeps RGB end to end.
  - `kd_vo_set_timing` (547-577): hsync regs (2, 5); `XZONE = hbp | (hact+hbp-1)<<16`; `YZONE = vbp | (vact+vbp-1)<<16`; `TOTAL_SIZE = htotal | vtotal<<16`; `VO+0x780 = (hact-1) | (vact-1)<<16 | 1<<15`.
  - `kd_vo_set_background` (580-583) writes `VO+0x3D0`.
  - `kd_vo_enable` (599-603): `VO_REG_LOAD_CTL ← 0x11`.
- **Framebuffer scan-out**, `vo_osd4_logo_test` (692-725, under `CONFIG_K230_BARE_DISP_LOGO_RM69A10`). OSD4, 568×1232, XRGB8888:

  ```c
  699: writel(0x03, VO_BASE_ADDR + VO_OSD_INFOR(RM69A10_LOGO_OSD));          // format
  701: reg = RM69A10_LOGO_WIDTH | (RM69A10_LOGO_HEIGHT << 16);   → VO_OSD_SIZE
  704: reg = ((start_w + W - 1) << 16) + start_w;                → VO_DISP_OSD_XCTL
  707: reg = ((start_h + H - 1) << 16) + start_h;                → VO_DISP_OSD_YCTL
  710-713: addr → VO_OSD_VLU_ADDR0/ALP_ADDR0/VLU_ADDR1/ALP_ADDR1
  715: writel((RM69A10_LOGO_WIDTH * 4) / 8, … VO_OSD_STRIDE)    // stride in 8-byte units
  717: writel(0x40, … VO_OSD_DMA_CTRL);  718: writel(0x1100, … VO_OSD_ADDR_SEL_MODE);
  720-722: VO_DISP_ENABLE |= BIT(8);   724: writel(0x11, VO_REG_LOAD_CTL)
  ```

  - `start_w`/`start_h` are read back from XZONE/YZONE (695-696).
  - Framebuffer address: `k230_logo.c` 199 `#define RM69A10_LOGO_FB_ADDR 0x1f000000UL`. Size: 198 `568*1232*4`.
  - The image is loaded from `/logo.xrgb`, then `flush_cache(add, ROUND(size, CONFIG_SYS_CACHELINE_SIZE))` (241).
  - The Linux kernel keeps this framebuffer reserved for a splash handoff (LT-BSP patches 0038, 0051; not quoted here).
  - `kd_vo_set_layer` (605-684) and `vo_layer1_test` (728-798) are the NV12 video-layer alternatives (layer 1).

**RT-Smart equivalents (names only; closed implementation).** LT-RT `connector_comm.c` 145-203 maps:
- `connecter_dsi_send_pkg` → `dwc_lpdt_send_pkg`
- `connector_set_phy_freq` → `dwc_mipi_phy_config`
- `connector_set_dsi_attr` → `kd_dsi_dsi_attr`
- `connector_set_dsi_enable` → `dwc_dsi_enable`
- `connector_set_vo_init` → `vo_init`
- `connector_set_vo_param` → `kd_vo_set_dev_param`
- `connector_set_vo_enable` → `kd_vo_enable`
- `connector_set_vtth_intr` → `kd_vo_set_vtth_intr`
- `connector_set_pixclk` → `k230_set_pixclk`

All of these resolve into `canmv_k230/src/rtsmart/mpp/kernel/lib/libvo.a`, a binary. CAN-SDK v2.0 `src/big/mpp/kernel/connector/src/connector_comm.c` 170-210 has the same mapping. The U-Boot file reimplements the same names: `vo_init`, `kd_vo_set_dev_param`, `kd_vo_enable`, `kd_vo_set_vtth_intr`, `dwc_mipi_phy_config`, `dwc_dsi_enable`, `k230_set_pixclk`, `k230_display_rst`.

`rm69a10_init` (`rm69a10.c` 379-393) runs in this order: pixclk, `rm69a10_set_phy_freq` (310-325, forces `K_DSI_2LAN`), `rm69a10_dsi_resolution_init` (328-355: set attr, DCS init, dsi enable), `rm69a10_vo_resolution_init` (358-376). Note the RT-Smart order: DSI enable comes **before** the VO init. In U-Boot, for RM69A10, DSI enable comes last.

### (d) Bare-metal port plausibility

**Plausible.** LT-BSP's U-Boot path is already bare-metal C with no OS dependencies beyond `writel`/`readl`, `mdelay`/`udelay`, `memcpy` and one GPIO helper. Files and functions a port needs (all LT-BSP `U/board/canaan/common/logo/` unless noted):

1. **`display_logo.h`:** base addresses (348-354), register offsets (6-338), structs (359-517), `GENMASK` (344).
2. **`display_logo.c`:**
   - DSI: `dwc_dsi_set_lan_num`, `dwc_dsi_set_lpdt_div`, `dwc_dsi_set_vcid`, `dw_mipi_dsi_get_hcomponent_lbcc`, `dwc_dsi_set_timing`, `dwc_dsi_set_lpdt_mode`, `dwc_dsi_set_color_coding`, `dwc_dsi_init`, `dwc_dsi_enable`, `kd_dsi_set_attr`, `kd_dwc_lpdt_send_pkg`, `kd_dwc_lpdt_send_short_pkg`.
   - Clock and reset: `k230_set_pixclk`, `k230_display_rst`.
   - VO: `kd_vo_set_hsync*/vsync*`, `kd_vo_wrap_init`, `kd_vo_table_init` (needs `vo_table.h` from CAN-LS `UO/board/canaan/common/logo/vo_table.h`), `kd_vo_set_config_mix`, `kd_vo_osd_set_*`, `kd_vo_layer_set_*`, `kd_vo_set_layer_outstanding`, `kd_vo_set_vtth_intr`, `vo_init`, `kd_vo_set_timing`, `kd_vo_set_background`, `kd_vo_set_dev_param`, `kd_vo_enable`, `vo_osd4_logo_test` (the OSD4 XRGB8888 framebuffer setup).
   - D-PHY: `k230_dsi_write_phy_reg`, `k230_dsi_phy_pll_config`, `k230_dsi_phy0_config`, `k230_dsi_phy1_config`, `k230_dsi_config_2lan_phy`, `dwc_mipi_phy_config`.
3. **`st7701.c`:** `st7701_hardware_init` (GPIO22/25 sequence; it uses U-Boot's `k230_gpio()` from `board/canaan/common/k230_board_common.c`, so a port needs its own K230 GPIO and IOMUX writes for IO22/IO25), `rm69a10_568x1232_init`, and the `st7701_init` order at 847-879.
4. **`k230_logo.c`:** `sysctl_pwr_set_power(SYSCTL_PD_DISP, true)` and its helpers (104-193; `SYSCTL_PWR_BASE_ADDR` comes from CAN-LS `UO/arch/riscv/cpu/k230/sysctl.h`, not read), plus the `k_connector_info` values at 316-334.
5. **Linux-derived alternatives** (if preferred): LT-BSP patches 0025, 0068 (hsfreqrange table by lane rate) and 0042 against `drivers/gpu/drm/canaan/canaan_dsi.c` and `canaan_phy.c`. `[INFERENCE]` These files are in the Canaan Linux kernel used by CAN-LS; I did not fetch the kernel source.

Open items for a port:
- Pick one timing: Linux 49.5 MHz with hsfreq 0x87 (validated by LilyGO at 594 Mbps), or RT-Smart/U-Boot 39.6 MHz. The vendor's own D-PHY m/n/voc for 49.5 MHz is only computed at runtime in Linux (`canaan_dsi_clk_cfg`); it is not a constant.
- The IO35 role (above).
- The `pixclk_div` 14 math does not match the comment.

---

## Q2. `boot_baremetal` in CAN-LS @ fc6cc215

File: https://github.com/kendryte/k230_linux_sdk/blob/fc6cc2151d54cb307be47f81815023f7ffb0eae6/buildroot-overlay/boot/uboot/u-boot-2022.10-overlay/arch/riscv/cpu/k230/cpu.c, lines 139-182:

```c
139: typedef void (*func_app_entry)(void);
140: static int k230_boot_baremetal(struct cmd_tbl *cmdtp, int flag, int argc,
141: 		       char *const argv[])
143: 	static	ulong	boot_address , boot_size, boot_cpu;
145: 	if (argc < 4)
146: 		return CMD_RET_USAGE;
148: 	boot_cpu = hextoul(argv[1], NULL);
149: 	boot_address = hextoul(argv[2], NULL);
150: 	boot_size = hextoul(argv[3], NULL);
152: 	flush_cache(boot_address, boot_size);
153: 	printf("boot_cpu = %ld boot_address = 0x%lx boot_size=0x%lx\n", boot_cpu, boot_address, boot_size);
154: 	if(boot_cpu)
156: 		writel(boot_address, (void*)0x91102104ULL);//cpu1_hart_rstvec
158: 		writel(0x10001000,(void*)0x9110100c);
160: 		writel(0x10001,(void*)0x9110100c);
162: 		writel(0x10000,(void*)0x9110100c);
164: 	else
166: 		writel(boot_address, (void*)0x91102100ULL);//cpu0_hart_rstvec
168: 		writel(0x10001000,(void*)0x91101004ULL);
170: 		writel(0x10001,(void*)0x91101004ULL);
172: 		writel(0x10000,(void*)0x91101004ULL);
175:     return 0;
178: U_BOOT_CMD_COMPLETE(
179: 	boot_baremetal, 4, 1, k230_boot_baremetal,
180: 	"boot_baremetal",
181: 	"\n boot_baremetal cpu addr size\n", NULL
```

What it does:
- **Syntax is `boot_baremetal <cpu> <addr> <size>`**: three arguments, all parsed as hex by `hextoul`. A missing third argument returns usage (145-146; maxargs 4 at 179).
- **Flush scope is exactly `[addr, addr+size)`, with no size limit, alignment check or bounds check.** Line 152 calls `flush_cache(boot_address, boot_size)`.
  - CAN-LS builds stock U-Boot 2022.10. It uses `BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE="2022.10"` (seen in `buildroot-overlay/configs/BPI-CanMV-K230D-Zero_defconfig` 110-113) and `rsync -a $(UBOOT_OVERLAY_DIRS)/ $(UBOOT_DIR)/` (`buildroot-overlay/boot/uboot/uboot.mk` 581-589). The overlay does not replace `arch/riscv/lib/cache.c`; its `arch/riscv/lib/` contains only `reset.c`.
  - Upstream https://github.com/u-boot/u-boot/blob/v2022.10/arch/riscv/lib/cache.c: `flush_cache(addr, size) { invalidate_icache_range(addr, addr + size); flush_dcache_range(addr, addr + size); }`. `invalidate_icache_range` is `fence.i`, i.e. the **whole** local I-cache.
  - `flush_dcache_range` is overridden in CAN-LS `UO/arch/riscv/cpu/k230/cache.c` 284-292:
    ```c
    register unsigned long i asm("a0") = start & ~(CONFIG_SYS_CACHELINE_SIZE - 1);
    for (; i < end; i += CONFIG_SYS_CACHELINE_SIZE)
    	asm volatile(".long 0x0295000b");  /* dcache.cpa a0 */
    sync_is();
    ```
    - `CONFIG_SYS_CACHELINE_SIZE` is 64 (`UO/include/configs/k230_evb.h` 33). Start is rounded down to 64 bytes; the loop runs while `i < addr+size`, so the last partial line is included.
    - `sync_is()` = `.long 0x01b0000b` (`UO/arch/riscv/include/asm/csr.h` 158).
  - `0x0295000b` decodes as T-Head `th.dcache.cpa a0` (funct7 0x01, sub-op 0x9, rs1 = x10). It is a **clean (write-back), not an invalidate**. Spec (https://github.com/XUANTIE-RV/thead-extension-spec, `xtheadcmo/dcache_cpa.adoc`): "cleans the cache lines that match the specified physical address in the D-cache. If a cache line is dirty it will be written back to the next-level storage". The L1-only variant `th.dcache.cpal1` is a separate instruction (`dcache_cpal1.adoc`). `[INFERENCE]` So `cpa` cleans all D-cache levels of the executing core.
  - These are local cache-maintenance instructions, so they act on the core running U-Boot. In this firmware that is the big core (repo `docs/notes/k230.md` 130-133 and ADR-102 already record that). The target core's caches are not touched; it starts from reset.
- **Reset release:**
  - cpu 0 (little): writes the reset vector to `0x91102100`, then `0x91101004` ← `0x10001000`, `0x10001`, `0x10000`.
  - cpu ≠ 0: writes `0x91102104` and `0x9110100c` with the same values.
  - No delays (the `udelay`s are commented out). It returns 0 immediately and does not wait for the target.

---

## Q3. Product pages and repos

| URL | What it shows (fetched 2026-10-23) |
| --- | --- |
| https://lilygo.cc/en-us/products/t-display-k230 | "T-Display K230", tagline "K230 + LORA + AMOLED + Touch + HDMI + Cam". **Regular price $98.79** (og:price 98.79 USD). Versions 915 MHz [K256-A], 868 MHz [K256], 433 MHz [K256-C], 923 MHz [K256-B]. Specs: CPU1 1.6 GHz + CPU0 800 MHz, 104×51×15.5 mm, "4.1 Inch AMOLED … Drive Chip RM69A10 … RGB 568 X 1232". Product information links to `github.com/Xinyuan-LilyGO/T-Display-K230_canmv_rt`. |
| https://lilygo.cc/en-us/products/t-display-k230-kit | "T-Display K230 Kit". **Regular price $150.31** (the og:price meta says 70.94 USD, which is probably a variant). Versions: Main Unit / Keyboard Only. Styles: SX1262/868 MHz, LR2021/830-940 MHz, with/without nRF9151. Specs: RM69A10 568×1232, GC2093 camera, "32 LPDDR4, Capacity: 8Gb", RTL8189 Wi-Fi, RC01812 Ethernet. Links to the canmv_rt repo and the wiki. |
| https://wiki.lilygo.cc/products/t-display-series/t-display-k230/ | LilyGO docs: 4.1" AMOLED 568×1232 MIPI DSI, GT9895 touch, 1 GB LPDDR4. It lists an ESP32-S3-R8 co-processor and RTL8152B Ethernet, which contradicts the kit page (RTL8189 Wi-Fi) and the BSP pinmap, which have no ESP32. Treat the wiki as unreliable. |
| https://www.aliexpress.com/item/1005008709409970.html | Search result title "LILYGO® T-Display-K230 K230 Chip Dual-Core RISC-V AIoT …". Not fetched, so I have no price. |
| https://www.tindie.com/products/lilygo/lilygo-t-display-k230-keyboard-expansion-board | Search result: "LILYGO T-Display-K230 Keyboard Expansion Board with NRF9151 LTE-M/GNSS, Dual 21700 Battery Holder". This is the expansion board, not the main unit. Not fetched. |
| https://lilymod.shop/products/t-display-k230 | Third-party mirror page (search result only). |
| GitHub | https://github.com/Xinyuan-LilyGO/T-Display-K230_canmv_rt (RT-Smart/CanMV, schematic `schematic/T-Display K230_V1.0_NEW.pdf`, 8 pages) and https://github.com/Xinyuan-LilyGO/T-Display-K230 (Linux BSP overlay on k230_linux_sdk fc6cc215). |

Not found: a Tindie or AliExpress listing for the main unit with a visible price. The AliExpress item page was not fetched.
