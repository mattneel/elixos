/*
 * Stand-in for U-Boot's <asm/io.h> when the vendor display code is compiled
 * on the build host (coproc/test/panel_trace/run.sh): every writel/readl goes
 * to the register model of coproc/test/k230_mmio_mock.c, the same one the
 * port's own trace is recorded with.
 */
#ifndef PANEL_TRACE_ASM_IO_H
#define PANEL_TRACE_ASM_IO_H

#include <stdint.h>

#include "k230_mmio.h"

#define __iomem
#define writel(value, addr) k230_mmio_write32((uintptr_t) (addr), (uint32_t) (value))
#define readl(addr) k230_mmio_read32((uintptr_t) (addr))

#endif
