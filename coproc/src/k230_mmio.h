/*
 * Elixos coprocessor firmware: 32-bit device register access and busy
 * delays for the K230 drivers (panel_k230.c).
 *
 * Every register access and every delay of a driver goes through these three
 * functions. The firmware implements them in k230_mmio.c (volatile accesses
 * ordered like U-Boot's riscv writel/readl, busy waits on the mtime clock);
 * the host tests implement them in coproc/test/k230_mmio_mock.c, which models
 * the registers and records every call, so a driver's register trace can be
 * compared with the vendor code's (coproc/test/panel_trace/).
 */
#ifndef K230_MMIO_H
#define K230_MMIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void k230_mmio_write32(uintptr_t addr, uint32_t value);
uint32_t k230_mmio_read32(uintptr_t addr);
/* Waits at least `us` microseconds. */
void k230_delay_us(uint32_t us);

#ifdef __cplusplus
}
#endif

#endif
