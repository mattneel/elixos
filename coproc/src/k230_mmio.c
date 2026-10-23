/*
 * Elixos coprocessor firmware: device register access and busy delays
 * (k230_mmio.h), for the little core in M-mode (physical addresses).
 *
 * The fences are U-Boot's riscv writel/readl ones: earlier memory writes
 * (a buffer the device will read) are ordered before the register write,
 * and a register read before later memory reads.
 */
#include "hw.h"
#include "k230_mmio.h"

void k230_mmio_write32(uintptr_t addr, uint32_t value)
{
    __asm__ volatile("fence w,o" ::: "memory");
    *(volatile uint32_t *) addr = value;
}

uint32_t k230_mmio_read32(uintptr_t addr)
{
    uint32_t value = *(volatile uint32_t *) addr;
    __asm__ volatile("fence i,r" ::: "memory");
    return value;
}

void k230_delay_us(uint32_t us)
{
    uint64_t end = hw_now_us() + us + 1;
    while (hw_now_us() < end) {
    }
}
