/*
 * Elixos coprocessor firmware: the panel scan-out (M33). REQUIRES THE BOARD;
 * not ported yet (panel_k230.c, docs/notes/k230-panel.md).
 */
#ifndef PANEL_K230_H
#define PANEL_K230_H

#define PANEL_K230_OK 0
#define PANEL_K230_NOT_PORTED (-1)

/* Powers and initialises the panel: 0, or PANEL_K230_NOT_PORTED. */
int panel_k230_open(void);
/* Puts w x h RGB565 little-endian pixels (rows top to bottom) at (x, y). */
int panel_k230_write(unsigned x, unsigned y, unsigned w, unsigned h, const void *pixels, unsigned long size);

#endif
