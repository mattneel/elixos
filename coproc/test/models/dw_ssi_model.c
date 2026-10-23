/*
 * Test model of a DesignWare SSI master with an SX1262 (dw_ssi_model.h).
 */
#include <stdio.h>
#include <string.h>

#include "dw_ssi_model.h"
#include "k230_mmio_mock.h"
#include "sx1262_model.h"

#define CTRLR0 0x00u
#define SSIENR 0x08u
#define SER 0x10u
#define BAUDR 0x14u
#define TXFTLR 0x18u
#define TXFLR 0x20u
#define RXFLR 0x24u
#define SR 0x28u
#define DR 0x60u
#define DR_END 0xecu

#define MAX_DEPTH 256

static struct {
    uint64_t base;
    unsigned depth;
    unsigned reads_per_byte;
    unsigned reads;
    uint8_t tx[MAX_DEPTH], rx[MAX_DEPTH];
    unsigned tx_head, tx_count, rx_head, rx_count;
    int in_frame;
    unsigned errors;
    uint32_t ctrlr0, baudr;
} ssi;

static uint32_t reg(unsigned offset)
{
    return mock_peek(ssi.base + offset);
}

static void end_frame(void)
{
    if (ssi.in_frame) {
        sx1262_model_select(0);
        ssi.in_frame = 0;
    }
}

static void error(const char *what)
{
    fprintf(stderr, "dw_ssi_model: %s\n", what);
    ssi.errors++;
}

static void shift(void)
{
    if (!(reg(SSIENR) & 1) || reg(SER) == 0 || ssi.tx_count == 0) {
        return;
    }
    if (!ssi.in_frame) {
        ssi.in_frame = 1;
        ssi.ctrlr0 = reg(CTRLR0);
        ssi.baudr = reg(BAUDR);
        sx1262_model_select(1);
    }
    uint8_t out = ssi.tx[ssi.tx_head];
    ssi.tx_head = (ssi.tx_head + 1) % MAX_DEPTH;
    ssi.tx_count--;
    uint8_t in = sx1262_model_exchange(out);
    if (ssi.rx_count == ssi.depth) {
        error("RX FIFO overflow");
    } else {
        ssi.rx[(ssi.rx_head + ssi.rx_count) % MAX_DEPTH] = in;
        ssi.rx_count++;
    }
    if (ssi.tx_count == 0) {
        end_frame();
    }
}

static void flush(void)
{
    ssi.tx_count = ssi.rx_count = 0;
    ssi.tx_head = ssi.rx_head = 0;
}

static void write_reg(void *ctx, uint64_t offset, uint32_t value)
{
    (void) ctx;
    if (offset >= DR && offset <= DR_END) {
        if (!(reg(SSIENR) & 1)) {
            error("DR written while disabled");
        } else if (ssi.tx_count == ssi.depth) {
            error("TX FIFO overflow");
        } else {
            ssi.tx[(ssi.tx_head + ssi.tx_count) % MAX_DEPTH] = (uint8_t) value;
            ssi.tx_count++;
        }
    } else if (offset == SSIENR && !(value & 1)) {
        if (ssi.tx_count) {
            error("disabled with bytes still to send");
        }
        end_frame();
        flush();
    } else if (offset == SER && value == 0) {
        end_frame();
    }
}

static uint32_t read_reg(void *ctx, uint64_t offset, uint32_t stored)
{
    (void) ctx;
    if (++ssi.reads >= ssi.reads_per_byte) {
        ssi.reads = 0;
        shift();
    }
    switch (offset) {
        case TXFTLR: return stored & (ssi.depth - 1);
        case TXFLR: return ssi.tx_count;
        case RXFLR: return ssi.rx_count;
        case SR:
            return (ssi.in_frame ? 1u : 0u) | (ssi.tx_count < ssi.depth ? 2u : 0u) | (ssi.tx_count == 0 ? 4u : 0u)
                   | (ssi.rx_count ? 8u : 0u) | (ssi.rx_count == ssi.depth ? 16u : 0u);
        default:
            if (offset >= DR && offset <= DR_END) {
                if (ssi.rx_count == 0) {
                    error("RX FIFO underflow");
                    return 0;
                }
                uint8_t in = ssi.rx[ssi.rx_head];
                ssi.rx_head = (ssi.rx_head + 1) % MAX_DEPTH;
                ssi.rx_count--;
                return in;
            }
            return stored;
    }
}

void dw_ssi_model_attach(uint64_t base, unsigned depth, unsigned reads_per_byte)
{
    memset(&ssi, 0, sizeof ssi);
    ssi.base = base;
    ssi.depth = depth;
    ssi.reads_per_byte = reads_per_byte;
    mock_poke(base + SSIENR, 0);
    mock_poke(base + SER, 0);
    struct mock_device device = { .base = base, .size = 0x100, .read = read_reg, .write = write_reg, .ctx = NULL };
    mock_attach(&device);
}

unsigned dw_ssi_model_errors(void)
{
    return ssi.errors;
}

uint32_t dw_ssi_model_ctrlr0(void)
{
    return ssi.ctrlr0;
}

uint32_t dw_ssi_model_baudr(void)
{
    return ssi.baudr;
}
