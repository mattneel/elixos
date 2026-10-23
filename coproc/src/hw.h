/*
 * Elixos coprocessor firmware: the bare-metal layer under AtomVM (console,
 * clock, idle wait). See board.h for the build parameters.
 */
#ifndef COPROC_HW_H
#define COPROC_HW_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

void hw_console_init(void);
void hw_console_write(const char *bytes, size_t len);

/* Microseconds since the first hw_clock_init (the mtime counter). */
void hw_clock_init(void);
uint64_t hw_now_us(void);

/*
 * Waits until about `us` microseconds have passed or an interrupt is pending
 * (wfi with a one-shot mtimecmp); returns early, never late. Without
 * COPROC_MTIMECMP_ADDR it returns at once and the caller polls.
 */
void hw_idle(uint64_t us);

uint64_t hw_mhartid(void);
uint64_t hw_marchid(void);

/* Memory statistics for the banner and the report. */
size_t hw_heap_used(void);
size_t hw_heap_size(void);

#endif
