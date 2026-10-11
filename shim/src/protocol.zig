//! Shim control protocol (docs/PROTOCOL.md §2). Pure code: no syscalls here.
//!
//! The BEAM writes one ASCII line per message to the control pipe the shim
//! hands it (ELIXOS_CTL_FD). The shim reads, parses and applies them through
//! recovery.applyMessage. The Elixir side (Elixos.Shim.Protocol) must agree
//! byte for byte, which is why both suites run spec/protocol.vectors.
const std = @import("std");
const testing = std.testing;
const milestone = @import("milestone.zig");
const decimal = @import("decimal.zig");
const helpers = @import("helpers.zig");

/// Longest accepted line, excluding the trailing '\n'. Checked before anything else.
pub const max_line_len = 64;

/// Owned request name: parsing never retains a pointer into the pipe buffer.
pub const HelperName = struct {
    name: [32]u8 = @splat(0),
    name_len: usize = 0,
};

pub const Message = union(enum) {
    /// "HB": the BEAM is alive. Missing heartbeats get it killed (PROTOCOL.md §3).
    heartbeat,
    /// "COMMIT <gen>": <gen> booted and is healthy; it becomes last_good.
    commit: u32,
    /// "NEXT <gen>": boot <gen> next time, provisionally.
    next: u32,
    /// "REBOOT" / "POWEROFF" / "HALT": carry this out when the BEAM exits.
    reboot,
    poweroff,
    halt,
    /// "HELPER <name>": launch only the image-declared helper, with fixed argv.
    helper: HelperName,
};

pub const ParseError = error{ Invalid, TooLong };

/// Parses one line, given without its trailing '\n'.
/// Generation numbers use decimal.parseU32 (one grammar everywhere).
pub fn parse(line: []const u8) ParseError!Message {
    // The length limit is checked before anything else (PROTOCOL.md §2).
    if (line.len > max_line_len) return error.TooLong;
    if (std.mem.eql(u8, line, "HB")) return .heartbeat;
    if (std.mem.eql(u8, line, "REBOOT")) return .reboot;
    if (std.mem.eql(u8, line, "POWEROFF")) return .poweroff;
    if (std.mem.eql(u8, line, "HALT")) return .halt;
    if (std.mem.startsWith(u8, line, "COMMIT ")) {
        const generation = decimal.parseU32(line["COMMIT ".len..]) orelse return error.Invalid;
        return .{ .commit = generation };
    }
    if (std.mem.startsWith(u8, line, "NEXT ")) {
        const generation = decimal.parseU32(line["NEXT ".len..]) orelse return error.Invalid;
        return .{ .next = generation };
    }
    if (std.mem.startsWith(u8, line, "HELPER ")) {
        const name = line["HELPER ".len..];
        if (!helpers.validName(name)) return error.Invalid;
        var owned: HelperName = .{ .name_len = name.len };
        @memcpy(owned.name[0..name.len], name);
        return .{ .helper = owned };
    }
    return error.Invalid;
}

/// Writes `msg` into `buf` as a wire line including the trailing '\n'.
pub fn encode(msg: Message, buf: []u8) error{NoSpaceLeft}![]u8 {
    return switch (msg) {
        .heartbeat => std.fmt.bufPrint(buf, "HB\n", .{}),
        .commit => |generation| std.fmt.bufPrint(buf, "COMMIT {d}\n", .{generation}),
        .next => |generation| std.fmt.bufPrint(buf, "NEXT {d}\n", .{generation}),
        .reboot => std.fmt.bufPrint(buf, "REBOOT\n", .{}),
        .poweroff => std.fmt.bufPrint(buf, "POWEROFF\n", .{}),
        .halt => std.fmt.bufPrint(buf, "HALT\n", .{}),
        .helper => |name| std.fmt.bufPrint(buf, "HELPER {s}\n", .{name.name[0..name.name_len]}),
    };
}

// ---------------------------------------------------------------------------
// Tests. The golden vectors are the contract; the rest pins down edge cases.

const vectors = @embedFile("protocol_vectors");

const Expected = union(enum) { ok: Message, err: ParseError };

fn unescape(src: []const u8, out: []u8) ![]u8 {
    var i: usize = 0;
    var n: usize = 0;
    while (i < src.len) : (n += 1) {
        if (n == out.len) return error.VectorTooLong;
        if (src[i] == '\\' and i + 1 < src.len and src[i + 1] == '\\') {
            out[n] = '\\';
            i += 2;
        } else if (src[i] == '\\' and i + 4 <= src.len and src[i + 1] == 'x') {
            out[n] = try std.fmt.parseInt(u8, src[i + 2 .. i + 4], 16);
            i += 4;
        } else {
            out[n] = src[i];
            i += 1;
        }
    }
    return out[0..n];
}

fn parseExpected(text: []const u8) !Expected {
    var words = std.mem.tokenizeScalar(u8, text, ' ');
    const verb = words.next() orelse return error.MalformedVector;
    const arg = words.next();
    if (words.next() != null) return error.MalformedVector;
    if (std.mem.eql(u8, verb, "helper")) {
        const name = arg orelse return error.MalformedVector;
        if (!helpers.validName(name)) return error.MalformedVector;
        var owned: HelperName = .{ .name_len = name.len };
        @memcpy(owned.name[0..name.len], name);
        return .{ .ok = .{ .helper = owned } };
    }
    const gen = if (arg) |a| try std.fmt.parseInt(u32, a, 10) else null;
    if (std.mem.eql(u8, verb, "heartbeat")) return .{ .ok = .heartbeat };
    if (std.mem.eql(u8, verb, "commit")) return .{ .ok = .{ .commit = gen orelse return error.MalformedVector } };
    if (std.mem.eql(u8, verb, "next")) return .{ .ok = .{ .next = gen orelse return error.MalformedVector } };
    if (std.mem.eql(u8, verb, "reboot")) return .{ .ok = .reboot };
    if (std.mem.eql(u8, verb, "poweroff")) return .{ .ok = .poweroff };
    if (std.mem.eql(u8, verb, "halt")) return .{ .ok = .halt };
    if (std.mem.eql(u8, verb, "invalid")) return .{ .err = error.Invalid };
    if (std.mem.eql(u8, verb, "too_long")) return .{ .err = error.TooLong };
    return error.MalformedVector;
}

test "protocol: shared golden vectors (spec/protocol.vectors)" {
    try milestone.require(1);
    var seen: std.EnumSet(std.meta.Tag(Message)) = .empty;
    var checked: usize = 0;
    var line_no: usize = 0;
    var lines = std.mem.splitScalar(u8, vectors, '\n');
    while (lines.next()) |line| {
        line_no += 1;
        if (line.len == 0 or line[0] == '#') continue;
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse return error.MalformedVector;
        var wire_buf: [256]u8 = undefined;
        const wire = try unescape(line[0..tab], &wire_buf);
        const expected = try parseExpected(line[tab + 1 ..]);
        checked += 1;

        const actual = parse(wire);
        switch (expected) {
            .ok => |want| {
                const got = actual catch |err| {
                    std.debug.print("spec/protocol.vectors:{d}: expected {any}, got error.{t}\n", .{ line_no, want, err });
                    return err;
                };
                if (!std.meta.eql(want, got)) {
                    std.debug.print("spec/protocol.vectors:{d}: expected {any}, got {any}\n", .{ line_no, want, got });
                    return error.TestExpectedEqual;
                }
                seen.insert(std.meta.activeTag(got));
                var out: [max_line_len + 1]u8 = undefined;
                const encoded = try encode(got, &out);
                try testing.expectEqualStrings(wire, encoded[0 .. encoded.len - 1]);
                try testing.expectEqual(@as(u8, '\n'), encoded[encoded.len - 1]);
            },
            .err => |want| {
                if (actual) |got| {
                    std.debug.print("spec/protocol.vectors:{d}: expected error.{t}, got {any}\n", .{ line_no, want, got });
                    return error.TestUnexpectedResult;
                } else |err| {
                    if (err != want) {
                        std.debug.print("spec/protocol.vectors:{d}: expected error.{t}, got error.{t}\n", .{ line_no, want, err });
                        return error.TestUnexpectedError;
                    }
                }
            },
        }
    }
    try testing.expect(checked >= 40);
    // Every message kind must be covered by at least one valid vector.
    try testing.expect(seen.eql(.full));
}

test "protocol: encode reports a buffer that is too small" {
    try milestone.require(1);
    var tiny: [8]u8 = undefined;
    try testing.expectError(error.NoSpaceLeft, encode(.{ .commit = 4294967295 }, &tiny));
    var exact: [3]u8 = undefined;
    try testing.expectEqualStrings("HB\n", try encode(.heartbeat, &exact));
}

test "protocol: the longest valid message fits comfortably in a line" {
    try milestone.require(1);
    var out: [max_line_len + 1]u8 = undefined;
    const longest = try encode(.{ .commit = std.math.maxInt(u32) }, &out);
    try testing.expectEqualStrings("COMMIT 4294967295\n", longest);
    try testing.expect(longest.len <= max_line_len + 1);
}

test "protocol: helper names own their bytes independently of the input buffer" {
    try milestone.require(17);
    var input = "HELPER initdb".*;
    const msg = try parse(&input);
    @memset(&input, 'x');
    var out: [max_line_len + 1]u8 = undefined;
    try testing.expectEqualStrings("HELPER initdb\n", try encode(msg, &out));
    const name = msg.helper;
    for (name.name[name.name_len..]) |byte| try testing.expectEqual(@as(u8, 0), byte);
    var tiny: [8]u8 = undefined;
    try testing.expectError(error.NoSpaceLeft, encode(msg, &tiny));
}
