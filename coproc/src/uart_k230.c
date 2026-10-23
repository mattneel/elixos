/*
 * Elixos coprocessor firmware: UART3 on the K230 (uart_k230.h).
 *
 * Canaan's RT-Smart UART driver's set-up as LilyGO's tree has it (LT-RT =
 * Xinyuan-LilyGO/T-Display-K230_canmv_rt @ abb07090,
 * canmv_k230/src/rtsmart/rtsmart/kernel/bsp/maix3/drivers/interdrv/):
 *   uart_canaan/drv_uart.c 263-314   kd_uart_init: UART3's leaf divider
 *                                    1/1, then the divisor from the clock
 *                                    it reads back: fdiv = clk / 115200,
 *                                    DLL/DLH = fdiv / 16, DLF = the
 *                                    rounded remainder (16ths), refused
 *                                    past +2 %; LCR, IER, DLAB, divisor,
 *                                    8N1, FIFO on with RX trigger 2
 *                                    (UART_RECEIVE_FIFO_16, drv_uart.h
 *                                    99-102), MCR 0, status read clear,
 *                                    scratch 0
 *   uart_canaan/drv_uart.c 47-63     registers, 4 bytes apart; DLF at 0xC0
 *   sysctl/sysctl_clock/sysctl_clk.c 2712-2724, 1234-1239, 3237-3238,
 *                                    3279-3280
 *                                    UART3's clock: PLL0 / 16 / (divider
 *                                    [11:9] of CMU + 0x2C + 1); the 1/1
 *                                    divider write sets bit 31 too
 * The clock is read back from the PLL and divider registers, as the vendor
 * does, not assumed (the firmware used to program divisor 27 for an assumed
 * 50 MHz). The
 * one difference: the receive interrupt is not enabled (IER stays 0, as in
 * Canaan's console variant, uart/drv_uart.c 138-164): the firmware polls.
 * Pads (board DT, k230_canmv_v3p0.dts 166, 168): IO50 = UART3 TXD
 * (function 1, OE), IO51 = UART3 RXD (function 1, IE), drive 7, Schmitt.
 */
#include "k230_io.h"
#include "k230_mmio.h"
#include "uart_k230.h"

#define UART3_BASE 0x91403000u
#define UART_RBR 0x00u
#define UART_DLL 0x00u
#define UART_DLH 0x04u
#define UART_IER 0x04u
#define UART_FCR 0x08u
#define UART_LCR 0x0cu
#define UART_MCR 0x10u
#define UART_LSR 0x14u
#define UART_SCH 0x1cu
#define UART_USR 0x7cu
#define UART_DLF 0xc0u

#define PIN_TXD 50u
#define PIN_RXD 51u
#define PAD_TXD (K230_PAD_SEL(1) | K230_PAD_OE | K230_PAD_DS(7) | K230_PAD_ST)
#define PAD_RXD (K230_PAD_SEL(1) | K230_PAD_IE | K230_PAD_DS(7) | K230_PAD_ST)

/* drv_uart.h 99-102: UART_RECEIVE_FIFO_16 is 2. */
#define FCR_FIFO_ON_RX16 (0x01u | (2u << 6))

static void wr(uintptr_t reg, uint32_t value)
{
    k230_mmio_write32(UART3_BASE + reg, value);
}

int uart_k230_init(void)
{
    k230_pad(PIN_TXD, PAD_TXD);
    k230_pad(PIN_RXD, PAD_RXD);

    uintptr_t clkdiv = K230_CMU_BASE + K230_CMU_UART_I2C_CLKDIV;
    k230_mmio_write32(clkdiv, (k230_mmio_read32(clkdiv) & 0xfffff1ffu) | (1u << 31));
    float clock = (float) k230_uart3_clk_hz();

    float fdiv = 1.0f * clock / UART_K230_BAUD;
    uint16_t dl = (uint16_t) (fdiv / 16);
    uint8_t frac = (uint8_t) (0.5f + fdiv - dl * 16);
    if (dl == 0) {
        dl = 1;
        frac = 0;
    }
    float baud = 1.0f * clock / (dl * 16 + frac);
    if ((baud - UART_K230_BAUD) / UART_K230_BAUD > 0.02f) {
        return UART_K230_BAD_CLOCK;
    }

    wr(UART_LCR, 0x00);
    wr(UART_IER, 0x00);
    wr(UART_LCR, 0x80);
    wr(UART_DLL, (uint8_t) dl);
    wr(UART_DLH, (uint8_t) (dl >> 8));
    wr(UART_DLF, frac);
    wr(UART_LCR, 0x03);
    wr(UART_FCR, FCR_FIFO_ON_RX16);
    wr(UART_MCR, 0x00);
    (void) k230_mmio_read32(UART3_BASE + UART_LSR);
    (void) k230_mmio_read32(UART3_BASE + UART_RBR);
    (void) k230_mmio_read32(UART3_BASE + UART_USR);
    (void) k230_mmio_read32(UART3_BASE + UART_FCR);
    wr(UART_SCH, 0x00);
    return UART_K230_OK;
}
