//! The inter-core ring at boot (M33, docs/PROTOCOL.md §5 and §11): the
//! shim-side parameter `elixos.coproc_ring=<spec>` and the process that keeps
//! `elixos-link` running on it.
//!
//! On the board the coprocessor has no NIC: its link is `elixos-link` over the
//! UIO region the device tree names `coproc-ring`. The shim resolves the spec
//! as it does `elixos.deck` (deck.zig), then forks a *keeper* before the
//! BEAM starts. The keeper runs the helper and starts it again with a backoff
//! whenever it exits; it is a separate process, so PID 1's event loop, its
//! panic re-exec (ADR-004) and the BEAM's restarts never touch the link.
//!
//! One convention for the address: the TUN interface is the one
//! `elixos.coproc_link` names (default `coproc0`), and its address goes to the
//! helper as `--address`, so every restart of the helper configures the
//! interface it re-creates. The shim does not configure that interface
//! itself; it waits (bounded) for the helper to bring it up and then logs
//! the usual `coproc link` line.
const std = @import("std");
const linux = std.os.linux;
const milestone = @import("milestone.zig");
const cmdline = @import("cmdline.zig");
const deck = @import("deck.zig");

pub const helper_path = "/usr/bin/elixos-link";
/// The board's region (docs/notes/k230.md): 2 x 64 KiB rings + 4096.
pub const region_size: u32 = 0x21000;
/// The interface when `elixos.coproc_link` names none.
pub const default_interface = "coproc0";
/// How long the shim waits for the helper to bring the interface up.
pub const ready_timeout_ms: u32 = 5_000;
pub const ready_poll_ms: u32 = 10;

/// `uio:<name>` or `/dev/<path>`, parsed as `elixos.deck`'s spec (§5).
/// `pci:` is refused: QEMU's ivshmem devices all share one vendor and device
/// id, so "the first match" could be the deck's framebuffer.
pub fn parseSpec(value: ?[]const u8) ?deck.Spec {
    const spec = deck.parseSpec(value) orelse return null;
    return if (spec.target == .pci) null else spec;
}

// ---------------------------------------------------------------------------
// Console lines (§6). The keeper and main.zig format them through these.

pub const started_line = "coproc ring {s}";
pub const failed_line = "coproc ring {s} failed ({t})";
pub const exited_line = "coproc ring exited status={d}, restarting in {d}ms";
pub const killed_line = "coproc ring killed by signal {d}, restarting in {d}ms";
pub const fork_failed_line = "coproc ring cannot fork, restarting in {d}ms";

// ---------------------------------------------------------------------------
// The helper's command line.

/// `elixos-link --region <path> --size 135168 --tun <if> --side big
/// [--address <ip>/<len>]`, in fixed buffers: built once, before the fork.
pub const Command = struct {
    region: [deck.max_path + 1]u8 = undefined,
    interface: [16]u8 = undefined,
    address: ["255.255.255.255/32".len + 1]u8 = undefined,
    argv: [12:null]?[*:0]const u8 = @splat(null),

    pub fn init(self: *Command, region: []const u8, link: ?cmdline.Link) error{NoSpaceLeft}!void {
        const interface = if (link) |l| l.interface else default_interface;
        var n: usize = 0;
        const put = struct {
            fn put(argv: *[12:null]?[*:0]const u8, i: *usize, arg: [*:0]const u8) void {
                argv[i.*] = arg;
                i.* += 1;
            }
        }.put;
        put(&self.argv, &n, helper_path);
        put(&self.argv, &n, "--region");
        put(&self.argv, &n, (try std.fmt.bufPrintSentinel(&self.region, "{s}", .{region}, 0)).ptr);
        put(&self.argv, &n, "--size");
        put(&self.argv, &n, std.fmt.comptimePrint("{d}", .{region_size}));
        put(&self.argv, &n, "--tun");
        put(&self.argv, &n, (try std.fmt.bufPrintSentinel(&self.interface, "{s}", .{interface}, 0)).ptr);
        put(&self.argv, &n, "--side");
        put(&self.argv, &n, "big");
        if (link) |l| {
            const a = l.address;
            put(&self.argv, &n, "--address");
            put(&self.argv, &n, (try std.fmt.bufPrintSentinel(&self.address, "{d}.{d}.{d}.{d}/{d}", .{ a[0], a[1], a[2], a[3], l.prefix }, 0)).ptr);
        }
        while (n < self.argv.len) : (n += 1) self.argv[n] = null;
    }

    pub fn interfaceName(self: *const Command) []const u8 {
        return std.mem.sliceTo(&self.interface, 0);
    }
};

// ---------------------------------------------------------------------------
// Restart policy.

pub const first_delay_ms: u32 = 1_000;
pub const max_delay_ms: u32 = 30_000;
/// A helper that ran this long counts as healthy: the next delay starts over.
pub const healthy_ms: u64 = 60_000;

/// The delay before the next start: 1 s, doubling to 30 s while the helper
/// keeps failing, back to 1 s after it ran for a minute.
pub fn nextDelayMs(previous: u32, ran_ms: u64) u32 {
    if (previous == 0 or ran_ms >= healthy_ms) return first_delay_ms;
    return @min(previous *| 2, max_delay_ms);
}

// ---------------------------------------------------------------------------
// The keeper: a child of PID 1, never returns.

const sig_block: u32 = 0;
const sig_setmask: u32 = 2;

fn monotonicMs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / std.time.ns_per_ms;
}

/// Runs `command` for ever. `log` is main.zig's console logger. SIGTERM or
/// SIGINT (the shutdown's straggler signal) stops the helper and ends the
/// keeper; a helper that exits is started again after `nextDelayMs`.
pub fn keep(command: *const Command, comptime log: anytype) noreturn {
    var mask = linux.sigemptyset();
    for ([_]linux.SIG{ .CHLD, .TERM, .INT }) |signal| linux.sigaddset(&mask, signal);
    // Exactly these blocked: PID 1's mask is not this process's business.
    _ = linux.sigprocmask(sig_setmask, &mask, null);
    const raw = linux.signalfd(-1, &mask, linux.SFD.CLOEXEC);
    if (linux.errno(raw) != .SUCCESS) linux.exit_group(1);
    const signals: linux.fd_t = @intCast(raw);
    _ = linux.prctl(@backingInt(linux.PR.SET_NAME), @intFromPtr("elixos-ring"), 0, 0, 0);

    const empty_env = [_:null]?[*:0]const u8{};
    var delay: u32 = 0;
    while (true) {
        const started = monotonicMs();
        const child = linux.fork();
        if (linux.errno(child) != .SUCCESS) {
            delay = nextDelayMs(delay, 0);
            log(fork_failed_line, .{delay});
            pause(signals, delay, 0);
            continue;
        }
        if (child == 0) {
            const none = linux.sigemptyset();
            _ = linux.sigprocmask(sig_setmask, &none, null);
            _ = linux.execve(helper_path, @ptrCast(&command.argv), &empty_env);
            linux.exit_group(127);
        }
        const pid: linux.pid_t = @intCast(child);
        const status = waitHelper(signals, pid);
        delay = nextDelayMs(delay, monotonicMs() - started);
        if (linux.W.IFSIGNALED(status)) {
            log(killed_line, .{ @backingInt(linux.W.TERMSIG(status)), delay });
        } else {
            log(exited_line, .{ linux.W.EXITSTATUS(status), delay });
        }
        pause(signals, delay, 0);
    }
}

/// Blocks until the helper exits and returns its wait status. A shutdown
/// signal stops it first and ends the keeper.
fn waitHelper(signals: linux.fd_t, pid: linux.pid_t) u32 {
    while (true) {
        var status: i32 = 0;
        const rc = linux.wait4(pid, &status, linux.W.NOHANG, null);
        if (linux.errno(rc) == .SUCCESS and rc == pid) return @bitCast(status);
        if (linux.errno(rc) == .CHILD) return 0;
        pause(signals, 0, pid);
    }
}

/// Waits for a signal, at most `ms` milliseconds (0: until one arrives).
/// SIGTERM or SIGINT end the keeper, stopping `helper` (if not 0) first.
fn pause(signals: linux.fd_t, ms: u32, helper: linux.pid_t) void {
    const deadline = monotonicMs() + ms;
    while (true) {
        const left: i32 = if (ms == 0) -1 else @intCast(@min(deadline -| monotonicMs(), std.math.maxInt(i32)));
        if (ms != 0 and left == 0) return;
        var polls = [_]linux.pollfd{.{ .fd = signals, .events = linux.POLL.IN, .revents = 0 }};
        const ready = linux.poll(&polls, polls.len, left);
        if (linux.errno(ready) != .SUCCESS or ready == 0) continue;
        var info: linux.signalfd_siginfo = undefined;
        const n = linux.read(signals, @ptrCast(&info), @sizeOf(linux.signalfd_siginfo));
        if (linux.errno(n) != .SUCCESS or n != @sizeOf(linux.signalfd_siginfo)) continue;
        if (info.signo == @backingInt(linux.SIG.CHLD)) {
            if (ms == 0) return;
            continue;
        }
        // SIGTERM or SIGINT: the machine is shutting down.
        if (helper != 0) {
            _ = linux.kill(helper, .TERM);
            var status: i32 = 0;
            _ = linux.wait4(helper, &status, 0, null);
        }
        linux.exit_group(0);
    }
}

// ---------------------------------------------------------------------------

test "M33 coproc ring: elixos.coproc_ring specs" {
    try milestone.require(33);
    try std.testing.expectEqualStrings("coproc-ring", parseSpec("uio:coproc-ring").?.target.uio);
    try std.testing.expectEqualStrings("/dev/uio1", parseSpec("/dev/uio1").?.target.path);
    try std.testing.expectEqualStrings("uio:coproc-ring", parseSpec("uio:coproc-ring").?.text);
    for ([_][]const u8{ "", "uio:", "uio:a b", "pci:0x1af4:0x1110", "/dev/../x", "coproc-ring" }) |bad| {
        if (parseSpec(bad) != null) {
            std.debug.print("accepted {s}\n", .{bad});
            return error.TestUnexpectedSpec;
        }
    }
    try std.testing.expect(parseSpec(null) == null);
}

fn expectArgv(command: *const Command, expected: []const []const u8) !void {
    for (expected, 0..) |arg, i| try std.testing.expectEqualStrings(arg, std.mem.span(command.argv[i].?));
    try std.testing.expect(command.argv[expected.len] == null);
}

test "M33 coproc ring: the helper's command line" {
    try milestone.require(33);
    var command: Command = .{};
    try command.init("/dev/uio0", .{ .interface = "coproc0", .address = .{ 10, 0, 3, 15 }, .prefix = 24 });
    try expectArgv(&command, &.{
        "/usr/bin/elixos-link", "--region", "/dev/uio0", "--size", "135168",
        "--tun",                "coproc0",  "--side",    "big",    "--address",
        "10.0.3.15/24",
    });
    try std.testing.expectEqualStrings("coproc0", command.interfaceName());
    // Without elixos.coproc_link: coproc0, created and left down.
    try command.init("/dev/uio3", null);
    try expectArgv(&command, &.{
        "/usr/bin/elixos-link", "--region", "/dev/uio3", "--size", "135168", "--tun", "coproc0", "--side", "big",
    });
    // The widest address fits.
    try command.init("/dev/uio0", .{ .interface = "abcdefghijklmno", .address = .{ 255, 255, 255, 255 }, .prefix = 32 });
    try std.testing.expectEqualStrings("255.255.255.255/32", std.mem.span(command.argv[10].?));
    try std.testing.expectEqualStrings("abcdefghijklmno", command.interfaceName());
}

test "M33 coproc ring: restart backoff" {
    try milestone.require(33);
    try std.testing.expectEqual(@as(u32, 1_000), nextDelayMs(0, 0));
    try std.testing.expectEqual(@as(u32, 2_000), nextDelayMs(1_000, 10));
    try std.testing.expectEqual(@as(u32, 16_000), nextDelayMs(8_000, 59_999));
    try std.testing.expectEqual(@as(u32, 30_000), nextDelayMs(16_000, 0));
    try std.testing.expectEqual(@as(u32, 30_000), nextDelayMs(30_000, 0));
    try std.testing.expectEqual(@as(u32, 1_000), nextDelayMs(30_000, 60_000));
}

test "M33 coproc ring: console lines are byte-exact (PROTOCOL.md §6)" {
    try milestone.require(33);
    var buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings("coproc ring /dev/uio0", try std.fmt.bufPrint(&buffer, started_line, .{"/dev/uio0"}));
    try std.testing.expectEqualStrings(
        "coproc ring uio:coproc-ring failed (NotFound)",
        try std.fmt.bufPrint(&buffer, failed_line, .{ "uio:coproc-ring", error.NotFound }),
    );
    try std.testing.expectEqualStrings(
        "coproc ring exited status=1, restarting in 2000ms",
        try std.fmt.bufPrint(&buffer, exited_line, .{ 1, 2000 }),
    );
    try std.testing.expectEqualStrings(
        "coproc ring killed by signal 9, restarting in 1000ms",
        try std.fmt.bufPrint(&buffer, killed_line, .{ 9, 1000 }),
    );
    try std.testing.expectEqualStrings(
        "coproc ring cannot fork, restarting in 4000ms",
        try std.fmt.bufPrint(&buffer, fork_failed_line, .{4000}),
    );
}
