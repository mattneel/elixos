/*
 * Test model of a DesignWare SSI master (the K230's QSPI0 at 0x91582000,
 * which LilyGO's RT-Smart build drives as `spi1` for the LoRa module) with
 * the SX1262 model on its chip select 0.
 *
 * FIFOs of `depth` entries; TXFTLR keeps only the bits a FIFO of that depth
 * has (the readback Canaan's Linux driver probes the depth with,
 * spi-dw-core-k230.c 1371-1382). While enabled with a slave selected, one
 * byte shifts out of the TX FIFO (and its answer into the RX FIFO) every
 * `reads_per_byte` register reads, so the FIFO levels move as the driver
 * polls them. The chip select frames a command from the first byte shifted
 * until the TX FIFO runs empty: a DW master drops CS when its TX FIFO empties
 * (spi-dw-mmio-k230.c 58-61), so a driver that lets the FIFO run dry splits
 * the command, which the SX1262 model then sees as two. Overflows,
 * underflows and writes while disabled are counted as errors.
 */
#ifndef DW_SSI_MODEL_H
#define DW_SSI_MODEL_H

#include <stdint.h>

void dw_ssi_model_attach(uint64_t base, unsigned depth, unsigned reads_per_byte);
unsigned dw_ssi_model_errors(void);
/* The CTRLR0 and BAUDR values of the last frame shifted. */
uint32_t dw_ssi_model_ctrlr0(void);
uint32_t dw_ssi_model_baudr(void);

#endif
