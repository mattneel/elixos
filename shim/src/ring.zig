//! The inter-core ring (docs/PROTOCOL.md §11): one shared region holding two
//! single-producer, single-consumer rings of CRC-checked frames, one per
//! direction. Ring A carries big → little, ring B little → big.
//!
//! Each side owns its fields: the writer `writer epoch` and `head`, the
//! reader `reader epoch`, `tail` and `dropped`. The other side's field is
//! read with acquire and one's own is published with release, so the frame
//! bytes behind a `head` are visible before it, and a slot is reused only
//! after the reader has copied it out. No allocation, no syscalls: the
//! caller supplies the memory (an mmap of the region, or a test buffer).
const std = @import("std");
const builtin = @import("builtin");
const milestone = @import("milestone.zig");

comptime {
    // The fields are little-endian u32s accessed in place.
    if (builtin.cpu.arch.endian() != .little) @compileError("the ring layout is little-endian");
}

pub const magic: u32 = 0x52584C45; // "ELXR" in memory
pub const version: u32 = 1;
pub const header_size = 64;
pub const frame_header_size = 16;
pub const max_len: u32 = 65535;
/// `head - tail` must fit a u32 and positions must not jump when the
/// counters wrap at 2^32, so the capacity is a power of two up to 2^31.
pub const max_capacity: u32 = 1 << 31;

const Field = enum(u32) {
    magic = 0,
    version = 4,
    capacity = 8,
    writer_epoch = 12,
    head = 16,
    reader_epoch = 20,
    tail = 24,
    dropped = 28,
};

pub const Direction = enum { a, b };
pub const Side = enum {
    big,
    little,

    pub fn outgoing(side: Side) Direction {
        return if (side == .big) .a else .b;
    }
    pub fn incoming(side: Side) Direction {
        return if (side == .big) .b else .a;
    }
};

/// The capacity of each ring in a region of `size` bytes: the largest power
/// of two not above `size / 2 - 64`, capped at 2^31. Null unless `size` is a
/// positive multiple of 4096.
pub fn capacityFor(size: u64) ?u32 {
    if (size == 0 or size % 4096 != 0) return null;
    const usable = size / 2 - header_size;
    return @intCast(@min(std.math.floorPowerOfTwo(u64, usable), max_capacity));
}

/// The largest payload a ring of this capacity carries.
pub fn maxLen(capacity: u32) u32 {
    return @min(max_len, capacity / 4);
}

/// Stream bytes one frame occupies: its header and its padded payload.
pub fn occupancy(len: u32) u32 {
    return frame_header_size + std.mem.alignForward(u32, len, 8);
}

/// CRC-32 (IEEE) over `len`, `seq` (little-endian) and the payload.
pub fn checksum(len: u32, seq: u32, payload: []const u8) u32 {
    var prefix: [8]u8 = undefined;
    std.mem.writeInt(u32, prefix[0..4], len, .little);
    std.mem.writeInt(u32, prefix[4..8], seq, .little);
    var crc = std.hash.Crc32.init();
    crc.update(&prefix);
    crc.update(payload);
    return crc.final();
}

/// One ring: the header and data area at the start of one half of the region.
pub const Half = struct {
    bytes: []align(8) u8,

    pub fn of(region: []align(8) u8, direction: Direction) Half {
        const size = region.len / 2;
        const start: usize = if (direction == .a) 0 else size;
        return .{ .bytes = @alignCast(region[start..][0..size]) };
    }

    fn field(half: Half, which: Field) *u32 {
        return @ptrCast(@alignCast(half.bytes.ptr + @backingInt(which)));
    }

    pub fn load(half: Half, which: Field) u32 {
        return @atomicLoad(u32, half.field(which), .acquire);
    }

    fn store(half: Half, which: Field, value: u32) void {
        @atomicStore(u32, half.field(which), value, .release);
    }

    /// Magic, version and the capacity this region size implies.
    pub fn valid(half: Half) bool {
        const expected = capacityFor(@as(u64, half.bytes.len) * 2) orelse return false;
        return half.load(.magic) == magic and half.load(.version) == version and
            half.load(.capacity) == expected;
    }

    /// Zero header and data, then capacity, version and, last, magic.
    pub fn initialize(half: Half) void {
        half.store(.magic, 0);
        @memset(half.bytes[4..], 0);
        half.store(.capacity, capacityFor(@as(u64, half.bytes.len) * 2).?);
        half.store(.version, version);
        half.store(.magic, magic);
    }

    /// Initialises the ring unless it is already valid; true if it did.
    pub fn prepare(half: Half) bool {
        if (half.valid()) return false;
        half.initialize();
        return true;
    }

    fn data(half: Half, capacity: u32) []u8 {
        return half.bytes[header_size..][0..capacity];
    }

    /// Copies `bytes` into the stream at position `at`, wrapping.
    fn put(half: Half, capacity: u32, at: u32, bytes: []const u8) void {
        const area = half.data(capacity);
        const start = at & (capacity - 1);
        const first = @min(bytes.len, capacity - start);
        @memcpy(area[start..][0..first], bytes[0..first]);
        @memcpy(area[0 .. bytes.len - first], bytes[first..]);
    }

    /// Copies stream bytes from position `at` into `bytes`, wrapping.
    fn get(half: Half, capacity: u32, at: u32, bytes: []u8) void {
        const area = half.data(capacity);
        const start = at & (capacity - 1);
        const first = @min(bytes.len, capacity - start);
        @memcpy(bytes[0..first], area[start..][0..first]);
        @memcpy(bytes[first..], area[0 .. bytes.len - first]);
    }
};

pub const Writer = struct {
    half: Half,
    capacity: u32,
    /// The next frame's seq: counts this incarnation's frames from 0.
    seq: u32 = 0,

    pub const Outcome = enum { ok, full };

    /// A (re)starting writer on a valid ring: bumps the writer epoch and
    /// continues at `head`.
    pub fn open(half: Half) Writer {
        half.store(.writer_epoch, half.load(.writer_epoch) +% 1);
        return .{ .half = half, .capacity = half.load(.capacity) };
    }

    /// Publishes one frame, or reports the ring full and writes nothing.
    pub fn write(writer: *Writer, payload: []const u8) error{InvalidLength}!Outcome {
        if (payload.len == 0 or payload.len > maxLen(writer.capacity)) return error.InvalidLength;
        const len: u32 = @intCast(payload.len);
        const need = occupancy(len);
        const head = writer.half.load(.head);
        const used = head -% writer.half.load(.tail);
        // A tail beyond head (used > capacity) is never safe to write over.
        if (used > writer.capacity or writer.capacity - used < need) return .full;

        var header: [frame_header_size]u8 = @splat(0);
        std.mem.writeInt(u32, header[0..4], len, .little);
        std.mem.writeInt(u32, header[4..8], writer.seq, .little);
        std.mem.writeInt(u32, header[8..12], checksum(len, writer.seq, payload), .little);
        const zeros: [8]u8 = @splat(0);
        writer.half.put(writer.capacity, head, &header);
        writer.half.put(writer.capacity, head +% frame_header_size, payload);
        writer.half.put(writer.capacity, head +% frame_header_size +% len, zeros[0 .. need - frame_header_size - len]);
        writer.half.store(.head, head +% need);
        writer.seq +%= 1;
        return .ok;
    }
};

pub const Reader = struct {
    half: Half,
    capacity: u32,
    /// Frames this incarnation discarded (the header's `dropped` counts all).
    dropped: u32 = 0,

    pub const Frame = struct { seq: u32, payload: []u8 };
    pub const Result = union(enum) { frame: Frame, empty, dropped };

    /// A (re)starting reader on a valid ring: bumps the reader epoch and
    /// discards everything in flight (`tail = head`).
    pub fn open(half: Half) Reader {
        half.store(.reader_epoch, half.load(.reader_epoch) +% 1);
        half.store(.tail, half.load(.head));
        return .{ .half = half, .capacity = half.load(.capacity) };
    }

    /// Takes the next frame, copying its payload into `buffer`.
    pub fn read(reader: *Reader, buffer: *[max_len]u8) Result {
        const head = reader.half.load(.head);
        const tail = reader.half.load(.tail);
        const in_flight = head -% tail;
        if (in_flight == 0) return .empty;
        if (in_flight > reader.capacity or in_flight < frame_header_size) return reader.resync(head);

        var header: [frame_header_size]u8 = undefined;
        reader.half.get(reader.capacity, tail, &header);
        const len = std.mem.readInt(u32, header[0..4], .little);
        const seq = std.mem.readInt(u32, header[4..8], .little);
        const crc = std.mem.readInt(u32, header[8..12], .little);
        if (len == 0 or len > max_len or occupancy(len) > in_flight) return reader.resync(head);

        const payload = buffer[0..len];
        reader.half.get(reader.capacity, tail +% frame_header_size, payload);
        reader.half.store(.tail, tail +% occupancy(len));
        if (checksum(len, seq, payload) != crc) {
            reader.drop();
            return .dropped;
        }
        return .{ .frame = .{ .seq = seq, .payload = payload } };
    }

    /// The stream cannot be parsed: count one drop and skip to `head`.
    fn resync(reader: *Reader, head: u32) Result {
        reader.drop();
        reader.half.store(.tail, head);
        return .dropped;
    }

    fn drop(reader: *Reader) void {
        reader.half.store(.dropped, reader.half.load(.dropped) +% 1);
        reader.dropped +%= 1;
    }
};

// ---------------------------------------------------------------------------
// Tests

const testing = std.testing;

fn testRegion(comptime size: usize) type {
    return struct {
        bytes: [size]u8 align(8) = undefined,

        fn half(self: *@This(), direction: Direction) Half {
            return Half.of(&self.bytes, direction);
        }
    };
}

fn hex(out: []u8, text: []const u8) ![]u8 {
    return std.fmt.hexToBytes(out, text);
}

fn number(comptime T: type, text: []const u8) !T {
    return std.fmt.parseInt(T, text, 10);
}

/// Sets a ring's counters directly, as if `start` bytes had passed through.
fn rewind(half: Half, start: u32) void {
    half.store(.head, start);
    half.store(.tail, start);
}

fn expectFrame(result: Reader.Result, seq: u32, payload: []const u8) !void {
    switch (result) {
        .frame => |frame| {
            try testing.expectEqual(seq, frame.seq);
            try testing.expectEqualSlices(u8, payload, frame.payload);
        },
        else => return error.TestExpectedFrame,
    }
}

test "M31 ring: the shared golden vectors" {
    try milestone.require(31);
    const vectors = @embedFile("ring_vectors");
    const region = try testing.allocator.alignedAlloc(u8, .@"8", 1 << 20);
    defer testing.allocator.free(region);
    var buffer: [max_len]u8 = undefined;
    var counted: [7]usize = @splat(0);
    var lines = std.mem.splitScalar(u8, vectors, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const kind = fields.next().?;
        var scratch: [4096]u8 = undefined;
        var other: [4096]u8 = undefined;
        if (std.mem.eql(u8, kind, "crc")) {
            const bytes = try hex(&scratch, fields.next().?);
            var crc = std.hash.Crc32.init();
            crc.update(bytes);
            try testing.expectEqual(try std.fmt.parseInt(u32, fields.next().?, 16), crc.final());
            counted[0] += 1;
        } else if (std.mem.eql(u8, kind, "capacity")) {
            const size = try number(u64, fields.next().?);
            const expected = fields.next().?;
            if (std.mem.eql(u8, expected, "invalid")) {
                try testing.expectEqual(@as(?u32, null), capacityFor(size));
            } else {
                try testing.expectEqual(@as(?u32, try number(u32, expected)), capacityFor(size));
            }
            counted[1] += 1;
        } else if (std.mem.eql(u8, kind, "header")) {
            const size = try number(usize, fields.next().?);
            const expected = try hex(&scratch, fields.next().?);
            try testing.expectEqual(@as(usize, header_size), expected.len);
            @memset(region[0..size], 0xa5);
            for ([_]Direction{ .a, .b }) |direction| {
                const half = Half.of(@alignCast(region[0..size]), direction);
                try testing.expect(!half.valid());
                try testing.expect(half.prepare());
                try testing.expect(half.valid());
                try testing.expect(!half.prepare());
                try testing.expectEqualSlices(u8, expected, half.bytes[0..header_size]);
                for (half.bytes[header_size..]) |byte| try testing.expectEqual(@as(u8, 0), byte);
            }
            counted[2] += 1;
        } else if (std.mem.eql(u8, kind, "frame")) {
            const seq = try number(u32, fields.next().?);
            const payload = try hex(&scratch, fields.next().?);
            const expected = try hex(&other, fields.next().?);
            const half = Half.of(@alignCast(region[0..4096]), .a);
            half.initialize();
            var writer = Writer.open(half);
            writer.seq = seq;
            try testing.expectEqual(Writer.Outcome.ok, try writer.write(payload));
            try testing.expectEqual(@as(u32, @intCast(expected.len)), half.load(.head));
            try testing.expectEqualSlices(u8, expected, half.bytes[header_size..][0..expected.len]);
            var reader: Reader = .{ .half = half, .capacity = half.load(.capacity) };
            try expectFrame(reader.read(&buffer), seq, payload);
            counted[3] += 1;
        } else if (std.mem.eql(u8, kind, "decode")) {
            const stream = try hex(&scratch, fields.next().?);
            const half = Half.of(@alignCast(region[0..4096]), .b);
            half.initialize();
            @memcpy(half.bytes[header_size..][0..stream.len], stream);
            half.store(.head, @intCast(stream.len));
            var reader: Reader = .{ .half = half, .capacity = half.load(.capacity) };
            const result = reader.read(&buffer);
            var expected = std.mem.splitScalar(u8, fields.next().?, ' ');
            const outcome = expected.next().?;
            if (std.mem.eql(u8, outcome, "frame")) {
                const seq = try number(u32, expected.next().?);
                const payload = try hex(&other, expected.next().?);
                try expectFrame(result, seq, payload);
                try testing.expectEqual(try number(u32, expected.next().?), half.load(.tail));
                try testing.expectEqual(@as(u32, 0), half.load(.dropped));
            } else if (std.mem.eql(u8, outcome, "crc")) {
                try testing.expectEqual(Reader.Result.dropped, result);
                try testing.expectEqual(try number(u32, expected.next().?), half.load(.tail));
                try testing.expectEqual(@as(u32, 1), half.load(.dropped));
            } else {
                try testing.expectEqualStrings("resync", outcome);
                try testing.expectEqual(Reader.Result.dropped, result);
                try testing.expectEqual(@as(u32, @intCast(stream.len)), half.load(.tail));
                try testing.expectEqual(@as(u32, 1), half.load(.dropped));
            }
            counted[4] += 1;
        } else if (std.mem.eql(u8, kind, "wrap")) {
            const size = try number(usize, fields.next().?);
            const start = try number(u32, fields.next().?);
            const seq = try number(u32, fields.next().?);
            const payload = try hex(&other, fields.next().?);
            const head_after = try number(u32, fields.next().?);
            const half = Half.of(@alignCast(region[0..size]), .a);
            half.initialize();
            rewind(half, start);
            var writer = Writer.open(half);
            writer.seq = seq;
            try testing.expectEqual(Writer.Outcome.ok, try writer.write(payload));
            try testing.expectEqual(head_after, half.load(.head));
            var places = std.mem.splitScalar(u8, fields.next().?, ' ');
            while (places.next()) |place| {
                const equals = std.mem.indexOfScalar(u8, place, '=').?;
                const offset = try number(usize, place[0..equals]);
                const bytes = try hex(&scratch, place[equals + 1 ..]);
                try testing.expectEqualSlices(u8, bytes, half.bytes[offset..][0..bytes.len]);
            }
            var reader: Reader = .{ .half = half, .capacity = half.load(.capacity) };
            try expectFrame(reader.read(&buffer), seq, payload);
            try testing.expectEqual(head_after, half.load(.tail));
            counted[5] += 1;
        } else {
            return error.TestUnknownVector;
        }
    }
    for (counted[0..6]) |count| try testing.expect(count > 0);
}

test "M31 ring: frames wrap the data area and the 2^32 counters in order" {
    try milestone.require(31);
    var region: testRegion(4096) = .{};
    const half = region.half(.a);
    half.initialize();
    rewind(half, std.math.maxInt(u32) - 3000);
    var writer = Writer.open(half);
    var reader = Reader.open(half);
    var buffer: [max_len]u8 = undefined;
    var payload: [256]u8 = undefined;
    var written: u32 = 0;
    var received: u32 = 0;
    // Uneven sizes so frame boundaries land everywhere in the 1024-byte area.
    while (received < 500) {
        while (true) {
            const len = 1 + (written * 37) % 256;
            for (payload[0..len], 0..) |*byte, i| byte.* = @truncate(written +% @as(u32, @intCast(i)));
            if (try writer.write(payload[0..len]) == .full) break;
            written += 1;
        }
        // Drain only part of what is in flight, so writes and reads interleave.
        for (0..3) |_| {
            switch (reader.read(&buffer)) {
                .frame => |frame| {
                    try testing.expectEqual(received, frame.seq);
                    try testing.expectEqual(1 + (received * 37) % 256, @as(u32, @intCast(frame.payload.len)));
                    for (frame.payload, 0..) |byte, i| try testing.expectEqual(@as(u8, @truncate(received +% @as(u32, @intCast(i)))), byte);
                    received += 1;
                },
                .empty => break,
                .dropped => return error.TestUnexpectedDrop,
            }
        }
    }
    // The counters went past 2^32 on the way.
    try testing.expect(half.load(.head) < 1 << 20);
    try testing.expectEqual(@as(u32, 0), half.load(.dropped));
}

test "M31 ring: a full ring refuses frames and keeps every unread one" {
    try milestone.require(31);
    var region: testRegion(4096) = .{};
    const half = region.half(.b);
    half.initialize();
    var writer = Writer.open(half);
    var reader = Reader.open(half);
    var buffer: [max_len]u8 = undefined;
    const payload: [200]u8 = @splat(0x5a);
    // 1024 bytes hold four 216-byte frames and not a fifth.
    for (0..4) |_| try testing.expectEqual(Writer.Outcome.ok, try writer.write(&payload));
    const head = half.load(.head);
    try testing.expectEqual(@as(u32, 4 * 216), head);
    for (0..10) |_| try testing.expectEqual(Writer.Outcome.full, try writer.write(&payload));
    try testing.expectEqual(head, half.load(.head));
    try testing.expectEqual(@as(u32, 4), writer.seq);
    // A smaller frame still fits in what is left.
    try testing.expectEqual(Writer.Outcome.ok, try writer.write(payload[0..100]));
    try testing.expectEqual(Writer.Outcome.full, try writer.write(payload[0..100]));
    for (0..4) |seq| try expectFrame(reader.read(&buffer), @intCast(seq), &payload);
    try expectFrame(reader.read(&buffer), 4, payload[0..100]);
    try testing.expectEqual(Reader.Result.empty, reader.read(&buffer));
    // Room again once the reader is done.
    try testing.expectEqual(Writer.Outcome.ok, try writer.write(&payload));
    try expectFrame(reader.read(&buffer), 5, &payload);
    // Lengths outside 1..capacity/4 are the caller's error, not a full ring.
    try testing.expectError(error.InvalidLength, writer.write(&.{}));
    var big: [257]u8 = @splat(0);
    try testing.expectError(error.InvalidLength, writer.write(&big));
    // A tail beyond head is never written over.
    half.store(.tail, half.load(.head) +% 8);
    try testing.expectEqual(Writer.Outcome.full, try writer.write(payload[0..1]));
}

test "M31 ring: corrupt frames are dropped and counted, bad lengths resync" {
    try milestone.require(31);
    var region: testRegion(8192) = .{};
    const half = region.half(.a);
    half.initialize();
    var writer = Writer.open(half);
    var reader = Reader.open(half);
    var buffer: [max_len]u8 = undefined;
    _ = try writer.write("first");
    _ = try writer.write("second");
    _ = try writer.write("third");
    // Flip one payload byte of "second": stream 24 + 16 is its first byte.
    half.bytes[header_size + 24 + 16] ^= 0x01;
    try expectFrame(reader.read(&buffer), 0, "first");
    try testing.expectEqual(Reader.Result.dropped, reader.read(&buffer));
    try expectFrame(reader.read(&buffer), 2, "third");
    try testing.expectEqual(@as(u32, 1), half.load(.dropped));

    // A len beyond what is in flight: everything up to head goes, later frames arrive.
    const at = half.load(.head);
    _ = try writer.write("lost");
    _ = try writer.write("lost too");
    std.mem.writeInt(u32, half.bytes[header_size + at ..][0..4], 4000, .little);
    try testing.expectEqual(Reader.Result.dropped, reader.read(&buffer));
    try testing.expectEqual(half.load(.head), half.load(.tail));
    try testing.expectEqual(@as(u32, 2), half.load(.dropped));
    _ = try writer.write("after");
    try expectFrame(reader.read(&buffer), 5, "after");

    // A len of zero resyncs as well; so does a head beyond capacity.
    const zero_at = half.load(.head);
    _ = try writer.write("zeroed");
    std.mem.writeInt(u32, half.bytes[header_size + zero_at ..][0..4], 0, .little);
    try testing.expectEqual(Reader.Result.dropped, reader.read(&buffer));
    half.store(.head, half.load(.tail) +% half.load(.capacity) +% 8);
    try testing.expectEqual(Reader.Result.dropped, reader.read(&buffer));
    try testing.expectEqual(half.load(.head), half.load(.tail));
    try testing.expectEqual(@as(u32, 4), half.load(.dropped));
    try testing.expectEqual(@as(u32, 4), reader.dropped);
    try testing.expectEqual(Reader.Result.empty, reader.read(&buffer));
}

test "M31 ring: a restarted writer continues at head and loses nothing" {
    try milestone.require(31);
    var region: testRegion(4096) = .{};
    const half = region.half(.b);
    half.initialize();
    var reader = Reader.open(half);
    var buffer: [max_len]u8 = undefined;
    var writer = Writer.open(half);
    _ = try writer.write("before 0");
    _ = try writer.write("before 1");
    try expectFrame(reader.read(&buffer), 0, "before 0");
    // The writer restarts with one frame still unread.
    var restarted = Writer.open(half);
    try testing.expectEqual(@as(u32, 2), half.load(.writer_epoch));
    _ = try restarted.write("after 0");
    _ = try restarted.write("after 1");
    try expectFrame(reader.read(&buffer), 1, "before 1");
    try expectFrame(reader.read(&buffer), 0, "after 0");
    try expectFrame(reader.read(&buffer), 1, "after 1");
    try testing.expectEqual(Reader.Result.empty, reader.read(&buffer));
    try testing.expectEqual(@as(u32, 0), half.load(.dropped));
}

test "M31 ring: a restarted reader skips its predecessor's frames and loses no later one" {
    try milestone.require(31);
    var region: testRegion(4096) = .{};
    const half = region.half(.a);
    half.initialize();
    var writer = Writer.open(half);
    var reader = Reader.open(half);
    var buffer: [max_len]u8 = undefined;
    _ = try writer.write("old 0");
    _ = try writer.write("old 1");
    try expectFrame(reader.read(&buffer), 0, "old 0");
    // The reader restarts: "old 1" was meant for its previous incarnation.
    var restarted = Reader.open(half);
    try testing.expectEqual(@as(u32, 2), half.load(.reader_epoch));
    try testing.expectEqual(half.load(.head), half.load(.tail));
    try testing.expectEqual(Reader.Result.empty, restarted.read(&buffer));
    _ = try writer.write("new 2");
    _ = try writer.write("new 3");
    try expectFrame(restarted.read(&buffer), 2, "new 2");
    try expectFrame(restarted.read(&buffer), 3, "new 3");
    try testing.expectEqual(@as(u32, 0), half.load(.dropped));
}

test "M31 ring: the big core reinitialises only an invalid ring" {
    try milestone.require(31);
    var region: testRegion(8192) = .{};
    @memset(&region.bytes, 0xff);
    const a = region.half(.a);
    const b = region.half(.b);
    try testing.expect(a.prepare());
    try testing.expect(b.prepare());
    try testing.expectEqual(@as(u32, 2048), a.load(.capacity));
    var writer = Writer.open(a);
    _ = try writer.write("kept");
    // A valid ring is kept as it is, frames and all.
    try testing.expect(!a.prepare());
    try testing.expectEqual(@as(u32, 24), a.load(.head));
    // Wrong version, capacity or magic: start over.
    for ([_]Field{ .version, .capacity, .magic }) |which| {
        a.store(which, a.load(which) +% 1);
        try testing.expect(!a.valid());
        try testing.expect(a.prepare());
        try testing.expectEqual(@as(u32, 0), a.load(.head));
        try testing.expectEqual(@as(u32, 0), a.load(.writer_epoch));
    }
    // A half of the wrong size for its capacity field is invalid too.
    const small = Half.of(region.bytes[0..4096], .a);
    try testing.expect(!small.valid());
}
