/*
 * Stand-in for U-Boot's <common.h> on the build host: the C library and the
 * one bit macro the vendor display code takes from it (linux/bitops.h).
 */
#ifndef PANEL_TRACE_COMMON_H
#define PANEL_TRACE_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <asm/io.h>
#include <linux/delay.h>

#ifndef BIT_MASK
#define BIT_MASK(nr) (1UL << ((nr) % 64))
#endif

#endif
