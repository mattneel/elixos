/*
 * Test model of a DesignWare I2C master (the K230's I2C3 at 0x91408000)
 * with I2C targets behind it.
 *
 * Commands written to IC_DATA_CMD take effect at once: a byte is written to
 * the addressed target, or (CMD bit) read from it into the RX FIFO; a
 * RESTART bit, or a change of direction, starts a new message; a STOP bit
 * ends the transfer and raises STOP_DET. A target that is absent, or
 * refuses, aborts the transfer (TX_ABRT, nothing read). The FIFOs never
 * fill: IC_STATUS always shows room to send and the bus idle.
 */
#ifndef DW_I2C_MODEL_H
#define DW_I2C_MODEL_H

#include <stddef.h>
#include <stdint.h>

struct i2c_target {
    uint8_t addr;
    /* A message starts: 1 read, 0 write. Return 0 to not acknowledge. */
    int (*start)(void *ctx, int read);
    void (*write)(void *ctx, uint8_t byte);
    uint8_t (*read)(void *ctx);
    void (*stop)(void *ctx);
    void *ctx;
};

void dw_i2c_model_attach(uint64_t base, const struct i2c_target *target);
/* Commands written while the controller was disabled, RX underflows. */
unsigned dw_i2c_model_errors(void);

#endif
