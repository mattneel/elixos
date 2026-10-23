/*
 * Elixos coprocessor firmware: the GT9895 touch controller of the
 * T-Display K230 on I2C3 (touch_k230.c, docs/notes/coproc-firmware.md
 * "Board drivers").
 */
#ifndef TOUCH_K230_H
#define TOUCH_K230_H

#include <stddef.h>
#include <stdint.h>

#define TOUCH_K230_OK 0
/* Built without the board's devices (COPROC_K230_DEVICES=0: QEMU virt). */
#define TOUCH_K230_NO_DEVICE (-1)
/* The controller did not answer on I2C3 at 0x5D. */
#define TOUCH_K230_NO_ANSWER (-2)
/* It answered, but the 0xAA test pattern did not read back (3 tries). */
#define TOUCH_K230_CONFIRM_FAILED (-3)
/* touch_k230_poll before a successful touch_k230_open. */
#define TOUCH_K230_NOT_OPEN (-4)
/* The bus timed out during a poll. */
#define TOUCH_K230_BUS_ERROR (-5)

/* The panel's coordinates (568 x 1232 portrait). */
#define TOUCH_K230_WIDTH 568
#define TOUCH_K230_HEIGHT 1232

enum touch_k230_action { TOUCH_K230_DOWN = 0, TOUCH_K230_MOVE = 1, TOUCH_K230_UP = 2 };

struct touch_k230_event {
    enum touch_k230_action action;
    uint16_t x, y;
};

/* Powers and resets the controller, checks it answers and sets up I2C3.
 * Runs once per firmware boot; later calls return the first result. */
int touch_k230_open(void);

/* Reads the controller's touch report and turns the first finger into at
 * most one event. Returns the number of events (0 or 1) or an error. */
int touch_k230_poll(struct touch_k230_event *event);

#endif
