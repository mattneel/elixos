/*
 * Test model of a DesignWare I2C master (dw_i2c_model.h). Register offsets
 * as LilyGO's RT-Smart driver names them (drv_i2c.h 139-176).
 */
#include <stdio.h>
#include <string.h>

#include "dw_i2c_model.h"
#include "k230_mmio_mock.h"

#define IC_TAR 0x04u
#define IC_DATA_CMD 0x10u
#define IC_RAW_INTR_STAT 0x34u
#define IC_CLR_TX_ABRT 0x54u
#define IC_CLR_STOP_DET 0x60u
#define IC_ENABLE 0x6cu
#define IC_STATUS 0x70u
#define IC_ENABLE_STATUS 0x9cu

#define CMD_READ 0x100u
#define CMD_STOP 0x200u
#define CMD_RESTART 0x400u
#define STOP_DET 0x200u
#define TX_ABRT 0x40u

#define FIFO 256

static struct {
    uint64_t base;
    struct i2c_target target;
    int active; /* 0 idle, 1 in a transfer */
    int reading; /* the current message's direction */
    int refused; /* aborted: ignore commands until STOP */
    uint8_t rx[FIFO];
    unsigned rx_head, rx_count;
    uint32_t raw;
    unsigned errors;
} i2c;

static void end_transfer(void)
{
    if (i2c.active && !i2c.refused) {
        i2c.target.stop(i2c.target.ctx);
    }
    i2c.active = 0;
    i2c.refused = 0;
    i2c.raw |= STOP_DET;
}

static void begin_message(int reading)
{
    i2c.reading = reading;
    if (i2c.refused) {
        return;
    }
    uint32_t tar = mock_peek(i2c.base + IC_TAR) & 0x3ffu;
    if (tar != i2c.target.addr || !i2c.target.start(i2c.target.ctx, reading)) {
        if (i2c.active) {
            i2c.target.stop(i2c.target.ctx);
        }
        i2c.refused = 1;
        i2c.raw |= TX_ABRT;
    }
}

static void command(uint32_t value)
{
    int reading = (value & CMD_READ) != 0;
    if (!i2c.active) {
        i2c.active = 1;
        begin_message(reading);
    } else if ((value & CMD_RESTART) || reading != i2c.reading) {
        begin_message(reading);
    }
    if (!i2c.refused) {
        if (reading) {
            if (i2c.rx_count == FIFO) {
                fprintf(stderr, "dw_i2c_model: RX FIFO overflow\n");
                i2c.errors++;
            } else {
                i2c.rx[(i2c.rx_head + i2c.rx_count++) % FIFO] = i2c.target.read(i2c.target.ctx);
            }
        } else {
            i2c.target.write(i2c.target.ctx, (uint8_t) value);
        }
    }
    if (value & CMD_STOP) {
        end_transfer();
    }
}

static void write_reg(void *ctx, uint64_t offset, uint32_t value)
{
    (void) ctx;
    if (offset == IC_DATA_CMD) {
        if (!(mock_peek(i2c.base + IC_ENABLE) & 1u)) {
            fprintf(stderr, "dw_i2c_model: command while disabled\n");
            i2c.errors++;
            return;
        }
        command(value);
    }
}

static uint32_t read_reg(void *ctx, uint64_t offset, uint32_t stored)
{
    (void) ctx;
    switch (offset) {
        case IC_DATA_CMD:
            if (i2c.rx_count == 0) {
                fprintf(stderr, "dw_i2c_model: RX FIFO underflow\n");
                i2c.errors++;
                return 0;
            } else {
                uint8_t byte = i2c.rx[i2c.rx_head];
                i2c.rx_head = (i2c.rx_head + 1) % FIFO;
                i2c.rx_count--;
                return byte;
            }
        case IC_RAW_INTR_STAT: return i2c.raw;
        case IC_CLR_STOP_DET: i2c.raw &= ~STOP_DET; return 0;
        case IC_CLR_TX_ABRT: i2c.raw &= ~TX_ABRT; return 0;
        case IC_STATUS: return 0x06u | (i2c.rx_count ? 0x08u : 0u);
        case IC_ENABLE_STATUS: return mock_peek(i2c.base + IC_ENABLE) & 1u;
        default: return stored;
    }
}

void dw_i2c_model_attach(uint64_t base, const struct i2c_target *target)
{
    memset(&i2c, 0, sizeof i2c);
    i2c.base = base;
    i2c.target = *target;
    mock_poke(base + IC_ENABLE, 0);
    struct mock_device device = { .base = base, .size = 0x100, .read = read_reg, .write = write_reg, .ctx = NULL };
    mock_attach(&device);
}

unsigned dw_i2c_model_errors(void)
{
    return i2c.errors;
}
