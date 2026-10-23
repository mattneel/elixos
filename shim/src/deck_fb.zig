//! elixos-deck-fb (docs/PROTOCOL.md §12, M33): the BEAM's hands on the deck
//! framebuffer. `Elixos.Deck` spawns it as a Port with the region's path
//! (`ELIXOS_DECK`, §3) and sends packet-4 commands: fill, blit, move and
//! commit. It maps the region (a file, a PCI resource file or a UIO device),
//! initialises the header when its magic or geometry is wrong, and commits
//! as §12 says: pixels, damage, write fence, seq + 1.
//!
//! Static, libc-free, single-threaded. Its only buffer is one packet, sized
//! for a full-panel blit; the loop allocates nothing.
const std = @import("std");
const linux = std.os.linux;
const deck = @import("deck.zig");
const milestone = @import("milestone.zig");

const prefix = "elixos-deck-fb: ";

pub const Command = union(enum) {
    /// `F x y w h color`: fill a rectangle with one RGB565 colour.
    fill: struct { rect: deck.Rect, color: u16 },
    /// `B x y w h pixels`: copy w*h RGB565 pixels, row by row.
    blit: struct { rect: deck.Rect, pixels: []const u8 },
    /// `M x y w h dx dy`: move a rectangle; source and target may overlap.
    move: struct { rect: deck.Rect, x: u32, y: u32 },
    /// `C x y w h`: commit with this damage rectangle.
    commit: deck.Rect,
};

/// The largest packet: a full-panel blit.
pub const max_packet = 9 + @as(usize, deck.stride) * deck.height;

fn u16At(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}

fn rectAt(bytes: []const u8) deck.Rect {
    return .{ .x = u16At(bytes, 1), .y = u16At(bytes, 3), .w = u16At(bytes, 5), .h = u16At(bytes, 7) };
}

/// Null for anything malformed: an unknown opcode, a wrong length, a
/// rectangle (or a move's target) outside the panel.
pub fn parse(packet: []const u8) ?Command {
    if (packet.len < 9) return null;
    const rect = rectAt(packet);
    if (!deck.inside(rect)) return null;
    switch (packet[0]) {
        'F' => {
            if (packet.len != 11) return null;
            return .{ .fill = .{ .rect = rect, .color = @intCast(u16At(packet, 9)) } };
        },
        'B' => {
            if (packet.len - 9 != @as(usize, rect.w) * rect.h * 2) return null;
            return .{ .blit = .{ .rect = rect, .pixels = packet[9..] } };
        },
        'M' => {
            if (packet.len != 13) return null;
            const x = u16At(packet, 9);
            const y = u16At(packet, 11);
            if (!deck.inside(.{ .x = x, .y = y, .w = rect.w, .h = rect.h })) return null;
            return .{ .move = .{ .rect = rect, .x = x, .y = y } };
        },
        'C' => {
            if (packet.len != 9) return null;
            return .{ .commit = rect };
        },
        else => return null,
    }
}

fn row(region: []align(4096) u8, x: u32, y: u32, w: u32) []u8 {
    const start = deck.header_size + @as(usize, y) * deck.stride + @as(usize, x) * 2;
    return region[start..][0 .. @as(usize, w) * 2];
}

/// Carries out one command. Returns the new seq for a commit.
pub fn execute(region: []align(4096) u8, command: Command) ?u32 {
    switch (command) {
        .fill => |fill| {
            var pair: [2]u8 = undefined;
            std.mem.writeInt(u16, &pair, fill.color, .little);
            for (0..fill.rect.h) |dy| {
                const target = row(region, fill.rect.x, fill.rect.y + @as(u32, @intCast(dy)), fill.rect.w);
                var i: usize = 0;
                while (i < target.len) : (i += 2) @memcpy(target[i..][0..2], &pair);
            }
        },
        .blit => |blit| {
            const span = @as(usize, blit.rect.w) * 2;
            for (0..blit.rect.h) |dy| {
                @memcpy(row(region, blit.rect.x, blit.rect.y + @as(u32, @intCast(dy)), blit.rect.w), blit.pixels[dy * span ..][0..span]);
            }
        },
        .move => |move| {
            const r = move.rect;
            // Rows in the order that never reads a row already overwritten.
            const down = move.y > r.y;
            for (0..r.h) |i| {
                const dy: u32 = @intCast(if (down) r.h - 1 - i else i);
                const source = row(region, r.x, r.y + dy, r.w);
                const target = row(region, move.x, move.y + dy, r.w);
                if (@intFromPtr(target.ptr) <= @intFromPtr(source.ptr))
                    std.mem.copyForwards(u8, target, source)
                else
                    std.mem.copyBackwards(u8, target, source);
            }
        },
        .commit => |damage| return deck.commit(region, damage),
    }
    return null;
}

// ---------------------------------------------------------------------------
// The process

fn say(fd: linux.fd_t, bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = linux.write(fd, bytes.ptr + written, bytes.len - written);
        switch (linux.errno(rc)) {
            .SUCCESS => written += rc,
            .INTR => {},
            else => return,
        }
    }
}

fn fail(what: []const u8, err: anyerror) noreturn {
    var buffer: [256]u8 = undefined;
    say(2, std.fmt.bufPrint(&buffer, prefix ++ "{s} failed ({t})\n", .{ what, err }) catch prefix ++ "failed\n");
    linux.exit_group(1);
}

fn checked(raw: usize) error{System}!usize {
    return if (linux.errno(raw) == .SUCCESS) raw else error.System;
}

/// Maps exactly the protocol's region. A regular file (or a sysfs PCI
/// resource file) shorter than that would fault on access (SIGBUS); a
/// character device (UIO) reports no size, and its mmap refuses a length
/// beyond its map.
fn mapRegion(path: [*:0]const u8) []align(4096) u8 {
    const fd: linux.fd_t = @intCast(checked(linux.openat(linux.AT.FDCWD, path, .{
        .ACCMODE = .RDWR,
        .CLOEXEC = true,
    }, 0)) catch |err| fail("opening the region", err));
    defer _ = linux.close(fd);
    var stat: linux.Statx = undefined;
    _ = checked(linux.statx(fd, "", linux.AT.EMPTY_PATH, .{ .TYPE = true, .SIZE = true }, &stat)) catch |err| fail("statx on the region", err);
    if (linux.S.ISREG(stat.mode) and stat.size < deck.region_size) fail("checking the region size", error.RegionTooSmall);
    const address = checked(linux.mmap(null, deck.region_size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0)) catch |err| fail("mapping the region", err);
    return @as([*]align(4096) u8, @ptrFromInt(address))[0..deck.region_size];
}

fn reply(text: []const u8) void {
    var buffer: [64]u8 = undefined;
    std.mem.writeInt(u32, buffer[0..4], @intCast(text.len), .big);
    @memcpy(buffer[4..][0..text.len], text);
    say(1, buffer[0 .. 4 + text.len]);
}

/// Reads exactly `target.len` bytes; false at end of input before any byte.
fn readExactly(target: []u8) bool {
    var used: usize = 0;
    while (used < target.len) {
        const rc = linux.read(0, target.ptr + used, target.len - used);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) {
                    if (used == 0) return false;
                    fail("reading a packet", error.Truncated);
                }
                used += rc;
            },
            .INTR => {},
            else => fail("reading stdin", error.System),
        }
    }
    return true;
}

var incoming: [max_packet]u8 = undefined;

fn run(path: [*:0]const u8) noreturn {
    const region = mapRegion(path);
    _ = deck.prepare(region);
    var line: [64]u8 = undefined;
    reply(std.fmt.bufPrint(&line, "READY {d} {d} {d}", .{ deck.width, deck.height, deck.get(region, .seq) }) catch unreachable);
    while (true) {
        var header: [4]u8 = undefined;
        // The BEAM closing the Port is a shutdown too.
        if (!readExactly(&header)) linux.exit_group(0);
        const length = std.mem.readInt(u32, &header, .big);
        if (length == 0) linux.exit_group(0);
        if (length > incoming.len) fail("reading a packet", error.TooLong);
        if (!readExactly(incoming[0..length])) fail("reading a packet", error.Truncated);
        const command = parse(incoming[0..length]) orelse fail("parsing a packet", error.Protocol);
        if (execute(region, command)) |seq| {
            reply(std.fmt.bufPrint(&line, "COMMITTED {d}", .{seq}) catch unreachable);
        }
    }
}

pub fn main(init: std.process.Init.Minimal) noreturn {
    var it = std.process.Args.Iterator.init(init.args);
    _ = it.next();
    const path = it.next() orelse {
        say(2, "usage: elixos-deck-fb <region>\n");
        linux.exit_group(2);
    };
    if (it.next() != null) {
        say(2, "usage: elixos-deck-fb <region>\n");
        linux.exit_group(2);
    }
    run(path.ptr);
}

const Test = struct {
    var region: [deck.region_size]u8 align(4096) = undefined;

    fn pixel(x: u32, y: u32) u16 {
        return std.mem.readInt(u16, row(&region, x, y, 1)[0..2], .little);
    }

    fn cmd(comptime op: u8, values: []const u16, tail: []const u8, buffer: []u8) []const u8 {
        buffer[0] = op;
        for (values, 0..) |value, i| std.mem.writeInt(u16, buffer[1 + i * 2 ..][0..2], value, .little);
        const end = 1 + values.len * 2;
        @memcpy(buffer[end..][0..tail.len], tail);
        return buffer[0 .. end + tail.len];
    }
};

test "M33 elixos-deck-fb: commands parse only inside the panel" {
    try milestone.require(33);
    var buffer: [64]u8 = undefined;
    try std.testing.expect(parse(Test.cmd('F', &.{ 0, 0, 568, 1232, 0xF800 }, "", &buffer)) != null);
    try std.testing.expect(parse(Test.cmd('F', &.{ 1, 0, 568, 1, 0 }, "", &buffer)) == null);
    try std.testing.expect(parse(Test.cmd('F', &.{ 0, 0, 0, 1, 0 }, "", &buffer)) == null);
    try std.testing.expect(parse(Test.cmd('F', &.{ 0, 0, 1, 1 }, "", &buffer)) == null);
    try std.testing.expect(parse(Test.cmd('B', &.{ 2, 3, 2, 1 }, "abcd", &buffer)) != null);
    try std.testing.expect(parse(Test.cmd('B', &.{ 2, 3, 2, 1 }, "abc", &buffer)) == null);
    try std.testing.expect(parse(Test.cmd('M', &.{ 0, 24, 568, 100, 0, 0 }, "", &buffer)) != null);
    try std.testing.expect(parse(Test.cmd('M', &.{ 0, 0, 568, 100, 0, 1200 }, "", &buffer)) == null);
    try std.testing.expect(parse(Test.cmd('C', &.{ 0, 0, 568, 1232 }, "", &buffer)) != null);
    try std.testing.expect(parse(Test.cmd('C', &.{ 0, 0, 568, 1233 }, "", &buffer)) == null);
    try std.testing.expect(parse(Test.cmd('X', &.{ 0, 0, 1, 1 }, "", &buffer)) == null);
    try std.testing.expect(parse("") == null);
}

test "M33 elixos-deck-fb: fill, blit, move and commit" {
    try milestone.require(33);
    @memset(&Test.region, 0);
    _ = deck.prepare(&Test.region);
    var buffer: [64]u8 = undefined;
    _ = execute(&Test.region, parse(Test.cmd('F', &.{ 10, 20, 3, 2, 0xF800 }, "", &buffer)).?);
    try std.testing.expectEqual(@as(u16, 0xF800), Test.pixel(10, 20));
    try std.testing.expectEqual(@as(u16, 0xF800), Test.pixel(12, 21));
    try std.testing.expectEqual(@as(u16, 0), Test.pixel(13, 21));
    try std.testing.expectEqual(@as(u16, 0), Test.pixel(10, 22));
    // Pixel (x, y) lives at 4096 + y * stride + 2x, little-endian.
    try std.testing.expectEqual(@as(u8, 0x00), Test.region[4096 + 20 * 1136 + 20]);
    try std.testing.expectEqual(@as(u8, 0xF8), Test.region[4096 + 20 * 1136 + 21]);

    _ = execute(&Test.region, parse(Test.cmd('B', &.{ 0, 0, 2, 1 }, &.{ 0x34, 0x12, 0x78, 0x56 }, &buffer)).?);
    try std.testing.expectEqual(@as(u16, 0x1234), Test.pixel(0, 0));
    try std.testing.expectEqual(@as(u16, 0x5678), Test.pixel(1, 0));

    // Scroll up by 20 rows (overlapping) and down by 5 (overlapping).
    _ = execute(&Test.region, parse(Test.cmd('M', &.{ 0, 20, 568, 100, 0, 0 }, "", &buffer)).?);
    try std.testing.expectEqual(@as(u16, 0xF800), Test.pixel(10, 0));
    try std.testing.expectEqual(@as(u16, 0xF800), Test.pixel(12, 1));
    try std.testing.expectEqual(@as(u16, 0), Test.pixel(10, 2));
    _ = execute(&Test.region, parse(Test.cmd('M', &.{ 0, 0, 568, 10, 0, 5 }, "", &buffer)).?);
    try std.testing.expectEqual(@as(u16, 0xF800), Test.pixel(10, 5));
    try std.testing.expectEqual(@as(u16, 0xF800), Test.pixel(11, 6));
    try std.testing.expectEqual(@as(u16, 0), Test.pixel(10, 7));

    try std.testing.expectEqual(@as(?u32, 1), execute(&Test.region, parse(Test.cmd('C', &.{ 10, 20, 3, 2 }, "", &buffer)).?));
    try std.testing.expectEqual(@as(u32, 10), deck.get(&Test.region, .damage_x));
    try std.testing.expectEqual(@as(u32, 2), deck.get(&Test.region, .damage_h));
    try std.testing.expectEqual(@as(?u32, 2), execute(&Test.region, parse(Test.cmd('C', &.{ 0, 0, 568, 1232 }, "", &buffer)).?));
}
