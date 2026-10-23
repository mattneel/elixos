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
    /// elixos.live[=1|0]: keep writable /priv on the RAM-backed initramfs rootfs.
    /// Never mounts data_device, even when safe or data is also supplied.
    live: bool = false,
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
    /// elixos.data_wait=S (S >= 0): seconds to wait for `data_device` to
    /// appear before giving up. The kernel runs /init without waiting for USB
    /// or SD storage, so on hardware the device may need a moment; QEMU
    /// virtual disks are always ready, and 0 disables the wait.
    data_wait_s: u32 = 10,
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
    var settings: Settings = .{};
    var tokens = std.mem.tokenizeAny(u8, text, " \n");
    while (tokens.next()) |token| {
        const equals = std.mem.indexOfScalar(u8, token, '=');
        const key = if (equals) |i| token[0..i] else token;
        const value: ?[]const u8 = if (equals) |i| token[i + 1 ..] else null;
        // Everything else on the command line belongs to the kernel.
        const name = std.mem.cutPrefix(u8, key, "elixos.") orelse continue;

        if (std.mem.eql(u8, name, "safe")) {
            if (setFlag(&settings.safe, value) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "live")) {
            if (setFlag(&settings.live, value) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "generation")) {
            if (setNumber(&settings.generation, value, 0) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "max_attempts")) {
            if (setNumber(&settings.max_attempts, value, 1) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "hb_timeout")) {
            if (setNumber(&settings.heartbeat_timeout_s, value, 1) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "boot_grace")) {
            if (setNumber(&settings.boot_grace_s, value, 1) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "data")) {
            const device = value orelse {
                settings.invalid += 1;
                continue;
            };
            if (std.mem.startsWith(u8, device, "/dev/") and device.len > "/dev/".len) {
                settings.data_device = device;
            } else {
                settings.invalid += 1;
            }
        } else if (std.mem.eql(u8, name, "data_wait")) {
            if (setNumber(&settings.data_wait_s, value, 0) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "commit_after")) {
            // BEAM side (PROTOCOL.md §5, ADR-023): the shim knows the name and
            // the syntax, checks them, and never applies the value - the BEAM
            // reads it itself. A good value is not an invalid parameter.
            if (!validNumber(value, 1)) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "test.stop_before_launch")) {
            if (setFlag(&settings.test_stop_before_launch, value) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "test.shim_panic_after")) {
            if (setNumber(&settings.test_shim_panic_after_s, value, 1) == null) settings.invalid += 1;
        } else {
            settings.invalid += 1;
        }
    }
    return settings;
}

/// A BEAM-side parameter (ADR-023): checked here, applied by Elixos.Boot.Cmdline.
fn validNumber(value: ?[]const u8, min: u32) bool {
    const parsed = decimal.parseU32(value orelse return false) orelse return false;
    return parsed >= min;
}

/// `elixos.flag`, `=1` or `=0`; null for anything else. Returns true when set.
fn setFlag(field: *bool, value: ?[]const u8) ?void {
    const flag = value orelse {
        field.* = true;
        return {};
    };
    if (std.mem.eql(u8, flag, "1")) {
        field.* = true;
        return {};
    }
    if (std.mem.eql(u8, flag, "0")) {
        field.* = false;
        return {};
    }
    return null;
}

/// `key=N` with a canonical u32 N >= `min`; null for anything else.
fn setNumber(field: anytype, value: ?[]const u8, min: u32) ?void {
    const parsed = decimal.parseU32(value orelse return null) orelse return null;
    if (parsed < min) return null;
    field.* = parsed;
    return {};
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

test "cmdline: a BEAM-side parameter is validated but never counted" {
    try milestone.require(5);

    // `elixos.commit_after` belongs to the BEAM (PROTOCOL.md §5, ADR-023): the
    // shim checks its syntax and never applies it, and a good value is not an
    // "invalid elixos.* parameter".
    const good = parse("console=ttyS0 quiet elixos.commit_after=2 elixos.data=/dev/vda");
    try testing.expectEqual(@as(u32, 0), good.invalid);

    // A malformed value is still the shim's business to report.
    try testing.expectEqual(@as(u32, 1), parse("elixos.commit_after=abc").invalid);
    try testing.expectEqual(@as(u32, 1), parse("elixos.commit_after=0").invalid);
    try testing.expectEqual(@as(u32, 1), parse("elixos.commit_after=07").invalid);
    try testing.expectEqual(@as(u32, 1), parse("elixos.commit_after").invalid);

    // And a key neither side defines stays a typo.
    try testing.expectEqual(@as(u32, 1), parse("elixos.commit_after_x=2").invalid);
}

test "cmdline: tolerates repeated spaces and the trailing newline" {
    try milestone.require(1);
    const s = parse("  quiet   elixos.generation=3  \n");
    try testing.expectEqual(@as(?u32, 3), s.generation);
    try testing.expectEqual(@as(u32, 0), s.invalid);
}

test "cmdline: live accepts the same boolean syntax as safe" {
    try milestone.require(1);
    const cases = [_]struct { text: []const u8, live: bool, invalid: u32 = 0 }{
        .{ .text = "elixos.live", .live = true },
        .{ .text = "elixos.live=1", .live = true },
        .{ .text = "elixos.live=0", .live = false },
        .{ .text = "elixos.live=", .live = false, .invalid = 1 },
        .{ .text = "elixos.live=2", .live = false, .invalid = 1 },
        .{ .text = "elixos.live=yes", .live = false, .invalid = 1 },
        .{ .text = "elixos.live=true", .live = false, .invalid = 1 },
        .{ .text = "elixos.live=01", .live = false, .invalid = 1 },
        .{ .text = "elixos.live=1=0", .live = false, .invalid = 1 },
    };
    for (cases) |case| {
        const settings = parse(case.text);
        try testing.expectEqual(case.live, settings.live);
        try testing.expectEqual(case.invalid, settings.invalid);
        try testing.expect(!settings.safe);
    }
}

test "cmdline: the last valid live flag wins and malformed flags do not reset it" {
    try milestone.require(1);
    const cases = [_]struct { text: []const u8, live: bool, invalid: u32 = 0 }{
        .{ .text = "elixos.live elixos.live=0", .live = false },
        .{ .text = "elixos.live=0 elixos.live=1", .live = true },
        .{ .text = "elixos.live=0 elixos.live", .live = true },
        .{ .text = "elixos.live=1 elixos.live=bad", .live = true, .invalid = 1 },
        .{ .text = "elixos.live=0 elixos.live=bad", .live = false, .invalid = 1 },
        .{ .text = "elixos.live=bad elixos.live", .live = true, .invalid = 1 },
    };
    for (cases) |case| {
        const settings = parse(case.text);
        try testing.expectEqual(case.live, settings.live);
        try testing.expectEqual(case.invalid, settings.invalid);
    }
}
