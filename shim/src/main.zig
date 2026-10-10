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
/// The factory's ERTS and release carry version numbers; the factory build
/// points these two paths at them (`erts` and `releases/current`).
const erlexec_path = factory_path ++ "/erts/bin/erlexec";
const bindir_path = factory_path ++ "/erts/bin";
const boot_path = factory_path ++ "/releases/current/start";
const sys_config_path = factory_path ++ "/releases/current/sys.config";
/// Where the generation's code lives: `$ROOT/lib`, see the boot script.
const lib_path = factory_path ++ "/lib";

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
    if (mountData(settings.data_device, settings.data_wait_s)) {
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

    launch(plan, settings, disk_mounted);
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
            var name_buffer: [24]u8 = undefined;
            log("cannot mount {s} ({s}), entering rescue", .{ m.target, errnoName(&name_buffer, err) });
            ok = false;
        }
    }
    return ok;
}

/// Mounts the data device on /data, waiting for it to appear first (see
/// `Settings.data_wait_s`: the kernel starts /init without waiting for USB or
/// SD storage, so on real hardware the device may not exist yet). Logs and
/// returns false when it fails, so the boot goes to the factory in rescue
/// mode (PROTOCOL.md §6).
fn mountData(device: []const u8, wait_s: u32) bool {
    var buffer: [512]u8 = undefined;
    const path = std.mem.printSentinel(&buffer, "{s}", .{device}, 0) catch {
        log("cannot mount {s} (ENAMETOOLONG), entering rescue", .{device});
        return false;
    };

    var remaining: u32 = wait_s *| 10; // tenths of a second
    while (true) {
        const err = linux.errno(linux.mount(path.ptr, "/data", "ext4", 0, 0));
        if (err == .SUCCESS) return true;
        // Only "there is no such device yet" is worth waiting for: anything
        // else (a bad filesystem, a wrong device) will not fix itself.
        if (err != .NOENT or remaining == 0) {
            var name_buffer: [24]u8 = undefined;
            log("cannot mount {s} ({s}), entering rescue", .{ device, errnoName(&name_buffer, err) });
            return false;
        }
        if (remaining == wait_s *| 10) log("waiting for {s} up to {d}s", .{ device, wait_s });
        sleepMs(100);
        remaining -= 1;
    }
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

/// 6. Launch the planned generation: the factory's ERTS, as our child, with
///    the control pipe and the environment contract of PROTOCOL.md §3. PID 1
///    stays PID 1, so a crashed or hung BEAM stays observable (ADR-002).
fn launch(plan: recovery.Plan, settings: cmdline.Settings, disk_mounted: bool) noreturn {
    if (!pathExists(factory_path)) {
        log("factory missing, powering off", .{});
        shutdown(.poweroff);
    }

    // The control channel (PROTOCOL.md §2). The BEAM holds the write end, we
    // hold the read end: the write end must survive exec, the read end must
    // not, or EOF would never arrive when the BEAM exits.
    var pipe_fds: [2]linux.fd_t = undefined;
    if (linux.errno(linux.pipe2(&pipe_fds, .{})) != .SUCCESS) {
        log("cannot create the control pipe, powering off", .{});
        shutdown(.poweroff);
    }
    _ = linux.fcntl(pipe_fds[0], linux.F.SETFD, linux.FD_CLOEXEC);

    const child = linux.fork();
    if (linux.errno(child) != .SUCCESS) {
        log("cannot fork, powering off", .{});
        shutdown(.poweroff);
    }
    if (child == 0) execErts(plan, pipe_fds[1]);

    _ = linux.close(pipe_fds[1]);
    supervise(@intCast(child), pipe_fds[0], plan, settings, disk_mounted);
}

/// The child's half of the launch: log, set up argv/envp, exec. Only returns
/// by way of exit_group: PID 1's child must not fall back into the shim.
fn execErts(plan: recovery.Plan, ctl_fd: linux.fd_t) noreturn {
    var generation: [32]u8 = undefined;
    var attempt: [32]u8 = undefined;
    var control: [32]u8 = undefined;
    var mode: [32]u8 = undefined;

    // erlexec takes $ROOTDIR and $BINDIR from the environment (below) and
    // passes -root/-bindir to ERTS itself: repeating them here makes ERTS
    // exit with "no_or_multiple_root_variables". The boot script resolves its
    // $ROOT against that -root and its $RELEASE_LIB against the boot_var.
    const argv = [_]?[*:0]const u8{
        "erlexec",
        "-boot",     boot_path,
        "-boot_var", "RELEASE_LIB", lib_path,
        "-config",   sys_config_path,
        "-mode",     "embedded",
        // No shell at boot: the login REPL asks user_drv for one when the
        // application is up (ADR-012), so the prompt never races the boot.
        "-noshell",
        null,
    };
    const envp = [_]?[*:0]const u8{
        "ROOTDIR=" ++ factory_path,
        "BINDIR=" ++ bindir_path,
        "EMU=beam",
        "PROGNAME=erl",
        "HOME=/data/home",
        "TERM=linux",
        "LANG=C.UTF-8",
        zeroed(&generation, "ELIXOS_GENERATION={d}", .{plan.launch.generation}),
        zeroed(&mode, "ELIXOS_MODE={t}", .{plan.launch.mode}),
        zeroed(&attempt, "ELIXOS_ATTEMPT={d}", .{plan.next_state.attempts}),
        zeroed(&control, "ELIXOS_CTL_FD={d}", .{ctl_fd}),
        null,
    };

    log("launching generation={d} mode={t}", .{ plan.launch.generation, plan.launch.mode });
    _ = linux.execve(erlexec_path, @ptrCast(&argv), @ptrCast(&envp));
    // execve only returns on failure. Say why we are going away, and let the
    // shim count the attempt (ADR-007) instead of leaving a zombie half-boot.
    log("cannot exec {s}, exiting", .{erlexec_path});
    _ = linux.exit_group(1);
}

/// Formats into `buffer` and NUL-terminates it. The buffers are sized for the
/// widest value each holds, so a failure can only mean a bug: exit loudly.
fn zeroed(buffer: []u8, comptime fmt: []const u8, args: anytype) [*:0]const u8 {
    const text = std.mem.printSentinel(buffer, fmt, args, 0) catch {
        log("cannot format the launch environment, exiting", .{});
        _ = linux.exit_group(1);
    };
    return text.ptr;
}

/// Watches the BEAM: its control lines, and its exit. M5 adds the heartbeat
/// deadline, signals and the relaunch policy; M4 can only carry out a
/// requested shutdown.
fn supervise(
    beam: linux.pid_t,
    ctl_fd: linux.fd_t,
    plan: recovery.Plan,
    settings: cmdline.Settings,
    disk_mounted: bool,
) noreturn {
    _ = settings; // the heartbeat deadline arrives with M5
    var state = plan.next_state;
    var requested: ?recovery.Shutdown = null;
    var buffer: [protocol.max_line_len * 2]u8 = undefined;
    var pending: usize = 0;
    var control_open = true;
    var exit_status: ?u32 = null;

    while (true) {
        if (control_open) {
            const rc = linux.read(ctl_fd, buffer[0..].ptr + pending, buffer.len - pending);
            const err = linux.errno(rc);
            if (err == .SUCCESS) {
                if (rc == 0) {
                    // EOF: every write end is closed, so the BEAM is gone.
                    control_open = false;
                } else {
                    pending += rc;
                    if (consumeLines(&state, &buffer, &pending, &requested) and disk_mounted) {
                        writeState(state);
                    }
                    if (pending == buffer.len) {
                        // A line that does not fit cannot be valid
                        // (PROTOCOL.md §2): discard it and keep reading.
                        log("ignored control line (TooLong)", .{});
                        pending = 0;
                    }
                }
            } else if (err != .INTR) {
                control_open = false;
            }
        }

        if (exit_status == null) {
            var status: i32 = 0;
            const rc = linux.wait4(beam, &status, linux.W.NOHANG, null);
            if (linux.errno(rc) == .SUCCESS and rc != 0) exit_status = @bitCast(status);
        }
        if (exit_status != null and !control_open) break;
    }

    if (exit_status) |status| logBeamExit(status);
    if (requested) |kind| shutdown(kind);

    // An exit nobody asked for cannot be recovered yet: M5 relaunches through
    // recovery.onBeamExit with a backoff (ADR-007). Until then, power off
    // cleanly rather than limp on.
    shutdown(.poweroff);
}

/// Applies every complete control line in `buffer`, keeps any unfinished tail,
/// and returns whether the state changed (so the caller persists it).
fn consumeLines(
    state: *recovery.BootState,
    buffer: []u8,
    pending: *usize,
    requested: *?recovery.Shutdown,
) bool {
    var changed = false;
    var start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, buffer[0..pending.*], start, '\n')) |newline| {
        const line = buffer[start..newline];
        start = newline + 1;

        // PROTOCOL.md §2: a line that is not exactly a message is logged and
        // ignored, never fatal.
        const message = protocol.parse(line) catch |err| {
            log("ignored control line ({t})", .{err});
            continue;
        };
        const outcome = recovery.applyMessage(state.*, message);
        if (!std.meta.eql(outcome.state, state.*)) {
            state.* = outcome.state;
            changed = true;
        }
        if (outcome.shutdown) |kind| requested.* = kind;
    }

    const remaining = pending.* - start;
    if (remaining > 0) std.mem.copyForwards(u8, buffer[0..remaining], buffer[start..pending.*]);
    pending.* = remaining;
    return changed;
}

/// PROTOCOL.md §6: how the BEAM went away.
fn logBeamExit(status: u32) void {
    if (linux.W.IFEXITED(status)) {
        log("beam exited status={d}", .{linux.W.EXITSTATUS(status)});
    } else if (linux.W.IFSIGNALED(status)) {
        log("beam killed by signal {d}", .{@intFromEnum(linux.W.TERMSIG(status))});
    }
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
/// spelling PROTOCOL.md §6 uses. `linux.E` is non-exhaustive and formatting an
/// unnamed value with `{t}` panics: PID 1 must have no panic path (ADR-002),
/// so an unnamed errno prints as its number instead. Parsers keep reporting
/// Zig error names unchanged.
fn errnoName(buffer: []u8, err: linux.E) []const u8 {
    const name = std.enums.tagName(linux.E, err) orelse
        return std.fmt.bufPrint(buffer, "errno {d}", .{@intFromEnum(err)}) catch "errno ?";
    return std.fmt.bufPrint(buffer, "E{s}", .{name}) catch "E?";
}

/// A bounded sleep. Used only while waiting for a device that may still be
/// probing; nothing else in the shim sleeps.
fn sleepMs(ms: u32) void {
    const request: linux.timespec = .{
        .sec = @intCast(ms / 1000),
        .nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
    };
    _ = linux.nanosleep(&request, null);
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
