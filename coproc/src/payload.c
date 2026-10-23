/*
 * Elixos coprocessor firmware: reads the payload (coproc/tools/mkpayload.py).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "payload.h"
#include "ramfs.h"
#include "ring.h"

#define HEADER_SIZE 32
#define ENTRY_SIZE 64
#define NAME_SIZE 48

static uint32_t u32(const uint8_t *p)
{
    return (uint32_t) p[0] | ((uint32_t) p[1] << 8) | ((uint32_t) p[2] << 16) | ((uint32_t) p[3] << 24);
}

/* KEY=VALUE lines; a line without '=' is ignored. */
static void apply_env(const char *text, size_t size)
{
    char *copy = malloc(size + 1);
    if (copy == NULL) {
        return;
    }
    memcpy(copy, text, size);
    copy[size] = '\0';
    char *line = copy;
    while (line && *line) {
        char *next = strchr(line, '\n');
        if (next) {
            *next++ = '\0';
        }
        char *equals = strchr(line, '=');
        if (equals && equals != line) {
            *equals = '\0';
            setenv(line, equals + 1, 1);
        }
        line = next;
    }
    free(copy);
}

bool payload_load(const uint8_t *base, size_t limit, struct Payload *out)
{
    memset(out, 0, sizeof(*out));
    if (memcmp(base, "ELXP", 4) != 0) {
        printf("elixos coproc: no payload at %p\n", (const void *) base);
        return false;
    }
    uint32_t version = u32(base + 4), count = u32(base + 8), size = u32(base + 12), crc = u32(base + 16);
    if (version != 1 || size > limit || size < HEADER_SIZE + count * ENTRY_SIZE) {
        printf("elixos coproc: bad payload header (version %u, size %u, limit %zu)\n",
            (unsigned) version, (unsigned) size, limit);
        return false;
    }
    if (ring_crc32(0, base + HEADER_SIZE, size - HEADER_SIZE) != crc) {
        printf("elixos coproc: payload CRC mismatch (%u bytes)\n", (unsigned) size);
        return false;
    }
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *entry = base + HEADER_SIZE + i * ENTRY_SIZE;
        uint32_t kind = u32(entry), offset = u32(entry + 4), length = u32(entry + 8);
        const char *name = (const char *) entry + 16;
        if (offset > size || length > size - offset || memchr(name, '\0', NAME_SIZE) == NULL) {
            printf("elixos coproc: bad payload entry %u\n", (unsigned) i);
            return false;
        }
        const uint8_t *data = base + offset;
        switch (kind) {
            case PAYLOAD_KIND_ENV:
                apply_env((const char *) data, length);
                break;
            case PAYLOAD_KIND_AVM:
                if (out->avm_count == PAYLOAD_MAX_AVMS) {
                    printf("elixos coproc: more than %d AVM packs\n", PAYLOAD_MAX_AVMS);
                    return false;
                }
                out->avms[out->avm_count].data = data;
                out->avms[out->avm_count].size = length;
                out->avms[out->avm_count].name = name;
                out->avm_count++;
                break;
            case PAYLOAD_KIND_FILE:
                if (ramfs_put(name, data, length) != 0) {
                    printf("elixos coproc: cannot store %s\n", name);
                    return false;
                }
                break;
            default:
                printf("elixos coproc: unknown payload entry kind %u\n", (unsigned) kind);
                return false;
        }
    }
    out->size = size;
    return true;
}
