/*
 * The inter-core ring, little side (docs/PROTOCOL.md §11): the C counterpart
 * of shim/src/ring.zig, checked against the same spec/ring.vectors by
 * coproc/test/ring_vectors_test.c. Pure C over caller-supplied memory, so the
 * host builds and tests it as is.
 */
#ifndef COPROC_RING_H
#define COPROC_RING_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define RING_MAGIC 0x52584C45u /* "ELXR" in memory */
#define RING_VERSION 1u
#define RING_HEADER_SIZE 64u
#define RING_FRAME_HEADER_SIZE 16u
#define RING_MAX_LEN 65535u

enum RingField
{
    RING_FIELD_MAGIC = 0,
    RING_FIELD_VERSION = 4,
    RING_FIELD_CAPACITY = 8,
    RING_FIELD_WRITER_EPOCH = 12,
    RING_FIELD_HEAD = 16,
    RING_FIELD_READER_EPOCH = 20,
    RING_FIELD_TAIL = 24,
    RING_FIELD_DROPPED = 28,
};

/* One ring: a half of the region (A at 0, B at S/2). */
struct RingHalf
{
    uint8_t *bytes;
    size_t size;
};

struct RingWriter
{
    struct RingHalf half;
    uint32_t capacity;
    uint32_t seq;
};

struct RingReader
{
    struct RingHalf half;
    uint32_t capacity;
    uint32_t dropped;
};

enum RingWriteResult
{
    RING_WRITE_OK,
    RING_WRITE_FULL,
    RING_WRITE_INVALID_LENGTH,
};

enum RingReadResult
{
    RING_READ_FRAME,
    RING_READ_EMPTY,
    RING_READ_DROPPED,
};

uint32_t ring_crc32(uint32_t crc, const uint8_t *bytes, size_t len);
uint32_t ring_checksum(uint32_t len, uint32_t seq, const uint8_t *payload);

/* The ring capacity for a region of `size` bytes, 0 if invalid. */
uint32_t ring_capacity_for(uint64_t size);
uint32_t ring_max_len(uint32_t capacity);
uint32_t ring_occupancy(uint32_t len);

/* Half A (big writes) or B (little writes) of a region. */
struct RingHalf ring_half(uint8_t *region, size_t size, bool b);

uint32_t ring_load(struct RingHalf half, enum RingField field);
void ring_store(struct RingHalf half, enum RingField field, uint32_t value);

/* Magic, version and the capacity the region size implies. */
bool ring_valid(struct RingHalf half);

/* The big core's initialisation (the little side never calls it; tests do). */
void ring_initialize(struct RingHalf half);

/* A (re)starting writer: bumps the writer epoch, continues at head. */
struct RingWriter ring_writer_open(struct RingHalf half);
enum RingWriteResult ring_write(struct RingWriter *writer, const uint8_t *payload, uint32_t len);

/* A (re)starting reader: bumps the reader epoch, tail = head. */
struct RingReader ring_reader_open(struct RingHalf half);

/*
 * Takes the next frame, copying its payload into `buffer` (RING_MAX_LEN
 * bytes); on RING_READ_FRAME sets *seq and *len.
 */
enum RingReadResult ring_read(struct RingReader *reader, uint8_t *buffer, uint32_t *seq, uint32_t *len);

#endif
