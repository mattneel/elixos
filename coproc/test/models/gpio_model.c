/*
 * Test model of the K230 GPIO blocks (gpio_model.h).
 */
#include <stddef.h>

#include "gpio_model.h"
#include "k230_mmio_mock.h"

#define BASE 0x9140B000u
#define BANK 0x1000u
#define DR 0x00u
#define DDR 0x04u
#define EXT 0x50u
#define PINS 64

static struct {
    void (*listen)(void *ctx, int level);
    void *listen_ctx;
    int (*drive)(void *ctx);
    void *drive_ctx;
    int last; /* last level reported to the listener, -1 none */
} pins[PINS];

static int level_of(unsigned pin)
{
    uint64_t bank = BASE + (pin / 32) * BANK;
    uint32_t bit = 1u << (pin % 32);
    if (!(mock_peek(bank + DDR) & bit)) {
        return -1;
    }
    return (mock_peek(bank + DR) & bit) ? 1 : 0;
}

int gpio_model_output(unsigned pin)
{
    return level_of(pin);
}

static void changed(unsigned bank)
{
    for (unsigned pin = bank * 32; pin < bank * 32 + 32; pin++) {
        if (pins[pin].listen == NULL) {
            continue;
        }
        int level = level_of(pin);
        if (level >= 0 && level != pins[pin].last) {
            pins[pin].last = level;
            pins[pin].listen(pins[pin].listen_ctx, level);
        }
    }
}

static void write_reg(void *ctx, uint64_t offset, uint32_t value)
{
    (void) value;
    unsigned bank = (unsigned) (uintptr_t) ctx;
    if (offset == DR || offset == DDR) {
        changed(bank);
    }
}

static uint32_t read_reg(void *ctx, uint64_t offset, uint32_t stored)
{
    unsigned bank = (unsigned) (uintptr_t) ctx;
    if (offset != EXT) {
        return stored;
    }
    uint32_t value = 0;
    for (unsigned i = 0; i < 32; i++) {
        unsigned pin = bank * 32 + i;
        int level = level_of(pin);
        if (level < 0) {
            level = pins[pin].drive != NULL ? pins[pin].drive(pins[pin].drive_ctx) : 0;
        }
        value |= (uint32_t) (level & 1) << i;
    }
    return value;
}

void gpio_model_attach(void)
{
    for (unsigned i = 0; i < PINS; i++) {
        pins[i].listen = NULL;
        pins[i].drive = NULL;
        pins[i].last = -1;
    }
    for (unsigned bank = 0; bank < 2; bank++) {
        /* The DesignWare block's reset state: every pin an input, data 0. */
        mock_poke(BASE + bank * BANK + DR, 0);
        mock_poke(BASE + bank * BANK + DDR, 0);
        struct mock_device device = {
            .base = BASE + bank * BANK,
            .size = BANK,
            .read = read_reg,
            .write = write_reg,
            .ctx = (void *) (uintptr_t) bank,
        };
        mock_attach(&device);
    }
}

void gpio_model_listen(unsigned pin, void (*fn)(void *ctx, int level), void *ctx)
{
    pins[pin].listen = fn;
    pins[pin].listen_ctx = ctx;
    pins[pin].last = level_of(pin);
}

void gpio_model_drive(unsigned pin, int (*fn)(void *ctx), void *ctx)
{
    pins[pin].drive = fn;
    pins[pin].drive_ctx = ctx;
}
