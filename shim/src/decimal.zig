//! Canonical unsigned decimals (docs/PROTOCOL.md §1).
//!
//! Shared by the control protocol, boot.state and the kernel command line:
//! `0` or `[1-9][0-9]*`, value at most maxInt(u32). No sign, no leading zeros,
//! no whitespace, ASCII digits only. One grammar everywhere means one parser.
const std = @import("std");
const testing = std.testing;
const milestone = @import("milestone.zig");

/// Returns the value, or null if `text` is not a canonical u32.
pub fn parseU32(text: []const u8) ?u32 {
    _ = text;
    @panic("TODO(M1): decimal.parseU32");
}

test "decimal: accepts canonical u32 values" {
    try milestone.require(1);
    try testing.expectEqual(@as(?u32, 0), parseU32("0"));
    try testing.expectEqual(@as(?u32, 7), parseU32("7"));
    try testing.expectEqual(@as(?u32, 10), parseU32("10"));
    try testing.expectEqual(@as(?u32, 4294967295), parseU32("4294967295"));
}

test "decimal: rejects everything that is not canonical" {
    try milestone.require(1);
    const rejected = [_][]const u8{
        "",    "00",   "07",    "-1",  "+1",         " 1", "1 ",
        "1.0", "0x10", "1_000", "1e3", "4294967296",
        "4294967300", "99999999999999999999", "\u{0661}", // ARABIC-INDIC DIGIT ONE
    };
    for (rejected) |text| {
        if (parseU32(text)) |value| {
            std.debug.print("decimal.parseU32({q}) must be null, got {d}\n", .{ text, value });
            return error.TestUnexpectedResult;
        }
    }
}
