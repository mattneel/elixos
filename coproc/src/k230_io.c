/*
 * Elixos coprocessor firmware: K230 pads, GPIO and clocks (k230_io.h).
 */
#include "k230_io.h"
#include "k230_mmio.h"

#define OSC_HZ 24000000u

void k230_pad(unsigned io, uint32_t value)
{
    uintptr_t pad = K230_IOMUX_BASE + 4u * io;
    k230_mmio_write32(pad, (k230_mmio_read32(pad) & K230_PAD_MSC) | value);
}

static uintptr_t gpio_bank(unsigned pin)
{
    return K230_GPIO_BASE + (pin / 32) * 0x1000u;
}

void k230_gpio_set(unsigned pin, int level)
{
    uintptr_t data = gpio_bank(pin) + K230_GPIO_DR;
    uint32_t bit = 1u << (pin % 32);
    uint32_t value = k230_mmio_read32(data);
    k230_mmio_write32(data, level ? value | bit : value & ~bit);
}

void k230_gpio_output(unsigned pin, int level)
{
    uintptr_t direction = gpio_bank(pin) + K230_GPIO_DDR;
    k230_mmio_write32(direction, k230_mmio_read32(direction) | (1u << (pin % 32)));
    k230_gpio_set(pin, level);
}

void k230_gpio_input(unsigned pin)
{
    uintptr_t direction = gpio_bank(pin) + K230_GPIO_DDR;
    k230_mmio_write32(direction, k230_mmio_read32(direction) & ~(1u << (pin % 32)));
}

int k230_gpio_get(unsigned pin)
{
    return (k230_mmio_read32(gpio_bank(pin) + K230_GPIO_EXT) >> (pin % 32)) & 1u;
}

uint64_t k230_pll0_hz(void)
{
    if ((k230_mmio_read32(K230_PLL0_CFG1) >> 19) & 1u) {
        return OSC_HZ;
    }
    uint32_t cfg0 = k230_mmio_read32(K230_PLL0_CFG0);
    uint64_t fbdiv = cfg0 & 0x1fffu;
    uint64_t refdiv = (cfg0 >> 16) & 0x3fu;
    uint64_t outdiv = (cfg0 >> 24) & 0xfu;
    return (uint64_t) OSC_HZ * (fbdiv + 1) / (refdiv + 1) / (outdiv + 1);
}

static uint64_t divided(uint64_t hz, uintptr_t reg, unsigned shift)
{
    return hz / (((k230_mmio_read32(K230_CMU_BASE + reg) >> shift) & 7u) + 1u);
}

uint64_t k230_uart3_clk_hz(void)
{
    return divided(k230_pll0_hz() / 16, K230_CMU_UART_I2C_CLKDIV, 9);
}

uint64_t k230_i2c3_clk_hz(void)
{
    return divided(k230_pll0_hz() / 4, K230_CMU_UART_I2C_CLKDIV, 24);
}

uint64_t k230_ssi1_clk_hz(void)
{
    return divided(k230_pll0_hz() / 4, K230_CMU_HS_SPI_CFG, 3);
}
