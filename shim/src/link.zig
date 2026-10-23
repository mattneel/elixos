//! elixos-link (docs/PROTOCOL.md §11): bridges the inter-core ring to a TUN
//! device. Every packet read from TUN goes into the outgoing ring, every frame
//! from the incoming ring goes onto TUN. Static, libc-free, single-threaded;
//! after startup the loop allocates nothing and only polls, reads and writes.
const std = @import("std");
const linux = std.os.linux;
const ring = @import("ring.zig");
const cmdline = @import("cmdline.zig");
const netif = @import("netif.zig");
const milestone = @import("milestone.zig");

const prefix = "elixos-link: ";
const usage =
    "usage: elixos-link --region <path> --size <S> [--offset <bytes>] --tun <ifname>\n" ++
    "                   [--side big|little] [--address <ip>/<len>]\n";

pub const Options = struct {
    region: [*:0]const u8,
    size: u64,
    offset: u64 = 0,
    tun: []const u8,
    side: ring.Side = .big,
    address: ?cmdline.Link = null,
};

/// The arguments after argv[0]. Null for anything malformed: unknown or
/// repeated flags, a size that is not a valid region (ring.capacityFor), an
/// offset that is not page-aligned, a bad interface name or address.
pub fn parseArgs(args: []const [:0]const u8) ?Options {
    var region: ?[*:0]const u8 = null;
    var size: ?u64 = null;
    var offset: ?u64 = null;
    var tun: ?[]const u8 = null;
    var side: ?ring.Side = null;
    var address: ?[]const u8 = null;
    if (args.len % 2 != 0) return null;
    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        const flag = args[i];
        const value = args[i + 1];
        if (std.mem.eql(u8, flag, "--region")) {
            if (region != null or value.len == 0) return null;
            region = value.ptr;
        } else if (std.mem.eql(u8, flag, "--size")) {
            if (size != null) return null;
            size = parseU64(value) orelse return null;
        } else if (std.mem.eql(u8, flag, "--offset")) {
            if (offset != null) return null;
            offset = parseU64(value) orelse return null;
        } else if (std.mem.eql(u8, flag, "--tun")) {
            if (tun != null or !cmdline.validInterface(value)) return null;
            tun = value;
        } else if (std.mem.eql(u8, flag, "--side")) {
            if (side != null) return null;
            side = std.meta.stringToEnum(ring.Side, value) orelse return null;
        } else if (std.mem.eql(u8, flag, "--address")) {
            if (address != null) return null;
            address = value;
        } else return null;
    }
    var options: Options = .{
        .region = region orelse return null,
        .size = size orelse return null,
        .tun = tun orelse return null,
        .offset = offset orelse 0,
        .side = side orelse .big,
    };
    _ = ring.capacityFor(options.size) orelse return null;
    if (options.offset % 4096 != 0 or options.offset > std.math.maxInt(i64) - options.size) return null;
    if (options.size > std.math.maxInt(usize)) return null;
    if (address) |cidr| options.address = cmdline.parseInterfaceAddress(options.tun, cidr) orelse return null;
    return options;
}

/// Canonical decimal: digits only, no leading zero, no overflow.
fn parseU64(text: []const u8) ?u64 {
    if (text.len == 0 or (text.len > 1 and text[0] == '0')) return null;
    var value: u64 = 0;
    for (text) |c| {
        if (c < '0' or c > '9') return null;
        value = std.math.mul(u64, value, 10) catch return null;
        value = std.math.add(u64, value, c - '0') catch return null;
    }
    return value;
}

pub const Stats = struct {
    /// Packets moved from TUN into the outgoing ring.
    tx: u64 = 0,
    /// Frames moved from the incoming ring onto TUN.
    rx: u64 = 0,
    /// Packets dropped because the outgoing ring was full (or the packet is
    /// longer than the ring carries).
    full: u64 = 0,
    /// Incoming frames this helper discarded as corrupt.
    dropped: u64 = 0,
};

pub fn statsLine(buffer: []u8, stats: Stats) []const u8 {
    return std.fmt.bufPrint(buffer, prefix ++ "stats tx {d} rx {d} full {d} dropped {d}\n", .{
        stats.tx, stats.rx, stats.full, stats.dropped,
    }) catch unreachable;
}

pub fn upLine(buffer: []u8, interface: []const u8, size: u64) []const u8 {
    return std.fmt.bufPrint(buffer, prefix ++ "up {s} region {d} bytes\n", .{ interface, size }) catch unreachable;
}

fn say(bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = linux.write(2, bytes.ptr + written, bytes.len - written);
        switch (linux.errno(rc)) {
            .SUCCESS => written += rc,
            .INTR => {},
            else => return,
        }
    }
}

fn fail(what: []const u8, err: anyerror) noreturn {
    var buffer: [256]u8 = undefined;
    say(std.fmt.bufPrint(&buffer, prefix ++ "{s} failed ({t})\n", .{ what, err }) catch prefix ++ "failed\n");
    linux.exit_group(1);
}

fn checked(raw: usize) error{System}!usize {
    return if (linux.errno(raw) == .SUCCESS) raw else error.System;
}

fn report(stats: Stats) void {
    var buffer: [160]u8 = undefined;
    say(statsLine(&buffer, stats));
}

/// Reads pending signals: SIGUSR1 prints the stats, SIGTERM and SIGINT print
/// them and exit.
fn handleSignals(signals: linux.fd_t, stats: Stats) void {
    while (true) {
        var info: linux.signalfd_siginfo = undefined;
        const rc = linux.read(signals, @ptrCast(&info), @sizeOf(linux.signalfd_siginfo));
        if (linux.errno(rc) != .SUCCESS or rc != @sizeOf(linux.signalfd_siginfo)) return;
        report(stats);
        if (info.signo != @backingInt(linux.SIG.USR1)) linux.exit_group(0);
    }
}

fn blockSignals() linux.fd_t {
    var mask = linux.sigemptyset();
    for ([_]linux.SIG{ .USR1, .TERM, .INT }) |signal| linux.sigaddset(&mask, signal);
    _ = checked(linux.sigprocmask(linux.SIG.BLOCK, &mask, null)) catch |err| fail("sigprocmask", err);
    const fd = checked(linux.signalfd(-1, &mask, linux.SFD.NONBLOCK | linux.SFD.CLOEXEC)) catch |err| fail("signalfd", err);
    return @intCast(fd);
}

fn mapRegion(options: Options) []align(8) u8 {
    const fd: linux.fd_t = @intCast(checked(linux.openat(linux.AT.FDCWD, options.region, .{
        .ACCMODE = .RDWR,
        .CLOEXEC = true,
    }, 0)) catch |err| fail("opening the region", err));
    defer _ = linux.close(fd);
    // A regular file shorter than the region would fault on access (SIGBUS);
    // a device (UIO) reports no size and is trusted to be large enough.
    var stat: linux.Statx = undefined;
    _ = checked(linux.statx(fd, "", linux.AT.EMPTY_PATH, .{ .TYPE = true, .SIZE = true }, &stat)) catch |err| fail("statx on the region", err);
    if (linux.S.ISREG(stat.mode) and stat.size < options.offset + options.size) fail("checking the region size", error.RegionTooSmall);
    const size: usize = @intCast(options.size);
    const address = checked(linux.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, @intCast(options.offset))) catch |err| fail("mapping the region", err);
    return @as([*]align(4096) u8, @ptrFromInt(address))[0..size];
}

const TUNSETIFF = 0x400454ca;
const IFF_TUN: u16 = 0x0001;
const IFF_NO_PI: u16 = 0x1000;

/// Creates the TUN interface; returns its fd and fills `name` with the name
/// the kernel gave it.
fn openTun(requested: []const u8, name: *[linux.IFNAMESIZE]u8) linux.fd_t {
    const fd: linux.fd_t = @intCast(checked(linux.openat(linux.AT.FDCWD, "/dev/net/tun", .{
        .ACCMODE = .RDWR,
        .NONBLOCK = true,
        .CLOEXEC = true,
    }, 0)) catch |err| fail("opening /dev/net/tun", err));
    var request: linux.ifreq = std.mem.zeroes(linux.ifreq);
    @memcpy(request.ifrn.name[0..requested.len], requested);
    request.ifru.flags = @bitCast(IFF_TUN | IFF_NO_PI);
    _ = checked(linux.ioctl(fd, TUNSETIFF, @intFromPtr(&request))) catch |err| fail("creating the TUN interface", err);
    name.* = request.ifrn.name;
    return fd;
}

/// Waits (polling every millisecond, as §11 asks) until the big core has
/// initialised both rings. SIGTERM still ends the helper meanwhile.
fn awaitRings(region: []align(8) u8, signals: linux.fd_t) void {
    while (!ring.Half.of(region, .a).valid() or !ring.Half.of(region, .b).valid()) {
        var polls = [_]linux.pollfd{.{ .fd = signals, .events = linux.POLL.IN, .revents = 0 }};
        _ = linux.poll(&polls, polls.len, 1);
        if (polls[0].revents != 0) handleSignals(signals, .{});
    }
}

// The loop's only buffers: one TUN packet and one ring frame.
var packet: [65536]u8 = undefined;
var frame: [ring.max_len]u8 = undefined;
/// Packets or frames moved per direction before the loop checks the other one.
const batch = 64;

fn bridge(tun: linux.fd_t, signals: linux.fd_t, writer: *ring.Writer, reader: *ring.Reader) noreturn {
    var stats: Stats = .{};
    while (true) {
        var polls = [_]linux.pollfd{
            .{ .fd = tun, .events = linux.POLL.IN, .revents = 0 },
            .{ .fd = signals, .events = linux.POLL.IN, .revents = 0 },
        };
        // At most 1 ms idle: the incoming ring has no wakeup of its own.
        const polled = linux.poll(&polls, polls.len, 1);
        if (linux.errno(polled) != .SUCCESS and linux.errno(polled) != .INTR) fail("poll", error.System);
        if (polls[1].revents != 0) handleSignals(signals, stats);
        if (polls[0].revents & (linux.POLL.ERR | linux.POLL.NVAL) != 0) fail("the TUN interface", error.Closed);

        for (0..batch) |_| {
            const rc = linux.read(tun, &packet, packet.len);
            switch (linux.errno(rc)) {
                .SUCCESS => {},
                .AGAIN, .INTR => break,
                else => fail("reading TUN", error.System),
            }
            if (rc == 0) break;
            // A full ring drops the packet; IP retransmits (§11).
            const outcome = writer.write(packet[0..rc]) catch .full;
            switch (outcome) {
                .ok => stats.tx += 1,
                .full => stats.full += 1,
            }
        }

        for (0..batch) |_| {
            switch (reader.read(&frame)) {
                .empty => break,
                .dropped => stats.dropped += 1,
                .frame => |incoming| {
                    // The kernel may refuse a frame that is not an IP packet;
                    // that is the peer's garbage, not a link failure.
                    const rc = linux.write(tun, incoming.payload.ptr, incoming.payload.len);
                    if (linux.errno(rc) == .SUCCESS) stats.rx += 1;
                },
            }
        }
    }
}

fn run(options: Options) noreturn {
    const signals = blockSignals();
    const region = mapRegion(options);
    switch (options.side) {
        .big => for ([_]ring.Direction{ .a, .b }) |direction| {
            _ = ring.Half.of(region, direction).prepare();
        },
        .little => awaitRings(region, signals),
    }
    var writer = ring.Writer.open(ring.Half.of(region, options.side.outgoing()));
    var reader = ring.Reader.open(ring.Half.of(region, options.side.incoming()));

    var name: [linux.IFNAMESIZE]u8 = undefined;
    const tun = openTun(options.tun, &name);
    const interface = std.mem.sliceTo(&name, 0);
    if (options.address) |requested| {
        var link = requested;
        link.interface = interface;
        netif.setLink(link) catch |err| fail("configuring the address", err);
    }
    var line: [96]u8 = undefined;
    say(upLine(&line, interface, options.size));
    bridge(tun, signals, &writer, &reader);
}

pub fn main(init: std.process.Init.Minimal) noreturn {
    var args: [16][:0]const u8 = undefined;
    var count: usize = 0;
    var it = std.process.Args.Iterator.init(init.args);
    _ = it.next();
    while (it.next()) |arg| {
        if (count == args.len) {
            say(usage);
            linux.exit_group(2);
        }
        args[count] = arg;
        count += 1;
    }
    const options = parseArgs(args[0..count]) orelse {
        say(usage);
        linux.exit_group(2);
    };
    run(options);
}

test "M31 elixos-link: arguments" {
    try milestone.require(31);
    const full = parseArgs(&.{
        "--region", "/dev/uio0", "--size", "1052672", "--offset",  "8192",
        "--tun",    "coproc0",   "--side", "little",  "--address", "10.9.0.2/30",
    }).?;
    try std.testing.expectEqualStrings("/dev/uio0", std.mem.span(full.region));
    try std.testing.expectEqual(@as(u64, 1052672), full.size);
    try std.testing.expectEqual(@as(u64, 8192), full.offset);
    try std.testing.expectEqualStrings("coproc0", full.tun);
    try std.testing.expectEqual(ring.Side.little, full.side);
    const address = full.address.?;
    try std.testing.expectEqual([4]u8{ 10, 9, 0, 2 }, address.address);
    try std.testing.expectEqual(@as(u6, 30), address.prefix);

    const minimal = parseArgs(&.{ "--tun", "tun0", "--size", "4096", "--region", "ring" }).?;
    try std.testing.expectEqual(ring.Side.big, minimal.side);
    try std.testing.expectEqual(@as(u64, 0), minimal.offset);
    try std.testing.expectEqual(@as(?cmdline.Link, null), minimal.address);

    const bad = [_][]const [:0]const u8{
        &.{},
        &.{ "--size", "4096", "--tun", "tun0" },
        &.{ "--region", "r", "--tun", "tun0" },
        &.{ "--region", "r", "--size", "4096" },
        &.{ "--region", "r", "--size", "4095", "--tun", "tun0" },
        &.{ "--region", "r", "--size", "04096", "--tun", "tun0" },
        &.{ "--region", "r", "--size", "4096", "--tun", "tun0", "--offset", "100" },
        &.{ "--region", "r", "--size", "4096", "--tun", "tun0", "--side", "middle" },
        &.{ "--region", "r", "--size", "4096", "--tun", "tun/0" },
        &.{ "--region", "r", "--size", "4096", "--tun", "a-name-far-too-long" },
        &.{ "--region", "r", "--size", "4096", "--tun", "tun0", "--address", "10.9.0.1" },
        &.{ "--region", "r", "--size", "4096", "--tun", "tun0", "--address", "10.9.0.256/30" },
        &.{ "--region", "r", "--size", "4096", "--tun", "tun0", "--tun", "tun1" },
        &.{ "--region", "r", "--size", "4096", "--tun", "tun0", "--verbose" },
        &.{ "--region", "r", "--size", "99999999999999999999", "--tun", "tun0" },
    };
    for (bad) |args| try std.testing.expectEqual(@as(?Options, null), parseArgs(args));
}

test "M31 elixos-link: its stderr lines are exact" {
    try milestone.require(31);
    var buffer: [160]u8 = undefined;
    try std.testing.expectEqualStrings(
        "elixos-link: up coproc0 region 1052672 bytes\n",
        upLine(&buffer, "coproc0", 1052672),
    );
    try std.testing.expectEqualStrings(
        "elixos-link: stats tx 1 rx 22 full 333 dropped 18446744073709551615\n",
        statsLine(&buffer, .{ .tx = 1, .rx = 22, .full = 333, .dropped = std.math.maxInt(u64) }),
    );
}
