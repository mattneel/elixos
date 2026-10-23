/*
 * Elixos coprocessor firmware: the RM69A10 panel on the K230's VO block and
 * MIPI DSI host (M33, panel_k230.c, docs/notes/k230-panel.md).
 *
 * After panel_k230_open() the VO scans the §12 framebuffer's pixels
 * (COPROC_FB_ADDR + 4096, RGB565, stride 1136) out to the panel by itself,
 * every frame: a commit needs no push. The status band (rows 0-27) is a
 * second layer over it, set by panel_k230_status().
 */
#ifndef PANEL_K230_H
#define PANEL_K230_H

#include <stddef.h>

#define PANEL_K230_WIDTH 568
#define PANEL_K230_HEIGHT 1232
#define PANEL_K230_STRIDE (2 * PANEL_K230_WIDTH)
#define PANEL_K230_STATUS_ROWS 28
#define PANEL_K230_STATUS_BYTES (PANEL_K230_STATUS_ROWS * PANEL_K230_STRIDE)

#define PANEL_K230_OK 0
/* Built without the panel (COPROC_PANEL_K230=0: QEMU virt). */
#define PANEL_K230_NO_PANEL (-1)
/* The display power domain did not report power-up. */
#define PANEL_K230_POWER_TIMEOUT (-2)
/* The D-PHY did not report its state machine done or its lanes ready. */
#define PANEL_K230_DPHY_TIMEOUT (-3)
/* panel_k230_status() before a successful panel_k230_open(). */
#define PANEL_K230_NOT_OPEN (-4)
/* panel_k230_status() with a buffer that is not one status band. */
#define PANEL_K230_BADARG (-5)

/*
 * Powers the panel, brings up the display clocks, D-PHY, DSI host and VO,
 * sends the RM69A10 init sequence and starts scanning the framebuffer out.
 * Blocks about 0.95 s. Runs once per firmware boot: later calls (the VM
 * restarts on every deploy) return the first call's result at once, and the
 * panel keeps scanning out meanwhile.
 */
int panel_k230_open(void);

/*
 * The status band: PANEL_K230_STATUS_BYTES of RGB565 little-endian pixels
 * (568 x 28, rows top to bottom) laid over the framebuffer's rows 0-27, or
 * size 0 to remove it. The pixels are copied.
 */
int panel_k230_status(const void *pixels, size_t size);

#endif
