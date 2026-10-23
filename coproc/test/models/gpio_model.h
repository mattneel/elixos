/*
 * Test model of the K230's two GPIO blocks (GPIO0 at 0x9140B000 for IO0-31,
 * GPIO1 at 0x9140C000 for IO32-63; port A data +0x00, direction +0x04,
 * external port +0x50), attached to the register mock (k230_mmio_mock.h).
 *
 * A pin driven as an output (direction bit set) has its data bit as level;
 * a device model listens to the level of the pins it is wired to
 * (gpio_model_listen) and drives the level of its own outputs, which the
 * external port register shows for pins configured as inputs
 * (gpio_model_drive).
 */
#ifndef GPIO_MODEL_H
#define GPIO_MODEL_H

#include <stdint.h>

/* Attaches the model; call after mock_reset. */
void gpio_model_attach(void);

/* fn(ctx, level) runs whenever the level the K230 drives on `pin` changes
 * (an output whose data bit changes, or a pin turned into an output). */
void gpio_model_listen(unsigned pin, void (*fn)(void *ctx, int level), void *ctx);

/* fn(ctx) answers the level a device drives on `pin`, read through the
 * external port when the pin is an input. */
void gpio_model_drive(unsigned pin, int (*fn)(void *ctx), void *ctx);

/* The level the K230 drives on `pin` (-1: not an output). */
int gpio_model_output(unsigned pin);

#endif
