/*
 * Elixos coprocessor firmware: the K230 PMU's power key (INT0) and main
 * supply enable (OUT0) (power_k230.c, docs/notes/coproc-firmware.md
 * "Board drivers").
 */
#ifndef POWER_K230_H
#define POWER_K230_H

#define POWER_K230_OK 0
/* Built without the board's devices (COPROC_K230_DEVICES=0: QEMU virt). */
#define POWER_K230_NO_DEVICE (-1)
/* power_k230_poll before power_k230_open. */
#define POWER_K230_NOT_OPEN (-2)
/* power_k230_off asked the PMU to cut the supply and is still running 1 s
 * later. */
#define POWER_K230_STILL_ON (-3)

enum power_k230_key { POWER_K230_RELEASED = 0, POWER_K230_PRESSED = 1 };

/* Configures the PMU for the power key and power-off. */
int power_k230_open(void);

/* The key's change since the last poll: 1 with *key set, 0 for none, or an
 * error. */
int power_k230_poll(enum power_k230_key *key);

/* Cuts the main supply (an INT0 long press powers the board on again).
 * Returns only if the board is still on a second later. */
int power_k230_off(void);

#endif
