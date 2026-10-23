/*
 * Elixos coprocessor firmware: a DesignWare SSI master on the K230 (the
 * LoRa module's QSPI0, k230_spi.c), standard SPI, 8-bit frames, mode 0,
 * hardware chip select 0.
 */
#ifndef K230_SPI_H
#define K230_SPI_H

#include <stddef.h>
#include <stdint.h>

#define K230_SPI_OK 0
/* The FIFOs did not move for 10 ms. */
#define K230_SPI_TIMEOUT (-1)

struct k230_spi {
    uintptr_t base;
    unsigned fifo; /* FIFO depth, probed */
};

/* Probes the FIFO depth and programs the controller for `max_hz` from an
 * input clock of `clk_hz`. */
void k230_spi_init(struct k230_spi *spi, uintptr_t base, uint64_t clk_hz, uint32_t max_hz);

/* One full-duplex transfer of `len` bytes framed by one chip select. */
int k230_spi_transfer(struct k230_spi *spi, const uint8_t *tx, uint8_t *rx, size_t len);

#endif
