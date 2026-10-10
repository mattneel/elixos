//! Kernel command line -> shim settings (docs/PROTOCOL.md §5). Pure code.
//!
//! main.zig reads /proc/cmdline once at boot and hands the text to `parse`.
//! Only `elixos.*` tokens are ours; everything else belongs to the kernel.
const std = @import("std");
const testing = std.testing;
const milestone = @import("milestone.zig");
const decimal = @import("decimal.zig");

pub const Settings = struct {
    /// elixos.safe[=1|0]: boot the factory in rescue mode.
    safe: bool = false,
    /// elixos.generation=N: boot generation N once.
    generation: ?u32 = null,
    /// elixos.max_attempts=N (N >= 1).
    max_attempts: u32 = 3,
    /// elixos.hb_timeout=S (S >= 1): seconds without a heartbeat before the BEAM is killed.
    heartbeat_timeout_s: u32 = 10,
    /// elixos.boot_grace=S (S >= 1): seconds allowed before the *first* heartbeat.
    boot_grace_s: u32 = 120,
    /// elixos.data=/dev/...: block device holding the persistent image (ext4).
    data_device: []const u8 = "/dev/vda",
    /// elixos.test.stop_before_launch[=1|0]: log the plan, persist it, power off.
    /// Honored only in -Dtest-hooks builds (main.zig checks build_options).
    test_stop_before_launch: bool = false,
    /// elixos.test.shim_panic_after=S (S >= 1): panic the shim S seconds after launch.
    /// Honored only in -Dtest-hooks builds.
    test_shim_panic_after_s: ?u32 = null,
    /// Count of elixos.* tokens that were unknown or malformed. The shim logs it.
    invalid: u32 = 0,
};

/// Never fails: bad elixos.* tokens are counted in `invalid` and otherwise ignored.
/// Tokens are separated by spaces or newlines; the last occurrence of a key wins.
/// Returned slices point into `text`. Numbers use decimal.parseU32.
pub fn parse(text: []const u8) Settings {
    _ = text;
    @panic("TODO(M1): cmdline.parse");
}

test "cmdline: defaults when nothing elixos-specific is present" {
    try milestone.require(1);
    try testing.expectEqualDeep(Settings{}, parse("console=ttyS0 panic=-1 quiet\n"));
    try testing.expectEqualDeep(Settings{}, parse(""));
}

test "cmdline: recognizes every elixos.* parameter" {
    try milestone.require(1);
    const s = parse("console=ttyS0 elixos.safe elixos.generation=12 elixos.max_attempts=5 " ++
        "elixos.hb_timeout=30 elixos.boot_grace=300 elixos.data=/dev/sda2 " ++
        "elixos.test.stop_before_launch elixos.test.shim_panic_after=4\n");
    try testing.expect(s.safe);
    try testing.expectEqual(@as(?u32, 12), s.generation);
    try testing.expectEqual(@as(u32, 5), s.max_attempts);
    try testing.expectEqual(@as(u32, 30), s.heartbeat_timeout_s);
    try testing.expectEqual(@as(u32, 300), s.boot_grace_s);
    try testing.expectEqualStrings("/dev/sda2", s.data_device);
    try testing.expect(s.test_stop_before_launch);
    try testing.expectEqual(@as(?u32, 4), s.test_shim_panic_after_s);
    try testing.expectEqual(@as(u32, 0), s.invalid);
}

test "cmdline: boolean flags accept bare, =1 and =0" {
    try milestone.require(1);
    try testing.expect(parse("elixos.safe=1").safe);
    try testing.expect(!parse("elixos.safe=0").safe);
    try testing.expect(parse("elixos.test.stop_before_launch=1").test_stop_before_launch);
    try testing.expect(!parse("elixos.test.stop_before_launch=0").test_stop_before_launch);
}

test "cmdline: the last occurrence wins" {
    try milestone.require(1);
    const s = parse("elixos.safe elixos.max_attempts=2 elixos.safe=0 elixos.max_attempts=7");
    try testing.expect(!s.safe);
    try testing.expectEqual(@as(u32, 7), s.max_attempts);
}

test "cmdline: malformed or unknown elixos.* tokens are counted, never applied" {
    try milestone.require(1);
    const s = parse("elixos.generation=abc elixos.max_attempts=0 elixos.hb_timeout=-1 " ++
        "elixos.boot_grace=0 elixos.data=sda2 elixos.bogus=1 elixos.safe=yes " ++
        "elixos.test.shim_panic_after=0 elixos.generation=07");
    var expected: Settings = .{};
    expected.invalid = 9;
    try testing.expectEqualDeep(expected, s);
}

test "cmdline: tolerates repeated spaces and the trailing newline" {
    try milestone.require(1);
    const s = parse("  quiet   elixos.generation=3  \n");
    try testing.expectEqual(@as(?u32, 3), s.generation);
    try testing.expectEqual(@as(u32, 0), s.invalid);
}
