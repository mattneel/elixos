/*
 * The inter-core ring, little side (docs/PROTOCOL.md §11). Mirrors
 * shim/src/ring.zig: each side owns its fields; the other side's are read
 * with acquire, one's own published with release, so a frame's bytes are
 * visible before the head that covers them and a slot is reused only after
 * the reader advanced the tail past it.
 */
#include <string.h>

#include "ring.h"

uint32_t ring_crc32(uint32_t crc, const uint8_t *bytes, size_t len)
{
    crc = ~crc;
    for (size_t i = 0; i < len; i++) {
        crc ^= bytes[i];
        for (int bit = 0; bit < 8; bit++) {
            crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
        }
    }
    return ~crc;
}

static void put_u32(uint8_t *out, uint32_t value)
{
    out[0] = (uint8_t) value;
    out[1] = (uint8_t) (value >> 8);
    out[2] = (uint8_t) (value >> 16);
    out[3] = (uint8_t) (value >> 24);
}

static uint32_t get_u32(const uint8_t *in)
{
    return (uint32_t) in[0] | ((uint32_t) in[1] << 8) | ((uint32_t) in[2] << 16) | ((uint32_t) in[3] << 24);
}

uint32_t ring_checksum(uint32_t len, uint32_t seq, const uint8_t *payload)
{
    uint8_t prefix[8];
    put_u32(prefix, len);
    put_u32(prefix + 4, seq);
    return ring_crc32(ring_crc32(0, prefix, sizeof(prefix)), payload, len);
}

uint32_t ring_capacity_for(uint64_t size)
{
    if (size == 0 || size % 4096 != 0) {
        return 0;
    }
    uint64_t usable = size / 2 - RING_HEADER_SIZE;
    uint64_t capacity = 1;
    while (capacity * 2 <= usable && capacity < (1ull << 31)) {
        capacity *= 2;
    }
    return (uint32_t) capacity;
}

uint32_t ring_max_len(uint32_t capacity)
{
    return capacity / 4 < RING_MAX_LEN ? capacity / 4 : RING_MAX_LEN;
}

uint32_t ring_occupancy(uint32_t len)
{
    return RING_FRAME_HEADER_SIZE + ((len + 7u) & ~7u);
}

struct RingHalf ring_half(uint8_t *region, size_t size, bool b)
{
    struct RingHalf half = { .bytes = region + (b ? size / 2 : 0), .size = size / 2 };
    return half;
}

uint32_t ring_load(struct RingHalf half, enum RingField field)
{
    return __atomic_load_n((uint32_t *) (half.bytes + field), __ATOMIC_ACQUIRE);
}

void ring_store(struct RingHalf half, enum RingField field, uint32_t value)
{
    __atomic_store_n((uint32_t *) (half.bytes + field), value, __ATOMIC_RELEASE);
}

bool ring_valid(struct RingHalf half)
{
    uint32_t expected = ring_capacity_for((uint64_t) half.size * 2);
    return expected != 0 && ring_load(half, RING_FIELD_MAGIC) == RING_MAGIC
        && ring_load(half, RING_FIELD_VERSION) == RING_VERSION
        && ring_load(half, RING_FIELD_CAPACITY) == expected;
}

void ring_initialize(struct RingHalf half)
{
    ring_store(half, RING_FIELD_MAGIC, 0);
    memset(half.bytes + 4, 0, half.size - 4);
    ring_store(half, RING_FIELD_CAPACITY, ring_capacity_for((uint64_t) half.size * 2));
    ring_store(half, RING_FIELD_VERSION, RING_VERSION);
    ring_store(half, RING_FIELD_MAGIC, RING_MAGIC);
}

/* Stream bytes at position `at`, wrapping around the data area. */
static void put(struct RingHalf half, uint32_t capacity, uint32_t at, const uint8_t *bytes, uint32_t len)
{
    uint8_t *area = half.bytes + RING_HEADER_SIZE;
    uint32_t start = at & (capacity - 1);
    uint32_t first = len < capacity - start ? len : capacity - start;
    memcpy(area + start, bytes, first);
    memcpy(area, bytes + first, len - first);
}

static void get(struct RingHalf half, uint32_t capacity, uint32_t at, uint8_t *bytes, uint32_t len)
{
    const uint8_t *area = half.bytes + RING_HEADER_SIZE;
    uint32_t start = at & (capacity - 1);
    uint32_t first = len < capacity - start ? len : capacity - start;
    memcpy(bytes, area + start, first);
    memcpy(bytes + first, area, len - first);
}

struct RingWriter ring_writer_open(struct RingHalf half)
{
    ring_store(half, RING_FIELD_WRITER_EPOCH, ring_load(half, RING_FIELD_WRITER_EPOCH) + 1);
    struct RingWriter writer = { .half = half, .capacity = ring_load(half, RING_FIELD_CAPACITY), .seq = 0 };
    return writer;
}

enum RingWriteResult ring_write(struct RingWriter *writer, const uint8_t *payload, uint32_t len)
{
    if (len == 0 || len > ring_max_len(writer->capacity)) {
        return RING_WRITE_INVALID_LENGTH;
    }
    uint32_t need = ring_occupancy(len);
    uint32_t head = ring_load(writer->half, RING_FIELD_HEAD);
    uint32_t used = head - ring_load(writer->half, RING_FIELD_TAIL);
    // A tail beyond head (used > capacity) is never safe to write over.
    if (used > writer->capacity || writer->capacity - used < need) {
        return RING_WRITE_FULL;
    }

    uint8_t header[RING_FRAME_HEADER_SIZE] = { 0 };
    static const uint8_t zeros[8] = { 0 };
    put_u32(header, len);
    put_u32(header + 4, writer->seq);
    put_u32(header + 8, ring_checksum(len, writer->seq, payload));
    put(writer->half, writer->capacity, head, header, sizeof(header));
    put(writer->half, writer->capacity, head + RING_FRAME_HEADER_SIZE, payload, len);
    put(writer->half, writer->capacity, head + RING_FRAME_HEADER_SIZE + len, zeros, need - RING_FRAME_HEADER_SIZE - len);
    ring_store(writer->half, RING_FIELD_HEAD, head + need);
    writer->seq++;
    return RING_WRITE_OK;
}

struct RingReader ring_reader_open(struct RingHalf half)
{
    ring_store(half, RING_FIELD_READER_EPOCH, ring_load(half, RING_FIELD_READER_EPOCH) + 1);
    ring_store(half, RING_FIELD_TAIL, ring_load(half, RING_FIELD_HEAD));
    struct RingReader reader = { .half = half, .capacity = ring_load(half, RING_FIELD_CAPACITY), .dropped = 0 };
    return reader;
}

static void drop(struct RingReader *reader)
{
    ring_store(reader->half, RING_FIELD_DROPPED, ring_load(reader->half, RING_FIELD_DROPPED) + 1);
    reader->dropped++;
}

/* The stream cannot be parsed: count one drop and skip to head. */
static enum RingReadResult resync(struct RingReader *reader, uint32_t head)
{
    drop(reader);
    ring_store(reader->half, RING_FIELD_TAIL, head);
    return RING_READ_DROPPED;
}

enum RingReadResult ring_read(struct RingReader *reader, uint8_t *buffer, uint32_t *seq, uint32_t *len)
{
    uint32_t head = ring_load(reader->half, RING_FIELD_HEAD);
    uint32_t tail = ring_load(reader->half, RING_FIELD_TAIL);
    uint32_t in_flight = head - tail;
    if (in_flight == 0) {
        return RING_READ_EMPTY;
    }
    if (in_flight > reader->capacity || in_flight < RING_FRAME_HEADER_SIZE) {
        return resync(reader, head);
    }

    uint8_t header[RING_FRAME_HEADER_SIZE];
    get(reader->half, reader->capacity, tail, header, sizeof(header));
    uint32_t frame_len = get_u32(header);
    uint32_t frame_seq = get_u32(header + 4);
    uint32_t crc = get_u32(header + 8);
    if (frame_len == 0 || frame_len > RING_MAX_LEN || ring_occupancy(frame_len) > in_flight) {
        return resync(reader, head);
    }

    get(reader->half, reader->capacity, tail + RING_FRAME_HEADER_SIZE, buffer, frame_len);
    ring_store(reader->half, RING_FIELD_TAIL, tail + ring_occupancy(frame_len));
    if (ring_checksum(frame_len, frame_seq, buffer) != crc) {
        drop(reader);
        return RING_READ_DROPPED;
    }
    *seq = frame_seq;
    *len = frame_len;
    return RING_READ_FRAME;
}
