//! Kernel command line -> shim settings (docs/PROTOCOL.md §5). Pure code.
//!
//! main.zig reads /proc/cmdline once at boot and hands the text to `parse`.
//! Only `elixos.*` tokens are ours; everything else belongs to the kernel.
const std = @import("std");
const testing = std.testing;
const milestone = @import("milestone.zig");
const decimal = @import("decimal.zig");
const deck = @import("deck.zig");
const coproc_ring = @import("coproc_ring.zig");

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
    /// elixos.coproc_link=<interface>,<a.b.c.d>/<prefix>: the coprocessor link
    /// (M29, ADR-098). The shim gives the interface this address and brings it
    /// up before the BEAM starts; Elixos.Coproc binds its listener to it.
    coproc_link: ?Link = null,
    /// elixos.deck=<spec>: the deck framebuffer's device (M33, PROTOCOL.md
    /// §12): `pci:<vendor>:<device>`, `uio:<name>` or `/dev/<path>`. The
    /// shim finds it, grants it to the BEAM and passes it as ELIXOS_DECK.
    deck: ?deck.Spec = null,
    /// elixos.coproc_ring=<spec>: the inter-core ring's device (M33,
    /// PROTOCOL.md §11): `uio:<name>` or `/dev/<path>`. The shim keeps
    /// `elixos-link` running on it, before and across the BEAM's launches.
    coproc_ring: ?deck.Spec = null,
    /// Count of elixos.* tokens that were unknown or malformed. The shim logs it.
    invalid: u32 = 0,
};

pub const Link = struct {
    interface: []const u8,
    address: [4]u8,
    prefix: u6,
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
        } else if (std.mem.eql(u8, name, "profile")) {
            // BEAM side too (ADR-111): the image's service profile.
            if (!validProfile(value)) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "test.stop_before_launch")) {
            if (setFlag(&settings.test_stop_before_launch, value) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "test.shim_panic_after")) {
            if (setNumber(&settings.test_shim_panic_after_s, value, 1) == null) settings.invalid += 1;
        } else if (std.mem.eql(u8, name, "coproc_link")) {
            if (parseLink(value)) |link| {
                settings.coproc_link = link;
            } else {
                settings.invalid += 1;
            }
        } else if (std.mem.eql(u8, name, "deck")) {
            if (deck.parseSpec(value)) |spec| {
                settings.deck = spec;
            } else {
                settings.invalid += 1;
            }
        } else if (std.mem.eql(u8, name, "coproc_ring")) {
            if (coproc_ring.parseSpec(value)) |spec| {
                settings.coproc_ring = spec;
            } else {
                settings.invalid += 1;
            }
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

/// `elixos.profile=full|deck` (ADR-111): read by Elixos.Boot.Cmdline.
fn validProfile(value: ?[]const u8) bool {
    const profile = value orelse return false;
    return std.mem.eql(u8, profile, "full") or std.mem.eql(u8, profile, "deck");
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

/// `<interface>,<a.b.c.d>/<prefix>`: a kernel interface name (1-15 of
/// [A-Za-z0-9_.-]), a canonical dotted-quad IPv4 address and a prefix length
/// 1-32. Null for anything else.
fn parseLink(value: ?[]const u8) ?Link {
    const text = value orelse return null;
    const comma = std.mem.indexOfScalar(u8, text, ',') orelse return null;
    return parseInterfaceAddress(text[0..comma], text[comma + 1 ..]);
}

/// An interface name and `<a.b.c.d>/<prefix>`, validated as for
/// elixos.coproc_link (also elixos-link's `--tun` and `--address`, M31).
pub fn parseInterfaceAddress(interface: []const u8, cidr: []const u8) ?Link {
    if (!validInterface(interface)) return null;
    const slash = std.mem.indexOfScalar(u8, cidr, '/') orelse return null;
    var address: [4]u8 = undefined;
    var octets = std.mem.splitScalar(u8, cidr[0..slash], '.');
    for (&address) |*octet| {
        const part = octets.next() orelse return null;
        const number = decimal.parseU32(part) orelse return null;
        if (number > 255) return null;
        octet.* = @intCast(number);
    }
    if (octets.next() != null) return null;
    const prefix = decimal.parseU32(cidr[slash + 1 ..]) orelse return null;
    if (prefix < 1 or prefix > 32) return null;
    return .{ .interface = interface, .address = address, .prefix = @intCast(prefix) };
}

/// A kernel interface name: 1-15 of [A-Za-z0-9_.-], not "." or "..".
pub fn validInterface(interface: []const u8) bool {
    if (interface.len == 0 or interface.len > 15) return false;
    if (std.mem.eql(u8, interface, ".") or std.mem.eql(u8, interface, "..")) return false;
    for (interface) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '.' and c != '-') return false;
    }
    return true;
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

test "cmdline: the coprocessor link names an interface, an address and a prefix" {
    try milestone.require(29);
    const settings = parse("console=ttyS0 elixos.coproc_link=eth1,10.0.3.15/24");
    const link = settings.coproc_link orelse return error.TestExpectedLink;
    try testing.expectEqualSlices(u8, "eth1", link.interface);
    try testing.expectEqual([4]u8{ 10, 0, 3, 15 }, link.address);
    try testing.expectEqual(@as(u6, 24), link.prefix);
    try testing.expectEqual(@as(u32, 0), settings.invalid);
    // The last valid one wins; a malformed one is counted and changes nothing.
    const later = parse("elixos.coproc_link=eth1,10.0.3.15/24 elixos.coproc_link=coproc0,192.168.7.1/32 " ++
        "elixos.coproc_link=bad");
    try testing.expectEqualSlices(u8, "coproc0", later.coproc_link.?.interface);
    try testing.expectEqual([4]u8{ 192, 168, 7, 1 }, later.coproc_link.?.address);
    try testing.expectEqual(@as(u32, 1), later.invalid);
}

test "cmdline: a malformed coprocessor link is refused, never half-applied" {
    try milestone.require(29);
    const bad = [_][]const u8{
        "elixos.coproc_link",                      "elixos.coproc_link=",
        "elixos.coproc_link=eth1",                 "elixos.coproc_link=,10.0.3.15/24",
        "elixos.coproc_link=eth1,10.0.3.15",       "elixos.coproc_link=eth1,10.0.3/24",
        "elixos.coproc_link=eth1,10.0.3.15.1/24",  "elixos.coproc_link=eth1,10.0.3.256/24",
        "elixos.coproc_link=eth1,10.0.03.15/24",   "elixos.coproc_link=eth1,10.0.3.15/0",
        "elixos.coproc_link=eth1,10.0.3.15/33",    "elixos.coproc_link=eth/1,10.0.3.15/24",
        "elixos.coproc_link=..,10.0.3.15/24",      "elixos.coproc_link=abcdefghijklmnop,10.0.3.15/24",
    };
    for (bad) |text| {
        const settings = parse(text);
        try testing.expect(settings.coproc_link == null);
        try testing.expectEqual(@as(u32, 1), settings.invalid);
    }
}

test "cmdline: the deck names its framebuffer's device" {
    try milestone.require(33);
    const settings = parse("console=ttyS0 elixos.deck=pci:0x1af4:0x1110");
    const spec = settings.deck orelse return error.TestExpectedDeck;
    try testing.expectEqualStrings("0x1af4", spec.target.pci.vendor);
    try testing.expectEqualStrings("0x1110", spec.target.pci.device);
    try testing.expectEqual(@as(u32, 0), settings.invalid);
    // The last valid one wins; a malformed one is counted and changes nothing.
    const later = parse("elixos.deck=pci:0x1af4:0x1110 elixos.deck=uio:deck-fb elixos.deck=/etc/passwd elixos.deck");
    try testing.expectEqualStrings("deck-fb", later.deck.?.target.uio);
    try testing.expectEqual(@as(u32, 2), later.invalid);
    try testing.expectEqualStrings("/dev/uio0", parse("elixos.deck=/dev/uio0").deck.?.target.path);
}

test "cmdline: the coprocessor ring names its region's device" {
    try milestone.require(33);
    const settings = parse("console=ttyS0 elixos.coproc_ring=uio:coproc-ring elixos.coproc_link=coproc0,10.0.3.15/24");
    const spec = settings.coproc_ring orelse return error.TestExpectedRing;
    try testing.expectEqualStrings("coproc-ring", spec.target.uio);
    try testing.expectEqualStrings("uio:coproc-ring", spec.text);
    try testing.expectEqualStrings("coproc0", settings.coproc_link.?.interface);
    try testing.expectEqual(@as(u32, 0), settings.invalid);
    // The last valid one wins; a malformed one (or a PCI device) is counted
    // and changes nothing.
    const later = parse("elixos.coproc_ring=uio:a elixos.coproc_ring=/dev/uio2 " ++
        "elixos.coproc_ring=pci:0x1af4:0x1110 elixos.coproc_ring elixos.coproc_ring=uio:");
    try testing.expectEqualStrings("/dev/uio2", later.coproc_ring.?.target.path);
    try testing.expectEqual(@as(u32, 3), later.invalid);
    try testing.expect(parse("elixos.deck=uio:deck-fb").coproc_ring == null);
}

test "cmdline: the image profile is a BEAM-side parameter" {
    try milestone.require(33);
    // ADR-111, ADR-023: validated here, applied by Elixos.Boot.Cmdline.
    try testing.expectEqualDeep(Settings{}, parse("elixos.profile=deck"));
    try testing.expectEqualDeep(Settings{}, parse("elixos.profile=full"));
    for ([_][]const u8{ "elixos.profile", "elixos.profile=", "elixos.profile=Deck", "elixos.profile=lite" }) |bad| {
        try testing.expectEqual(@as(u32, 1), parse(bad).invalid);
    }
}
