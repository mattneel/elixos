/*
 * Elixos coprocessor firmware: the payload loaded next to the image
 * (coproc/tools/mkpayload.py has the layout).
 */
#ifndef COPROC_PAYLOAD_H
#define COPROC_PAYLOAD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PAYLOAD_KIND_ENV 1
#define PAYLOAD_KIND_AVM 2
#define PAYLOAD_KIND_FILE 3
#define PAYLOAD_MAX_AVMS 8

struct PayloadAVM
{
    const void *data;
    size_t size;
    const char *name;
};

struct Payload
{
    struct PayloadAVM avms[PAYLOAD_MAX_AVMS];
    int avm_count;
    size_t size;
};

/*
 * Checks the payload at `base` (at most `limit` bytes), applies its
 * environment (setenv) and files (ramfs) and lists its AVM packs, in order.
 * Prints the reason and returns false if it is missing or damaged.
 */
bool payload_load(const uint8_t *base, size_t limit, struct Payload *out);

#endif
