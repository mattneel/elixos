/*
 * Stand-in for U-Boot's <linux/delay.h> on the build host: delays are
 * recorded by the register model in microseconds, as the port's are.
 */
#ifndef PANEL_TRACE_LINUX_DELAY_H
#define PANEL_TRACE_LINUX_DELAY_H

#include "k230_mmio.h"

#define mdelay(ms) k230_delay_us((unsigned) (ms) * 1000u)
#define udelay(us) k230_delay_us((unsigned) (us))

#endif
