/*
 * Elixos coprocessor firmware: a DesignWare I2C master on the K230 (I2C3,
 * the touch controller's bus, k230_i2c.c), 7-bit addresses, fast mode.
 */
#ifndef K230_I2C_H
#define K230_I2C_H

#include <stddef.h>
#include <stdint.h>

#define K230_I2C_OK 0
/* The bus stayed busy, or a byte did not move, past the vendor's timeouts. */
#define K230_I2C_TIMEOUT (-1)
/* The target did not acknowledge (TX_ABRT). */
#define K230_I2C_NACK (-2)

/* Programs the controller for 400 kHz from an input clock of `clk_hz`. */
void k230_i2c_init(uintptr_t base, uint64_t clk_hz);

/* One write message ending with a STOP. */
int k230_i2c_write(uintptr_t base, uint8_t addr, const uint8_t *data, size_t len);

/* A write message, a repeated START, a read message ending with a STOP. */
int k230_i2c_write_read(uintptr_t base, uint8_t addr, const uint8_t *out, size_t out_len, uint8_t *in, size_t in_len);

#endif
