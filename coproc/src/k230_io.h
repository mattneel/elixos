/*
 * Elixos coprocessor firmware: the K230's pads, GPIO and peripheral clocks,
 * shared by the board drivers (panel_k230.c, touch_k230.c, lora_k230.c,
 * power_k230.c, uart_k230.c). Every access goes through k230_mmio.h.
 *
 * Sources (pinned in docs/notes/coproc-firmware.md, "Board drivers"):
 *   LT-RT = Xinyuan-LilyGO/T-Display-K230_canmv_rt @ abb07090,
 *     canmv_k230/src/rtsmart/rtsmart/kernel/bsp/maix3/ (BSP) and
 *     canmv_k230/src/rtsmart/mpp/userapps/sample/sample_display/fpioa/rt_fpioa.c
 */
#ifndef K230_IO_H
#define K230_IO_H

#include <stdint.h>

/* Pad registers: one word per IO at IOMUX_BASE + 4 n (rt_fpioa.c 16, 228-245):
 * ST[0] DS[4:1] PD[5] PU[6] OE[7] IE[8] MSC[9] SL[10] SEL[13:11] DI[31]. */
#define K230_IOMUX_BASE 0x91105000u
#define K230_PAD_ST (1u << 0)
#define K230_PAD_DS(n) ((uint32_t) (n) << 1)
#define K230_PAD_PU (1u << 6)
#define K230_PAD_OE (1u << 7)
#define K230_PAD_IE (1u << 8)
#define K230_PAD_MSC (1u << 9)
#define K230_PAD_SEL(n) ((uint32_t) (n) << 11)
/* rt_fpioa.c 410: a pad as GPIO (SEL 0), IE, OE, drive 7, Schmitt. */
#define K230_PAD_GPIO (K230_PAD_IE | K230_PAD_OE | K230_PAD_DS(7) | K230_PAD_ST)

/* GPIO0 (IO0-31) and GPIO1 (IO32-63), DesignWare APB GPIO port A (BSP
 * board/board.h 230-234; drivers/interdrv/gpio/drv_gpio.h 32-33, 43). */
#define K230_GPIO_BASE 0x9140B000u
#define K230_GPIO_DR 0x00u
#define K230_GPIO_DDR 0x04u
#define K230_GPIO_EXT 0x50u

/* The clock and boot blocks (BSP board/board.h 161; sysctl_clk.h 36-50;
 * sysctl_boot.h 33-41). */
#define K230_CMU_BASE 0x91100000u
#define K230_CMU_HS_SPI_CFG 0x20u
#define K230_CMU_UART_I2C_CLKDIV 0x2cu
#define K230_PLL0_CFG0 0x91102000u
#define K230_PLL0_CFG1 0x91102004u

/* Writes a pad's configuration keeping its voltage select (MSC), as
 * rt_fpioa.c 266 does: (old & 0x200) | value. */
void k230_pad(unsigned io, uint32_t value);

/* GPIO pin `pin` (= IO number) as an output at `level`: the direction bit,
 * then the data bit in the data register's own value. */
void k230_gpio_output(unsigned pin, int level);
/* Sets or clears an output's data bit (read-modify-write). */
void k230_gpio_set(unsigned pin, int level);
/* GPIO pin `pin` as an input (direction bit cleared). */
void k230_gpio_input(unsigned pin);
/* The pin's level from the external port register. */
int k230_gpio_get(unsigned pin);

/* PLL0's output in Hz: 24 MHz x (fbdiv + 1) / (refdiv + 1) / (outdiv + 1),
 * or 24 MHz when bypassed (sysctl_clk.c 265-273, 530-575). */
uint64_t k230_pll0_hz(void);

/* The leaf clocks the drivers use, in Hz, from the dividers as they are
 * programmed now (sysctl_clk.c parents 1162-1166, 1193-1194, 1234-1239,
 * 1249-1254; ratios 3210-3211, 3237-3238, 3279-3280, 3298-3299). */
uint64_t k230_uart3_clk_hz(void);
uint64_t k230_i2c3_clk_hz(void);
uint64_t k230_ssi1_clk_hz(void);

#endif
