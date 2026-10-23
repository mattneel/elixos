/*
 * Test model of a Goodix GT9895 on I2C (address 0x5D): 4-byte big-endian
 * register addresses, a memory at 0x10000-0x1FFFF holding the touch report
 * at 0x10308 (layout as LilyGO's Linux driver reads it: 8-byte header with
 * status 0x80 and the point count in byte 2 and a u16 sum, 8-byte points
 * id << 4 | type, x, y, w little-endian, a u16 sum after the points).
 * It answers only while powered (IO35 high) and out of reset (IO24 high).
 *
 * Every transfer is logged as one line: "w 00 01 03 08 r 26" is the
 * address written, then 26 bytes read after a repeated start.
 */
#ifndef GT9895_MODEL_H
#define GT9895_MODEL_H

#include <stddef.h>
#include <stdint.h>

#include "dw_i2c_model.h"

struct gt9895_point {
    uint8_t id, type;
    uint16_t x, y, w;
};

void gt9895_model_init(void);
/* Powered and out of reset without the GPIO model (the vendor-code run). */
void gt9895_model_force_on(void);
/* Wires power (IO35) and reset (IO24) to the GPIO model. */
void gt9895_model_wire_gpio(void);
/* The I2C target, for dw_i2c_model_attach or direct calls. */
const struct i2c_target *gt9895_model_target(void);

/* A touch report with `n` points (n = 0: every finger lifted). */
void gt9895_model_report(const struct gt9895_point *points, unsigned n);
/* Breaks the header checksum of the current report. */
void gt9895_model_corrupt_header(void);
uint8_t gt9895_model_byte(uint32_t reg);
/* Times the reset line went from low to high. */
unsigned gt9895_model_resets(void);

int gt9895_model_write_log(const char *path);
size_t gt9895_model_transfers(void);
const char *gt9895_model_transfer(size_t index);

#endif
