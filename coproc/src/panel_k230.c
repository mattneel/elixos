/*
 * Elixos coprocessor firmware: the panel scan-out (M33). REQUIRES THE BOARD.
 *
 * The one hardware function behind the display backend
 * (os/src/coproc_display_k230.erl): bring up the RM69A10 AMOLED over the
 * K230's MIPI DSI host and VO block, and put a rectangle of RGB565 pixels on
 * it. Everything else - polling the §12 header, damage, shown, the status
 * line - is Erlang and tested on the host against a mirror file.
 *
 * NOT PORTED. panel_k230_open() fails with PANEL_K230_NOT_PORTED and prints
 * one line on the console; nothing pretends to scan out, and the backend
 * never stores `shown` for frames that did not reach the panel.
 *
 * The port's sources are pinned in docs/notes/k230-panel.md. In short:
 *   - Xinyuan-LilyGO/T-Display-K230 @ 0ad78192bab04585ae51bb847695fdc74658f134,
 *     k230_bsp/overlay/buildroot-overlay/boot/uboot/u-boot-2022.10-overlay/
 *     board/canaan/common/logo/:
 *       st7701.c 75-106 rm69a10_568x1232_init (the DCS list), 27-73 the
 *         IO22 reset / IO25 enable sequence, 847-879 the bring-up order;
 *       display_logo.c 108-116 pixel clock, 260-272 display reset,
 *         179-194 / 145-176 DSI host, 817-1075 2-lane D-PHY,
 *         505-603 VO, 692-725 OSD4 framebuffer scan-out;
 *       display_logo.h 348-354 register bases (VO 0x90840000,
 *         DSI 0x90850000, TX D-PHY 0x90850400);
 *       k230_logo.c 104-193 the display power domain, 316-334 the timing.
 *   - kendryte/k230_linux_sdk @ fc6cc2151d54cb307be47f81815023f7ffb0eae6,
 *     buildroot-overlay/boot/uboot/u-boot-2022.10-overlay/board/canaan/
 *     common/logo/vo_table.h (VO scaler coefficients).
 *   - Xinyuan-LilyGO/T-Display-K230_canmv_rt @
 *     abb07090ad8a666ed7a5e097b3c714b918731645,
 *     canmv_k230/src/rtsmart/mpp/kernel/connector/src/rm69a10.c 96-245 (the
 *     same DCS list; its DSI/VO/PHY calls go into the closed libvo.a).
 * Open before porting: which timing (39.6 or 49.5 MHz), the role of IO35
 * (IO35_DISEN on the schematic, I2S data in LilyGO's Linux), and the VO's
 * RGB565 OSD format code.
 */
#include <stdio.h>

#include "panel_k230.h"

int panel_k230_open(void)
{
    static int said;
    if (!said) {
        said = 1;
        printf("elixos coproc: panel: RM69A10 scan-out over the K230 MIPI DSI host is not ported "
               "(coproc/src/panel_k230.c, docs/notes/k230-panel.md); the panel stays dark\n");
    }
    return PANEL_K230_NOT_PORTED;
}

int panel_k230_write(unsigned x, unsigned y, unsigned w, unsigned h, const void *pixels, unsigned long size)
{
    (void) x;
    (void) y;
    (void) w;
    (void) h;
    (void) pixels;
    (void) size;
    return PANEL_K230_NOT_PORTED;
}
