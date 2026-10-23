/*
 * The coprocessor's ring (coproc/src/ring.c) against the shared golden
 * vectors (spec/ring.vectors), the same checks shim/src/ring.zig runs. Built
 * and run on the build host:
 *
 *   cc -std=c11 -Wall -Wextra -Werror -Icoproc/src -o ring_vectors_test \
 *      coproc/test/ring_vectors_test.c coproc/src/ring.c
 *   ./ring_vectors_test spec/ring.vectors
 *
 * Prints one line per vector kind with its count and exits non-zero on the
 * first mismatch.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ring.h"

static const char *vectors_path;
static int line_number;

static void fail(const char *what)
{
    fprintf(stderr, "%s:%d: %s\n", vectors_path, line_number, what);
    exit(1);
}

static void expect(int ok, const char *what)
{
    if (!ok) {
        fail(what);
    }
}

static size_t hex(const char *text, uint8_t *out, size_t max)
{
    size_t len = strlen(text);
    expect(len % 2 == 0 && len / 2 <= max, "bad hex field");
    for (size_t i = 0; i < len / 2; i++) {
        unsigned byte;
        expect(sscanf(text + 2 * i, "%2x", &byte) == 1, "bad hex digit");
        out[i] = (uint8_t) byte;
    }
    return len / 2;
}

/* Splits `line` at `sep` in place; returns the fields (empty ones kept). */
static int split(char *line, char sep, char **fields, int max)
{
    int n = 0;
    fields[n++] = line;
    for (char *p = line; *p; p++) {
        if (*p == sep) {
            *p = '\0';
            expect(n < max, "too many fields");
            fields[n++] = p + 1;
        }
    }
    return n;
}

static void expect_frame(enum RingReadResult result, uint32_t seq, uint32_t len, const uint8_t *got,
    uint32_t want_seq, const uint8_t *want, size_t want_len)
{
    expect(result == RING_READ_FRAME, "expected a frame");
    expect(seq == want_seq, "frame seq");
    expect(len == want_len && memcmp(got, want, want_len) == 0, "frame payload");
}

int main(int argc, char **argv)
{
    vectors_path = argc > 1 ? argv[1] : "spec/ring.vectors";
    FILE *in = fopen(vectors_path, "r");
    if (in == NULL) {
        perror(vectors_path);
        return 1;
    }
    static uint8_t region[1 << 20] __attribute__((aligned(8)));
    static uint8_t buffer[RING_MAX_LEN];
    static uint8_t scratch[4096], other[4096];
    static char line[16384];
    int counted[6] = { 0 };
    const char *kinds[6] = { "crc", "capacity", "header", "frame", "decode", "wrap" };

    while (fgets(line, sizeof(line), in)) {
        line_number++;
        line[strcspn(line, "\r\n")] = '\0';
        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }
        char *f[8];
        int n = split(line, '\t', f, 8);
        uint32_t seq, len;

        if (strcmp(f[0], "crc") == 0) {
            expect(n == 3, "crc fields");
            size_t size = hex(f[1], scratch, sizeof(scratch));
            expect(ring_crc32(0, scratch, size) == (uint32_t) strtoul(f[2], NULL, 16), "crc");
            counted[0]++;
        } else if (strcmp(f[0], "capacity") == 0) {
            expect(n == 3, "capacity fields");
            uint64_t size = strtoull(f[1], NULL, 10);
            uint32_t want = strcmp(f[2], "invalid") == 0 ? 0 : (uint32_t) strtoul(f[2], NULL, 10);
            expect(ring_capacity_for(size) == want, "capacity");
            counted[1]++;
        } else if (strcmp(f[0], "header") == 0) {
            expect(n == 3, "header fields");
            size_t size = strtoull(f[1], NULL, 10);
            size_t want = hex(f[2], scratch, sizeof(scratch));
            expect(want == RING_HEADER_SIZE && size <= sizeof(region), "header size");
            memset(region, 0xa5, size);
            for (int b = 0; b < 2; b++) {
                struct RingHalf half = ring_half(region, size, b);
                expect(!ring_valid(half), "valid before initialisation");
                ring_initialize(half);
                expect(ring_valid(half), "invalid after initialisation");
                expect(memcmp(half.bytes, scratch, RING_HEADER_SIZE) == 0, "header bytes");
                for (size_t i = RING_HEADER_SIZE; i < half.size; i++) {
                    expect(half.bytes[i] == 0, "data area not zeroed");
                }
            }
            counted[2]++;
        } else if (strcmp(f[0], "frame") == 0) {
            expect(n == 4, "frame fields");
            uint32_t want_seq = (uint32_t) strtoul(f[1], NULL, 10);
            size_t payload_len = hex(f[2], scratch, sizeof(scratch));
            size_t want = hex(f[3], other, sizeof(other));
            struct RingHalf half = ring_half(region, 4096, 0);
            ring_initialize(half);
            struct RingWriter writer = ring_writer_open(half);
            writer.seq = want_seq;
            expect(ring_write(&writer, scratch, (uint32_t) payload_len) == RING_WRITE_OK, "write");
            expect(ring_load(half, RING_FIELD_HEAD) == want, "head after write");
            expect(memcmp(half.bytes + RING_HEADER_SIZE, other, want) == 0, "frame bytes");
            struct RingReader reader = { .half = half, .capacity = ring_load(half, RING_FIELD_CAPACITY) };
            enum RingReadResult result = ring_read(&reader, buffer, &seq, &len);
            expect_frame(result, seq, len, buffer, want_seq, scratch, payload_len);
            counted[3]++;
        } else if (strcmp(f[0], "decode") == 0) {
            expect(n == 3, "decode fields");
            struct RingHalf half = ring_half(region, 4096, 1);
            ring_initialize(half);
            size_t stream = hex(f[1], half.bytes + RING_HEADER_SIZE, 1024);
            ring_store(half, RING_FIELD_HEAD, (uint32_t) stream);
            struct RingReader reader = { .half = half, .capacity = ring_load(half, RING_FIELD_CAPACITY) };
            enum RingReadResult result = ring_read(&reader, buffer, &seq, &len);
            char *e[5];
            int m = split(f[2], ' ', e, 5);
            if (strcmp(e[0], "frame") == 0) {
                expect(m == 4, "decode frame fields");
                size_t payload_len = hex(e[2], other, sizeof(other));
                expect_frame(result, seq, len, buffer, (uint32_t) strtoul(e[1], NULL, 10), other, payload_len);
                expect(ring_load(half, RING_FIELD_TAIL) == strtoul(e[3], NULL, 10), "tail after frame");
                expect(ring_load(half, RING_FIELD_DROPPED) == 0, "dropped after frame");
            } else if (strcmp(e[0], "crc") == 0) {
                expect(m == 2, "decode crc fields");
                expect(result == RING_READ_DROPPED, "crc: expected a drop");
                expect(ring_load(half, RING_FIELD_TAIL) == strtoul(e[1], NULL, 10), "tail after crc drop");
                expect(ring_load(half, RING_FIELD_DROPPED) == 1, "dropped after crc drop");
            } else {
                expect(strcmp(e[0], "resync") == 0, "unknown decode outcome");
                expect(result == RING_READ_DROPPED, "resync: expected a drop");
                expect(ring_load(half, RING_FIELD_TAIL) == stream, "tail after resync");
                expect(ring_load(half, RING_FIELD_DROPPED) == 1, "dropped after resync");
            }
            counted[4]++;
        } else if (strcmp(f[0], "wrap") == 0) {
            expect(n == 7, "wrap fields");
            size_t size = strtoull(f[1], NULL, 10);
            uint32_t start = (uint32_t) strtoul(f[2], NULL, 10);
            uint32_t want_seq = (uint32_t) strtoul(f[3], NULL, 10);
            size_t payload_len = hex(f[4], other, sizeof(other));
            uint32_t head_after = (uint32_t) strtoul(f[5], NULL, 10);
            struct RingHalf half = ring_half(region, size, 0);
            ring_initialize(half);
            ring_store(half, RING_FIELD_HEAD, start);
            ring_store(half, RING_FIELD_TAIL, start);
            struct RingWriter writer = ring_writer_open(half);
            writer.seq = want_seq;
            expect(ring_write(&writer, other, (uint32_t) payload_len) == RING_WRITE_OK, "wrap write");
            expect(ring_load(half, RING_FIELD_HEAD) == head_after, "head after wrap");
            char *places[16];
            int p = split(f[6], ' ', places, 16);
            for (int i = 0; i < p; i++) {
                char *equals = strchr(places[i], '=');
                expect(equals != NULL, "wrap place");
                *equals = '\0';
                size_t offset = strtoull(places[i], NULL, 10);
                size_t bytes = hex(equals + 1, scratch, sizeof(scratch));
                expect(memcmp(half.bytes + offset, scratch, bytes) == 0, "wrap bytes");
            }
            struct RingReader reader = { .half = half, .capacity = ring_load(half, RING_FIELD_CAPACITY) };
            enum RingReadResult result = ring_read(&reader, buffer, &seq, &len);
            expect_frame(result, seq, len, buffer, want_seq, other, payload_len);
            expect(ring_load(half, RING_FIELD_TAIL) == head_after, "tail after wrap");
            counted[5]++;
        } else {
            fail("unknown vector kind");
        }
    }
    fclose(in);

    /* Restart rules: a reopened reader discards what was in flight. */
    struct RingHalf half = ring_half(region, 4096, 0);
    ring_initialize(half);
    struct RingWriter writer = ring_writer_open(half);
    struct RingReader reader = ring_reader_open(half);
    uint32_t seq, len;
    expect(ring_write(&writer, (const uint8_t *) "one", 3) == RING_WRITE_OK, "restart write");
    reader = ring_reader_open(half);
    expect(ring_read(&reader, buffer, &seq, &len) == RING_READ_EMPTY, "reopened reader sees nothing");
    expect(ring_load(half, RING_FIELD_READER_EPOCH) == 2, "reader epoch bumped");
    expect(ring_write(&writer, (const uint8_t *) "two", 3) == RING_WRITE_OK, "write after restart");
    enum RingReadResult result = ring_read(&reader, buffer, &seq, &len);
    expect_frame(result, seq, len, buffer, 1, (const uint8_t *) "two", 3);
    /* Backpressure: a full ring refuses and overwrites nothing. */
    static uint8_t big[256];
    int written = 0;
    while (ring_write(&writer, big, sizeof(big)) == RING_WRITE_OK) {
        written++;
    }
    expect(written == 3 && ring_write(&writer, big, sizeof(big)) == RING_WRITE_FULL, "full ring");
    expect(ring_write(&writer, big, 257) == RING_WRITE_INVALID_LENGTH, "len above capacity/4");

    for (int i = 0; i < 6; i++) {
        expect(counted[i] > 0, "a vector kind is missing");
        printf("ring vectors: %s %d ok\n", kinds[i], counted[i]);
    }
    printf("ring vectors: restart and backpressure ok\n");
    return 0;
}
