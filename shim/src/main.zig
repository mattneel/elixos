//! Elixos PID 1 shim (ADR-002..004, docs/ARCHITECTURE.md §3).
//!
//! The kernel execs this binary as /init from the initramfs. It must never
//! exit: PID 1 exiting panics the kernel, which is why `main` is `noreturn`.
//!
//! Its jobs, built up over milestones M3..M8 (docs/ROADMAP.md):
//!
//!   1. Mount /proc, /sys, /dev (devtmpfs), /run and /tmp (tmpfs).
//!   2. Read /proc/cmdline -> cmdline.parse. Log the banner and invalid tokens.
//!   3. Mount the data device (elixos.data, ext4) on /data. Missing: rescue.
//!   4. Read /data/boot.state -> statefile.parse. Missing file: defaults.
//!      Corrupt file: rescue override, and never overwrite the evidence.
//!   5. recovery.planLaunch, persist next_state atomically, log the plan.
//!   6. Create the control pipe and exec ERTS (erlexec) for the planned
//!      generation with the environment contract in PROTOCOL.md §3.
//!   7. Event loop (epoll): signalfd for SIGCHLD/SIGTERM/SIGINT/SIGPWR;
//!      control lines -> protocol.parse -> recovery.applyMessage (persist on
//!      change); timerfd heartbeat deadline (boot_grace, then hb_timeout).
//!   8. Reap every child; PID 1 inherits orphans. On BEAM exit ->
//!      recovery.onBeamExit -> relaunch after a short backoff, or shut down.
//!   9. Shutdown: SIGTERM then SIGKILL stragglers, sync, unmount /data,
//!      reboot(2) with RESTART / POWER_OFF / HALT.
//!
//! Every console line it prints follows the log contract in PROTOCOL.md §6;
//! the QEMU tests match on those lines, so treat them as API.
//!
//! Prefer raw std.os.linux syscalls here. Allocate nothing after startup.
const std = @import("std");
const linux = std.os.linux;
const build_options = @import("build_options");

pub const milestone = @import("milestone.zig");
pub const decimal = @import("decimal.zig");
pub const protocol = @import("protocol.zig");
pub const statefile = @import("statefile.zig");
pub const cmdline = @import("cmdline.zig");
pub const recovery = @import("recovery.zig");

/// Printed in the banner: "elixos-shim: pid 1, version <version>".
pub const version = "0.0.0";

/// elixos.test.* hooks are compiled in only for QEMU test images (`-Dtest-hooks=true`).
pub const test_hooks = build_options.test_hooks;

// ADR-004 (M8): replace the default panic handler with one that re-execs
// /init in rescue mode instead of letting PID 1 die, e.g.
//
//   pub const panic = std.debug.FullPanic(rescuePanic);
//   fn rescuePanic(msg: []const u8, first_trace_addr: ?usize) noreturn { ... execve ... }
//
// Build its argv/envp at startup (BEAM pid, control fd) so the handler never
// allocates. execve keeps PID 1, and the BEAM stays our child across it.

/// PID 1's stdio: the kernel hands us /dev/console on fds 0, 1 and 2.
const console_fd: linux.fd_t = 1;

/// Every console line starts with this (PROTOCOL.md §6).
const log_prefix = "elixos-shim: ";

/// boot.state and the temp file it is written through (PROTOCOL.md §4).
const state_path = "/data/boot.state";
const state_tmp_path = "/data/boot.state.tmp";

/// The factory (generation 0) lives in the initramfs from M4 on.
const factory_path = "/factory";

pub fn main(init: std.process.Init.Minimal) noreturn {
    _ = init;
    log("pid 1, version " ++ version, .{});

    var overrides: recovery.Overrides = .{};

    // 1. The filesystems the rest of the boot needs. A missing one is not
    //    fatal: it only costs us /proc/cmdline or a place to mount /data.
    if (!mountBase()) overrides.safe = true;

    // 2. Kernel command line (PROTOCOL.md §5).
    var cmdline_buffer: [4096]u8 = undefined;
    const text: []const u8 = readFile("/proc/cmdline", &cmdline_buffer) catch "";
    const settings = cmdline.parse(text);
    if (settings.invalid > 0) log("ignored {d} invalid elixos.* parameters", .{settings.invalid});
    if (settings.safe) overrides.safe = true;

    // 3+4. /data and boot.state. The disk is mounted and read even when the
    //      safe override is set: rescue is "the factory with /data mounted"
    //      (ARCHITECTURE.md §4.5), and the plan must be computed from the real
    //      state. Persisting is a separate decision: only a plan that actually
    //      changes the state is written, which is what leaves the safe and
    //      generation overrides, and exhausted-rescue, untouched (ADR-006).
    var state: recovery.BootState = .{};
    var disk_mounted = false;
    if (mountData(settings.data_device)) {
        disk_mounted = true;
        if (readState(&state)) |_| {} else |err| switch (err) {
            // No file yet: the defaults mean "boot the factory, count it".
            error.FileNotFound => {},
            else => {
                log("state file unreadable ({t}), entering rescue", .{err});
                overrides.safe = true;
            },
        }
    } else {
        overrides.safe = true;
    }

    // 5. Plan, log it, persist it, then carry it out (ARCHITECTURE.md §3.3).
    const policy: recovery.Policy = .{ .max_attempts = settings.max_attempts };
    if (!overrides.safe) overrides.generation = settings.generation;

    if (!overrides.safe and overrides.generation == null and
        state.attempts >= policy.max_attempts and state.current != state.last_good)
    {
        log("fallback to last_good={d} after {d} attempts of generation={d}", .{
            state.last_good,
            state.attempts,
            state.current,
        });
    }

    const plan = recovery.planLaunch(state, policy, overrides);
    log("plan generation={d} mode={t} attempt={d}", .{
        plan.launch.generation,
        plan.launch.mode,
        plan.next_state.attempts,
    });
    // Persisted before the launch, so a crash, a hang or a power cut mid-boot
    // still counts. Only a plan that changes the state is written at all: the
    // safe and generation overrides, and an exhausted rescue, leave the file
    // exactly as they found it (ARCHITECTURE.md §3.3). A failed write only
    // risks over-counting attempts; the boot is not held hostage by the disk.
    if (disk_mounted and !std.meta.eql(plan.next_state, state)) writeState(plan.next_state);

    // Test hooks are compiled in for QEMU test images only (ADR-018).
    if (test_hooks and settings.test_stop_before_launch) {
        log("test hook stop_before_launch", .{});
        shutdown(.poweroff);
    }

    launch(plan);
}

// ---------------------------------------------------------------------------
// Boot steps

/// /proc, /sys, /dev, /run and /tmp. Returns false if any of them failed.
fn mountBase() bool {
    const Mount = struct {
        target: [*:0]const u8,
        fstype: [*:0]const u8,
        data: usize = 0,
    };
    const mounts = [_]Mount{
        .{ .target = "/proc", .fstype = "proc" },
        .{ .target = "/sys", .fstype = "sysfs" },
        .{ .target = "/dev", .fstype = "devtmpfs" },
        .{ .target = "/run", .fstype = "tmpfs", .data = @intFromPtr("mode=0755") },
        .{ .target = "/tmp", .fstype = "tmpfs", .data = @intFromPtr("mode=1777") },
    };
    var ok = true;
    for (mounts) |m| {
        const err = linux.errno(linux.mount(m.fstype, m.target, m.fstype, 0, m.data));
        if (err != .SUCCESS) {
            // Not fatal in itself: losing /proc only costs us the command line.
            var name_buffer: [16]u8 = undefined;
            log("cannot mount {s} ({s}), entering rescue", .{ m.target, errnoName(&name_buffer, err) });
            ok = false;
        }
    }
    return ok;
}

/// Mounts the data device on /data. Logs and returns false when it fails, so
/// the boot goes to the factory in rescue mode (PROTOCOL.md §6).
fn mountData(device: []const u8) bool {
    var buffer: [512]u8 = undefined;
    const path = std.mem.printSentinel(&buffer, "{s}", .{device}, 0) catch {
        log("cannot mount {s} (ENAMETOOLONG), entering rescue", .{device});
        return false;
    };
    const err = linux.errno(linux.mount(path.ptr, "/data", "ext4", 0, 0));
    if (err == .SUCCESS) return true;
    var name_buffer: [16]u8 = undefined;
    log("cannot mount {s} ({s}), entering rescue", .{ device, errnoName(&name_buffer, err) });
    return false;
}

/// Reads and parses /data/boot.state (PROTOCOL.md §4).
fn readState(state: *recovery.BootState) StateError!void {
    var buffer: [128]u8 = undefined;
    const text = try readFile(state_path, &buffer);
    state.* = try statefile.parse(text);
}

/// Write boot.state.tmp, fsync it, rename it over boot.state, fsync /data
/// (PROTOCOL.md §4). Every failure leaves the old file in place.
fn writeState(state: recovery.BootState) void {
    var buffer: [statefile.max_len]u8 = undefined;
    const text = statefile.encode(state, &buffer) catch return;
    writeFileAtomic(state_path, state_tmp_path, text);
}

/// 6. The launch. M4 turns this into fork + exec of ERTS (PROTOCOL.md §3).
fn launch(plan: recovery.Plan) noreturn {
    if (!pathExists(factory_path)) {
        // Until M4 the factory image does not exist: there is nothing to run.
        log("factory missing, powering off", .{});
        shutdown(.poweroff);
    }
    log("launching generation={d} mode={t}", .{ plan.launch.generation, plan.launch.mode });
    @panic("TODO(M4): fork + exec erlexec for the plan");
}

/// 9. Shutdown. PID 1 does not exit (ADR-002); the kernel powers the machine
/// off, reboots or halts, and if it refuses we idle forever.
fn shutdown(kind: recovery.Shutdown) noreturn {
    linux.sync();
    _ = linux.umount2("/data", 0);
    log("shutdown {t}", .{kind});
    const cmd: linux.LINUX_REBOOT.CMD = switch (kind) {
        .reboot => .RESTART,
        .poweroff => .POWER_OFF,
        .halt => .HALT,
    };
    _ = linux.reboot(.MAGIC1, .MAGIC2, cmd, null);
    while (true) _ = linux.pause();
}

// ---------------------------------------------------------------------------
// Syscall helpers. Raw std.os.linux, no allocation.

/// One console line: `elixos-shim: <text>\n` (PROTOCOL.md §6).
///
/// The buffer holds the longest message the shim can produce: the device name
/// in a mount failure is capped at 512 bytes by mountData, and the prefix, the
/// errno name and the trailing text fit in the rest.
fn log(comptime fmt: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, log_prefix ++ fmt ++ "\n", args) catch return;
    _ = writeAll(console_fd, line);
}

fn writeAll(fd: linux.fd_t, bytes: []const u8) bool {
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = linux.write(fd, bytes.ptr + written, bytes.len - written);
        if (linux.errno(rc) != .SUCCESS or rc == 0) return false;
        written += rc;
    }
    return true;
}

/// The conventional name of a syscall error: `.NOENT` prints as `ENOENT`, the
/// spelling PROTOCOL.md §6 uses. Parsers report Zig error names unchanged.
fn errnoName(buffer: []u8, err: linux.E) []const u8 {
    return std.fmt.bufPrint(buffer, "E{t}", .{err}) catch "EUNKNOWN";
}

fn readFile(path: [*:0]const u8, buffer: []u8) ReadError![]u8 {
    const raw_fd = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    const open_err = linux.errno(raw_fd);
    if (open_err != .SUCCESS) {
        return if (open_err == .NOENT) error.FileNotFound else error.ReadFailed;
    }
    const fd: linux.fd_t = @intCast(raw_fd);
    defer _ = linux.close(fd);

    var length: usize = 0;
    while (length < buffer.len) {
        const rc = linux.read(fd, buffer.ptr + length, buffer.len - length);
        if (linux.errno(rc) != .SUCCESS) return error.ReadFailed;
        if (rc == 0) return buffer[0..length];
        length += rc;
    }
    // Too long to be the file we expect: never guess at a prefix of it.
    return error.TooLong;
}

fn writeFileAtomic(final_path: [*:0]const u8, tmp_path: [*:0]const u8, bytes: []const u8) void {
    const raw_fd = linux.open(tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (linux.errno(raw_fd) != .SUCCESS) return;
    const fd: linux.fd_t = @intCast(raw_fd);
    const complete = writeAll(fd, bytes) and linux.errno(linux.fsync(fd)) == .SUCCESS;
    _ = linux.close(fd);

    // Never rename an incomplete or unsynced temporary file over the real one:
    // the whole point of the temp file is that a failure keeps the old state.
    if (!complete) return;
    if (linux.errno(linux.rename(tmp_path, final_path)) != .SUCCESS) return;

    // fsync the directory as well, so the rename itself is durable.
    const raw_dir = linux.open("/data", .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
    if (linux.errno(raw_dir) != .SUCCESS) return;
    const dir: linux.fd_t = @intCast(raw_dir);
    _ = linux.fsync(dir);
    _ = linux.close(dir);
}

fn pathExists(path: [*:0]const u8) bool {
    const raw_fd = linux.open(path, .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
    if (linux.errno(raw_fd) != .SUCCESS) return false;
    _ = linux.close(@intCast(raw_fd));
    return true;
}

/// readFile's errors, plus the state file's own parse errors.
const ReadError = error{ FileNotFound, ReadFailed, TooLong };
const StateError = ReadError || statefile.ParseError;

test {
    // Zig only analyzes what is referenced, so broken code can compile "clean"
    // (AGENTS.md §Zig). This pulls every shim file through semantic analysis
    // and collects their tests.
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(decimal);
    std.testing.refAllDecls(protocol);
    std.testing.refAllDecls(statefile);
    std.testing.refAllDecls(cmdline);
    std.testing.refAllDecls(recovery);
}
