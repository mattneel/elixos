/*
 * Test model of a Goodix GT9895 (gt9895_model.h).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gpio_model.h"
#include "gt9895_model.h"

#define MEM_BASE 0x10000u
#define MEM_SIZE 0x10000u
#define REPORT 0x10308u
#define MAX_LOG 256
#define LINE 512

static struct {
    int powered, out_of_reset;
    unsigned resets;
    uint8_t mem[MEM_SIZE];
    uint32_t addr;
    unsigned addr_bytes;
    char line[LINE];
    size_t line_len;
    unsigned reading; /* bytes read in the current read message */
    int in_read;
    char *log[MAX_LOG];
    size_t logged;
} gt;

static void append(const char *text)
{
    size_t n = strlen(text);
    if (gt.line_len + n + 1 >= LINE) {
        fprintf(stderr, "gt9895_model: transfer too long to log\n");
        exit(2);
    }
    memcpy(gt.line + gt.line_len, text, n + 1);
    gt.line_len += n;
}

static void close_read(void)
{
    if (gt.in_read) {
        char text[16];
        snprintf(text, sizeof text, " %u", gt.reading);
        append(text);
        gt.in_read = 0;
    }
}

static int start(void *ctx, int read)
{
    (void) ctx;
    if (!gt.powered || !gt.out_of_reset) {
        return 0;
    }
    close_read();
    append(gt.line_len ? (read ? " r" : " w") : (read ? "r" : "w"));
    if (read) {
        gt.in_read = 1;
        gt.reading = 0;
    } else {
        gt.addr_bytes = 0;
    }
    return 1;
}

static uint8_t *cell(uint32_t addr)
{
    static uint8_t outside;
    if (addr >= MEM_BASE && addr - MEM_BASE < MEM_SIZE) {
        return &gt.mem[addr - MEM_BASE];
    }
    outside = 0;
    return &outside;
}

static void write_byte(void *ctx, uint8_t byte)
{
    (void) ctx;
    char text[8];
    snprintf(text, sizeof text, " %02x", byte);
    append(text);
    if (gt.addr_bytes < 4) {
        gt.addr = (gt.addr_bytes == 0 ? 0 : gt.addr << 8) | byte;
        gt.addr_bytes++;
        return;
    }
    *cell(gt.addr++) = byte;
}

static uint8_t read_byte(void *ctx)
{
    (void) ctx;
    gt.reading++;
    return *cell(gt.addr++);
}

static void stop(void *ctx)
{
    (void) ctx;
    close_read();
    if (gt.logged == MAX_LOG) {
        fprintf(stderr, "gt9895_model: log full\n");
        exit(2);
    }
    gt.log[gt.logged++] = strdup(gt.line);
    gt.line_len = 0;
    gt.line[0] = 0;
}

static const struct i2c_target target = {
    .addr = 0x5d, .start = start, .write = write_byte, .read = read_byte, .stop = stop, .ctx = NULL,
};

void gt9895_model_init(void)
{
    for (size_t i = 0; i < gt.logged; i++) {
        free(gt.log[i]);
    }
    memset(&gt, 0, sizeof gt);
}

void gt9895_model_force_on(void)
{
    gt.powered = 1;
    gt.out_of_reset = 1;
}

static void on_power(void *ctx, int level)
{
    (void) ctx;
    gt.powered = level;
}

static void on_reset(void *ctx, int level)
{
    (void) ctx;
    if (level && !gt.out_of_reset) {
        gt.resets++;
    }
    gt.out_of_reset = level;
}

void gt9895_model_wire_gpio(void)
{
    gpio_model_listen(35, on_power, NULL);
    gpio_model_listen(24, on_reset, NULL);
}

const struct i2c_target *gt9895_model_target(void)
{
    return &target;
}

static void put16(uint8_t *at, unsigned value)
{
    at[0] = (uint8_t) value;
    at[1] = (uint8_t) (value >> 8);
}

static unsigned sum(const uint8_t *data, size_t n)
{
    unsigned s = 0;
    for (size_t i = 0; i < n; i++) {
        s += data[i];
    }
    return s & 0xffffu;
}

void gt9895_model_report(const struct gt9895_point *points, unsigned n)
{
    uint8_t *r = cell(REPORT);
    memset(r, 0, 8 + 10 * 8 + 2);
    r[0] = 0x80;
    r[2] = (uint8_t) n;
    put16(r + 6, sum(r, 6));
    for (unsigned i = 0; i < n; i++) {
        uint8_t *p = r + 8 + 8 * i;
        p[0] = (uint8_t) ((points[i].id << 4) | points[i].type);
        put16(p + 2, points[i].x);
        put16(p + 4, points[i].y);
        put16(p + 6, points[i].w);
    }
    put16(r + 8 + 8 * n, sum(r + 8, 8 * n));
}

void gt9895_model_corrupt_header(void)
{
    cell(REPORT)[6] ^= 0x55;
}

uint8_t gt9895_model_byte(uint32_t reg)
{
    return *cell(reg);
}

unsigned gt9895_model_resets(void)
{
    return gt.resets;
}

size_t gt9895_model_transfers(void)
{
    return gt.logged;
}

const char *gt9895_model_transfer(size_t index)
{
    return index < gt.logged ? gt.log[index] : NULL;
}

int gt9895_model_write_log(const char *path)
{
    FILE *out = fopen(path, "w");
    if (out == NULL) {
        perror(path);
        return -1;
    }
    for (size_t i = 0; i < gt.logged; i++) {
        fprintf(out, "%s\n", gt.log[i]);
    }
    return fclose(out);
}
