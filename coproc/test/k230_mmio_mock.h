/*
 * Host test double for coproc/src/k230_mmio.h: a register model of the K230
 * blocks the board drivers touch, recording every access and delay in order.
 *
 * Registers hold what was last written. A register never written reads a
 * fixed pattern derived from its address (so read-modify-write code must
 * keep the bits it does not own, exactly as the vendor code does), except
 * the status registers the panel bring-up polls:
 *   DSI PHY_STATUS     (0x908500b0)  0x1fbd from its `phy_ready_after`-th read
 *   DSI PHY_TST_CTRL1  (0x908500b8)  0x580 from its `fsm_done_after`-th read
 *   disp_lpi_state     (0x91103040)  bit 1 (powered) unless `power_fails`
 * A negative `*_after` never reports ready.
 *
 * Device models (coproc/test/models/: the GPIO blocks, the DesignWare I2C
 * and SSI controllers with a GT9895 and an SX1262 behind them, the PMU,
 * UART3) attach to an address range: they see every write after it is
 * stored and answer every read. Delays advance a virtual clock
 * (mock_now_us) the models use for BUSY lines and the like.
 */
#ifndef K230_MMIO_MOCK_H
#define K230_MMIO_MOCK_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "k230_mmio.h"

#ifdef __cplusplus
extern "C" {
#endif

struct mock_config {
    long phy_ready_after;
    long fsm_done_after;
    int power_fails;
};

enum mock_kind { MOCK_WRITE = 'W', MOCK_READ = 'R', MOCK_DELAY = 'D' };

struct mock_event {
    char kind;
    uint64_t addr; /* 0 for delays */
    uint32_t value; /* written, read, or microseconds */
};

/* A device model on [base, base + size): `read` answers a read (`stored` is
 * what the register holds), `write` sees a write after it is stored. Either
 * may be NULL. */
struct mock_device {
    uint64_t base;
    uint64_t size;
    uint32_t (*read)(void *ctx, uint64_t offset, uint32_t stored);
    void (*write)(void *ctx, uint64_t offset, uint32_t value);
    void *ctx;
};

/* The nominal model the trace test runs: each poll succeeds on its 3rd read. */
extern const struct mock_config mock_nominal;

/* A scenario from its name ("nominal", "dphy-timeout"), or NULL. */
const struct mock_config *mock_scenario(const char *name);

/* Forgets every register, event and device; the clock restarts at 0. */
void mock_reset(const struct mock_config *config);

/* Attaches a device model (up to 16; the struct is copied). */
void mock_attach(const struct mock_device *device);

size_t mock_event_count(void);
const struct mock_event *mock_events(void);
/* Forgets the events, keeps the registers. */
void mock_clear_events(void);

/* The value a register holds now (the model's view, not recorded). */
uint32_t mock_peek(uint64_t addr);
/* Sets a register without recording it (a value the hardware came up with). */
void mock_poke(uint64_t addr, uint32_t value);

/* Microseconds of delay so far. */
uint64_t mock_now_us(void);

/* One line per event: "W 0x90850000 0x00000001", "R ...", "D 200000". */
int mock_write_trace(const char *path);

#ifdef __cplusplus
}
#endif

#endif
