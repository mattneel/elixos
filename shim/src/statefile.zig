//! boot.state: the shim's only persistent state (docs/PROTOCOL.md §4).
//!
//! Single writer: the shim (ADR-006). The BEAM asks for changes over the
//! control protocol and may read the file, never write it. Pure code here;
//! main.zig does the write-temp + fsync + rename + fsync(dir) dance.
const std = @import("std");
const testing = std.testing;
const milestone = @import("milestone.zig");
const decimal = @import("decimal.zig");
const recovery = @import("recovery.zig");

pub const BootState = recovery.BootState;

/// Big enough for the canonical encoding of any BootState.
pub const max_len = 64;

pub const ParseError = error{ BadLine, UnknownKey, DuplicateKey, BadValue, MissingKey };

/// Strict parse. See PROTOCOL.md §4 for the exact grammar and error precedence.
pub fn parse(text: []const u8) ParseError!BootState {
    _ = text;
    @panic("TODO(M1): statefile.parse");
}

/// Canonical form: `current=N\nlast_good=N\nattempts=N\n`, in that order.
pub fn encode(state: BootState, buf: []u8) error{NoSpaceLeft}![]u8 {
    _ = state;
    _ = buf;
    @panic("TODO(M1): statefile.encode");
}

test "statefile: parses the canonical form" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        BootState{ .current = 7, .last_good = 6, .attempts = 1 },
        try parse("current=7\nlast_good=6\nattempts=1\n"),
    );
}

test "statefile: trailing newline is optional and key order is free" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        BootState{ .current = 7, .last_good = 6, .attempts = 1 },
        try parse("attempts=1\ncurrent=7\nlast_good=6"),
    );
}

test "statefile: encodes canonically" {
    try milestone.require(1);
    var buf: [max_len]u8 = undefined;
    try testing.expectEqualStrings(
        "current=7\nlast_good=6\nattempts=1\n",
        try encode(.{ .current = 7, .last_good = 6, .attempts = 1 }, &buf),
    );
}

test "statefile: round-trips the extremes" {
    try milestone.require(1);
    const max = std.math.maxInt(u32);
    const cases = [_]BootState{ .{}, .{ .current = max, .last_good = max, .attempts = max } };
    for (cases) |state| {
        var buf: [max_len]u8 = undefined;
        try testing.expectEqualDeep(state, try parse(try encode(state, &buf)));
    }
}

test "statefile: encode reports a buffer that is too small" {
    try milestone.require(1);
    var buf: [10]u8 = undefined;
    try testing.expectError(error.NoSpaceLeft, encode(.{}, &buf));
}

test "statefile: rejects malformed files with the documented error" {
    try milestone.require(1);
    const Case = struct { text: []const u8, err: ParseError };
    const cases = [_]Case{
        .{ .text = "", .err = error.MissingKey },
        .{ .text = "\n", .err = error.MissingKey },
        .{ .text = "current=7\nlast_good=6\n", .err = error.MissingKey },
        .{ .text = "current=7\nlast_good=6\nattempts=1\nattempts=2\n", .err = error.DuplicateKey },
        .{ .text = "current=7\nlast_good=6\nattempts=1\nextra=1\n", .err = error.UnknownKey },
        .{ .text = " current=7\nlast_good=6\nattempts=1\n", .err = error.UnknownKey },
        .{ .text = "current=7\nlast_good=6\nattempts=01\n", .err = error.BadValue },
        .{ .text = "current=7\nlast_good=-6\nattempts=1\n", .err = error.BadValue },
        .{ .text = "current=7\nlast_good=6\nattempts=\n", .err = error.BadValue },
        .{ .text = "current==7\nlast_good=6\nattempts=1\n", .err = error.BadValue },
        .{ .text = "current=7\r\nlast_good=6\r\nattempts=1\r\n", .err = error.BadValue },
        .{ .text = "current=4294967296\nlast_good=6\nattempts=1\n", .err = error.BadValue },
        .{ .text = "current=7\n\nlast_good=6\nattempts=1\n", .err = error.BadLine },
        .{ .text = "current=7\nlast_good=6\nattempts=1\n\n", .err = error.BadLine },
        .{ .text = "current 7\nlast_good=6\nattempts=1\n", .err = error.BadLine },
        .{ .text = "=7\nlast_good=6\nattempts=1\n", .err = error.BadLine },
    };
    for (cases) |case| {
        if (parse(case.text)) |state| {
            std.debug.print("statefile.parse({q}) must fail with {t}, got {any}\n", .{ case.text, case.err, state });
            return error.TestUnexpectedResult;
        } else |err| {
            if (err != case.err) {
                std.debug.print("statefile.parse({q}): expected {t}, got {t}\n", .{ case.text, case.err, err });
                return error.TestUnexpectedError;
            }
        }
    }
}
