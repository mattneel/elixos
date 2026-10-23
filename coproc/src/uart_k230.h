/*
 * Elixos coprocessor firmware: UART3, the little core's console on the
 * T-Display K230 (IO50 TX / IO51 RX, channel 1 of the CH342K), set up
 * from scratch: U-Boot leaves it alone (uart_k230.c).
 */
#ifndef UART_K230_H
#define UART_K230_H

#define UART_K230_OK 0
/* 115200 baud is more than 2 % off with the clock the CMU gives UART3. */
#define UART_K230_BAD_CLOCK (-1)

#define UART_K230_BAUD 115200u

/* Pads, UART3's clock divider, 8N1 at 115200 with FIFOs. */
int uart_k230_init(void);

#endif
