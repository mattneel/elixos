/*
 * Stand-in for the vendor's board/canaan/common/k230_board_common.h: st7701.c
 * includes it (as "../k230_board_common.h") for k230_gpio(), which
 * golden_board.cc compiles from k230_board_common.c 358-411.
 */
#ifndef PANEL_TRACE_K230_BOARD_COMMON_H
#define PANEL_TRACE_K230_BOARD_COMMON_H

int k230_gpio(char opt, int pin, char *value);

#endif
