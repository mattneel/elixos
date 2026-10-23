/*
 * The vendor code that touches registers through plain volatile pointers
 * rather than writel/readl, compiled for the register model:
 *   k230_logo.c 9-193           the display power domain (sysctl_pwr_s)
 *   k230_board_common.c 358-411 k230_gpio()
 * (run.sh extracts those lines from the sha256-pinned files.) They are built
 * as C++ with `uint32_t`/`u32` standing for mmio32: a 32-bit cell that, when
 * it lies in the K230's register space, turns every load and store into a
 * k230_mmio_read32/write32 of its own address instead of touching memory,
 * and is a plain integer elsewhere (the vendor's locals).
 */
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "k230_mmio.h"
#include <linux/delay.h>

#include "platform.h"

struct mmio32 {
    std::uint32_t plain;

    bool device() const volatile
    {
        std::uintptr_t a = reinterpret_cast<std::uintptr_t>(this);
        return a >= 0x90000000u && a < 0x92000000u;
    }
    std::uintptr_t address() const volatile
    {
        return reinterpret_cast<std::uintptr_t>(this);
    }
    operator std::uint32_t() const volatile
    {
        return device() ? k230_mmio_read32(address()) : plain;
    }
    /* No result: the vendor never chains assignments, and a volatile
     * reference result would be a read of its own. */
    void operator=(std::uint32_t value) volatile
    {
        if (device()) {
            k230_mmio_write32(address(), value);
        } else {
            plain = value;
        }
    }
    mmio32 &operator=(std::uint32_t value)
    {
        plain = value;
        return *this;
    }
    void operator|=(std::uint32_t value) volatile
    {
        std::uint32_t old = *this;
        *this = old | value;
    }
};
static_assert(sizeof(mmio32) == 4, "mmio32 is one register");

typedef mmio32 u32;
typedef std::uint64_t u64;

extern "C" {
#define uint32_t mmio32
#include "k230_logo_power.inc"
#undef uint32_t

#include "k230_gpio.inc"

void golden_power_on_display(void)
{
    /* k230_logo.c 353: the result is not looked at. */
    (void) sysctl_pwr_set_power(SYSCTL_PD_DISP, true);
}
}
