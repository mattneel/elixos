//! Elixos PID 1 shim (ADR-002..004, docs/ARCHITECTURE.md §3).
//!
//! The kernel execs this binary as /init from the initramfs. It must never
//! exit: PID 1 exiting panics the kernel, which is why `main` is `noreturn`.
//!
//! Its jobs, built up over milestones M3..M8 (docs/ROADMAP.md):
//!
//!   1. Mount /proc, /sys, /dev (devtmpfs), /run and /tmp (tmpfs).
//!   2. Read /proc/cmdline -> cmdline.parse. Log the banner and invalid tokens.
//!   3. Mount the data device (elixos.data, ext4) on /priv. Missing: rescue.
//!   4. Read /priv/boot.state -> statefile.parse. Missing file: defaults.
//!      Corrupt file: rescue override, and never overwrite the evidence.
//!   5. recovery.planLaunch, persist next_state atomically, log the plan.
//!   6. Create the control pipe and exec ERTS (erlexec) for the planned
//!      generation with the environment contract in PROTOCOL.md §3.
//!   7. Event loop (epoll): signalfd for SIGCHLD/SIGTERM/SIGINT/SIGPWR;
//!      control lines -> protocol.parse -> recovery.applyMessage (persist on
//!      change); timerfd heartbeat deadline (boot_grace, then hb_timeout).
//!   8. Reap every child; PID 1 inherits orphans. On BEAM exit ->
//!      recovery.onBeamExit -> relaunch after a short backoff, or shut down.
//!   9. Shutdown: SIGTERM then SIGKILL stragglers, sync, unmount /priv,
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

// ADR-004 (M8): PID 1 must not die of its own panic. The handler re-execs
// this same binary, which then ADOPTS the BEAM it is told about: execve keeps
// PID 1, so the BEAM stays this process's child (wait4 still works) and its
// session never notices. Everything the handler needs - the new argv carrying
// the BEAM's pid and control fd - is formatted while that BEAM is spawned,
// because the panic path allocates nothing and must not fail.
const init_path = "/init";

const rescue = struct {
    var pid_text: [24]u8 = undefined;
    var ctl_text: [24]u8 = undefined;
    /// { init, "--adopt", <pid>, <control fd>, <safe>, <mounted>, <request>, null }
    var argv: [8:null]?[*:0]const u8 = .{ null, null, null, null, null, null, null, null };
    /// The kernel gives PID 1 no environment; the new shim needs none either.
    var envp: [1:null]?[*:0]const u8 = .{null};

    const Adopted = struct {
        beam_pid: linux.pid_t,
        ctl_fd: linux.fd_t,
        /// The *effective* decisions of the boot that panicked. Rescue may
        /// have come from an unreadable state file or a missing disk, which
        /// the adopted shim cannot re-derive, and a shutdown request already
        /// read off the control pipe cannot be replayed.
        safe: bool,
        disk_mounted: bool,
        requested: ?recovery.Shutdown,
    };

    const yes = "1";
    const no = "0";

    fn requestName(requested: ?recovery.Shutdown) [*:0]const u8 {
        if (requested) |kind| switch (kind) {
            .reboot => return "reboot",
            .poweroff => return "poweroff",
            .halt => return "halt",
        };
        return "none";
    }

    fn requestOf(name: []const u8) ?recovery.Shutdown {
        if (std.mem.eql(u8, name, "reboot")) return .reboot;
        if (std.mem.eql(u8, name, "poweroff")) return .poweroff;
        if (std.mem.eql(u8, name, "halt")) return .halt;
        return null;
    }

    /// Called after every spawn (a relaunch means a new pid) and whenever a
    /// decision it carries changes, because this is what the panic handler
    /// execs with.
    fn arm(
        beam_pid: linux.pid_t,
        ctl_fd: linux.fd_t,
        safe: bool,
        disk_mounted: bool,
        requested: ?recovery.Shutdown,
    ) void {
        argv = .{
            init_path,
            "--adopt",
            zeroed(&pid_text, "{d}", .{beam_pid}),
            zeroed(&ctl_text, "{d}", .{ctl_fd}),
            if (safe) yes else no,
            if (disk_mounted) yes else no,
            requestName(requested),
            null,
        };
    }

    /// The adoption request in our own command line:
    /// `--adopt <pid> <fd> <safe> <mounted> <request>`.
    fn parse(args: []const []const u8) ?Adopted {
        // init, --adopt, pid, fd, safe, mounted, request.
        if (args.len < 7) return null;
        if (!std.mem.eql(u8, args[1], "--adopt")) return null;
        const pid = std.fmt.parseInt(linux.pid_t, args[2], 10) catch return null;
        const fd = std.fmt.parseInt(linux.fd_t, args[3], 10) catch return null;
        return .{
            .beam_pid = pid,
            .ctl_fd = fd,
            .safe = args[4][0] == '1',
            .disk_mounted = args[5][0] == '1',
            .requested = requestOf(args[6]),
        };
    }
};

pub const panic = std.debug.FullPanic(rescuePanic);

/// The panic handler (ADR-004): say what happened, then become /init again
/// with the BEAM's pid and control fd on the new command line.
fn rescuePanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;

    // No BEAM to adopt: the panic happened before one existed, and there is
    // nothing to rescue. `shutdown` says what it does (PROTOCOL.md §6).
    if (rescue.argv[0] == null) shutdown(.poweroff);

    log("re-exec after panic: {s}", .{msg});
    _ = linux.execve(init_path, @ptrCast(&rescue.argv), @ptrCast(&rescue.envp));

    // Nothing left to trust, and the re-exec did not work: stop the machine.
    shutdown(.poweroff);
}

/// Milliseconds on CLOCK_MONOTONIC: only the test hook needs a clock.
fn monotonicMs() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), std.time.ns_per_ms);
}

/// The shim's own command line, as a slice: the adoption request lives there.
fn ownArgs(init: std.process.Init.Minimal, buffer: *[8][]const u8) []const []const u8 {
    var count: usize = 0;
    var it = std.process.Args.Iterator.init(init.args);
    while (it.next()) |arg| {
        if (count == buffer.len) break;
        buffer[count] = arg;
        count += 1;
    }

    return buffer[0..count];
}

/// PID 1's stdio: the kernel hands us /dev/console on fds 0, 1 and 2.
const console_fd: linux.fd_t = 1;

/// Every console line starts with this (PROTOCOL.md §6).
const log_prefix = "elixos-shim: ";

/// boot.state and the temp file it is written through (PROTOCOL.md §4).
const state_path = "/priv/boot.state";
const state_tmp_path = "/priv/boot.state.tmp";

/// Crash dumps (PROTOCOL.md §7): ERTS writes them where the shim points
/// ERL_CRASH_DUMP, on the persistent disk, so the evidence of why a
/// generation failed survives the reboot that falls back from it.
const crash_dir = "/priv/crash";
/// One dump cannot fill /priv (ERL_CRASH_DUMP_BYTES).
const crash_dump_bytes = "1048576";
/// The newest few dumps are kept: a crash loop must not fill the disk.
const crash_dumps_kept = 5;

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
    log("pid 1, version " ++ version, .{});

    // A re-exec after a panic (ADR-004): the mounts are still in place (they
    // are not per-process), the BEAM is still our child, and its session is
    // still running. Read what that boot decided and adopt it; nothing is
    // planned, persisted or launched, because the running boot already
    // counted its attempt.
    var cmdline_buffer: [4096]u8 = undefined;
    var argv_buffer: [8][]const u8 = undefined;
    if (rescue.parse(ownArgs(init, &argv_buffer))) |adopted| {
        const settings = readSettings(&cmdline_buffer);
        var state: recovery.BootState = .{};
        var state_unreadable = false;
        if (readState(&state)) |_| {} else |err| switch (err) {
            // The same rule as a fresh boot: an unreadable state file means
            // rescue, and never writing over the evidence (ADR-006).
            error.FileNotFound => {},
            else => {
                log("state file unreadable ({t}), entering rescue", .{err});
                state_unreadable = true;
            },
        }

        // The safe override comes from the handoff, not from this boot's
        // command line: the boot that panicked may have entered rescue because
        // its disk would not mount, which cannot be re-derived here.
        var overrides: recovery.Overrides = .{ .safe = adopted.safe or state_unreadable };
        if (!overrides.safe) overrides.generation = settings.generation;

        const policy: recovery.Policy = .{ .max_attempts = settings.max_attempts };

        log("adopting beam pid={d}", .{adopted.beam_pid});
        supervise(
            recovery.planLaunch(state, policy, overrides),
            settings,
            overrides,
            adopted.disk_mounted,
            state,
            adopted,
        );
    }

    var overrides: recovery.Overrides = .{};

    // 1. The filesystems the rest of the boot needs. A missing one is not
    //    fatal: it only costs us /proc/cmdline or a place to mount /priv.
    if (!mountBase()) overrides.safe = true;

    // 2. Kernel command line (PROTOCOL.md §5). The buffer outlives the
    //    settings it is parsed into, for the whole of main.
    const settings = readSettings(&cmdline_buffer);
    if (settings.safe) overrides.safe = true;

    // 3+4. /priv and boot.state. The disk is mounted and read even when the
    //      safe override is set: rescue is "the factory with /priv mounted"
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

    const plan = recovery.planLaunch(state, policy, overrides);
    logPlan(state, plan, policy, overrides);
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

    launch(plan, settings, overrides, disk_mounted);
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

/// Mounts the data device on /priv, waiting for it to appear first (see
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
        const err = linux.errno(linux.mount(path.ptr, "/priv", "ext4", 0, 0));
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

/// Creates /priv/crash and prunes it to the newest `crash_dumps_kept` dumps.
/// Runs before every launch - including a relaunch after a crash, so a crash
/// loop inside one boot is bounded too - on a disk we may have just mounted;
/// without a disk there is nowhere to keep a dump.
fn prepareCrashDir() void {
    _ = linux.mkdir(crash_dir, 0o755);

    // One scan holds a bounded number of entries. A directory with more than
    // that gets another pass: an overflowing pass always has more than
    // `crash_dumps_kept` candidates, so it always removes some, and the loop
    // terminates. The bound is only a guard against a pathological directory.
    for (0..1024) |_| {
        if (!pruneCrashDumps()) break;
    }
}

/// True when `a` is older than `b`, comparing (seconds, nanoseconds) without
/// multiplying: kernel timestamps run to the year 2446, past i64 nanoseconds.
fn older(secs: []const i64, nsecs: []const u32, a: usize, b: usize) bool {
    if (secs[a] != secs[b]) return secs[a] < secs[b];
    return nsecs[a] < nsecs[b];
}

/// Unlinks the oldest `.dump` files until only `crash_dumps_kept` remain.
/// Everything is a fixed buffer: this runs on the launch path. Returns true
/// when the directory held more entries than one scan could see.
fn pruneCrashDumps() bool {
    const dir = linux.openat(
        linux.AT.FDCWD,
        crash_dir,
        // ACCMODE defaults to O_RDONLY: only reading is wanted here.
        .{ .DIRECTORY = true, .CLOEXEC = true },
        0,
    );
    if (linux.errno(dir) != .SUCCESS) return false;
    defer _ = linux.close(@intCast(dir));

    const max_entries = 24;
    var names: [max_entries][64]u8 = undefined;
    var secs: [max_entries]i64 = undefined;
    var nsecs: [max_entries]u32 = undefined;
    var count: usize = 0;
    var overflow = false;

    var buffer: [4096]u8 align(@alignOf(linux.dirent64)) = undefined;
    while (true) {
        const rc = linux.getdents64(@intCast(dir), &buffer, buffer.len);
        if (linux.errno(rc) != .SUCCESS or rc == 0) break;

        var offset: usize = 0;
        while (offset + @sizeOf(linux.dirent64) <= rc) {
            const entry: *align(1) const linux.dirent64 = @ptrCast(&buffer[offset]);
            const raw: [*:0]const u8 = @ptrCast(&entry.name);
            const name = std.mem.sliceTo(raw, 0);
            offset += entry.reclen;

            if (!std.mem.endsWith(u8, name, ".dump")) continue;
            if (count == max_entries) {
                // Whatever else is here is swept in the next pass.
                overflow = true;
                break;
            }
            if (name.len >= names[count].len) continue;

            var st: linux.Statx = undefined;
            if (linux.errno(linux.statx(@intCast(dir), raw, 0, .{ .MTIME = true }, &st)) != .SUCCESS) continue;

            @memcpy(names[count][0..name.len], name);
            names[count][name.len] = 0;
            secs[count] = @intCast(st.mtime.sec);
            nsecs[count] = st.mtime.nsec;
            count += 1;
        }
    }

    while (count > crash_dumps_kept) {
        var oldest: usize = 0;
        for (1..count) |i| {
            if (older(secs[0..count], nsecs[0..count], i, oldest)) oldest = i;
        }

        _ = linux.unlinkat(@intCast(dir), @ptrCast(&names[oldest]), 0);

        names[oldest] = names[count - 1];
        secs[oldest] = secs[count - 1];
        nsecs[oldest] = nsecs[count - 1];
        count -= 1;
    }

    return overflow;
}

/// Reads and parses the kernel command line (PROTOCOL.md §5). Both the fresh
/// boot and an adoption need it, so it is read per path rather than hoisted:
/// the fresh boot's console lines keep the order the tests expect.
/// `buffer` is the caller's: the returned settings point into it (data_device
/// and friends are slices into the command line), so it must outlive them.
fn readSettings(buffer: *[4096]u8) cmdline.Settings {
    const text: []const u8 = readFile("/proc/cmdline", buffer) catch "";
    const settings = cmdline.parse(text);
    if (settings.invalid > 0) log("ignored {d} invalid elixos.* parameters", .{settings.invalid});
    return settings;
}

/// Reads and parses /priv/boot.state (PROTOCOL.md §4).
fn readState(state: *recovery.BootState) StateError!void {
    var buffer: [128]u8 = undefined;
    const text = try readFile(state_path, &buffer);
    state.* = try statefile.parse(text);
}

/// Write boot.state.tmp, fsync it, rename it over boot.state, fsync /priv
/// (PROTOCOL.md §4). Every failure leaves the old file in place.
fn writeState(state: recovery.BootState) void {
    var buffer: [statefile.max_len]u8 = undefined;
    const text = statefile.encode(state, &buffer) catch return;
    writeFileAtomic(state_path, state_tmp_path, text);
}

/// 6. Launch the planned generation: the factory's ERTS, as our child, with
///    the control pipe and the environment contract of PROTOCOL.md §3. PID 1
///    stays PID 1, so a crashed or hung BEAM stays observable (ADR-002).
fn launch(plan: recovery.Plan, settings: cmdline.Settings, overrides: recovery.Overrides, disk_mounted: bool) noreturn {
    if (!pathExists(factory_path)) {
        log("factory missing, powering off", .{});
        shutdown(.poweroff);
    }
    // A fresh launch: the plan's next_state is what the session supervises.
    supervise(plan, settings, overrides, disk_mounted, plan.next_state, null);
}

/// The child's half of the launch: log, set up argv/envp, exec. Only returns
/// by way of exit_group: PID 1's child must not fall back into the shim.
///
/// `ctl_fd` is the pipe's write end (the BEAM's); `ctl_read_end` is the
/// parent's side, which the BEAM must not inherit: PID 1 keeps it across its
/// own re-exec (ADR-004), so it is closed here rather than made CLOEXEC.
fn execErts(
    plan: recovery.Plan,
    ctl_fd: linux.fd_t,
    ctl_read_end: linux.fd_t,
    disk_mounted: bool,
) noreturn {
    var generation: [32]u8 = undefined;
    var attempt: [32]u8 = undefined;
    var control: [32]u8 = undefined;
    var mode: [32]u8 = undefined;
    var crash: [80]u8 = undefined;

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
        // The console is a tty that is not the shell's controlling terminal,
        // so without +Bc Ctrl+C does nothing at all and a runaway expression
        // can only be stopped with Ctrl+G then `i` (PROTOCOL.md §3).
        "+Bc",
        // No shell at boot: the login REPL asks user_drv for one when the
        // application is up (ADR-012), so the prompt never races the boot.
        "-noshell",
        null,
    };
    // Without the persistent disk there is nowhere to keep a dump, and ERTS
    // would fail writing one: leave its default (the working directory) then.
    const crash_env: [2]?[*:0]const u8 = if (disk_mounted) .{
        zeroed(&crash, "ERL_CRASH_DUMP={s}/gen{d}-attempt{d}.dump", .{
            crash_dir,
            plan.launch.generation,
            plan.next_state.attempts,
        }),
        "ERL_CRASH_DUMP_BYTES=" ++ crash_dump_bytes,
    } else .{ null, null };

    const envp = [_]?[*:0]const u8{
        "ROOTDIR=" ++ factory_path,
        "BINDIR=" ++ bindir_path,
        "EMU=beam",
        "PROGNAME=erl",
        "HOME=/priv/home",
        "TERM=linux",
        "LANG=C.UTF-8",
        zeroed(&generation, "ELIXOS_GENERATION={d}", .{plan.launch.generation}),
        zeroed(&mode, "ELIXOS_MODE={t}", .{plan.launch.mode}),
        zeroed(&attempt, "ELIXOS_ATTEMPT={d}", .{plan.next_state.attempts}),
        zeroed(&control, "ELIXOS_CTL_FD={d}", .{ctl_fd}),
        crash_env[0],
        crash_env[1],
        null,
    };

    // PID 1 blocks the signals it handles through the signalfd, and fork
    // keeps that mask: ERTS would inherit SIGTERM/SIGINT/SIGPWR blocked and
    // never see a shutdown request. The child gets a clean mask.
    unblockSignals();

    // PID 1's end of the control pipe, which the BEAM must not hold.
    _ = linux.close(ctl_read_end);

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

/// The backoff before a crashed BEAM is relaunched: long enough that a crash
/// loop cannot spin the machine, short enough that a restart feels immediate.
const relaunch_backoff_ms = 1_000;

/// rt_sigprocmask's SIG_BLOCK and SIG_SETMASK. The kernel ABI fixes these
/// values: SIG_BLOCK 0, SIG_UNBLOCK 1, SIG_SETMASK 2 (x86_64 only, ADR-014).
const sig_block: u32 = 0;
const sig_setmask: u32 = 2;

/// One supervision session: the BEAM we launched, the control channel to it,
/// and the decisions that follow from its exit (ARCHITECTURE.md §3.3).
const Session = struct {
    settings: cmdline.Settings,
    policy: recovery.Policy,
    overrides: recovery.Overrides,
    disk_mounted: bool,

    epfd: linux.fd_t,
    sigfd: linux.fd_t,
    timerfd: linux.fd_t,

    plan: recovery.Plan,
    /// What the running plan was made from: control messages apply to this.
    state: recovery.BootState,
    beam: linux.pid_t = 0,
    ctl_fd: linux.fd_t = -1,
    requested: ?recovery.Shutdown = null,
    /// Set only by the `elixos.test.shim_panic_after` hook, in test images.
    panic_deadline_ms: ?i64 = null,
    first_heartbeat_pending: bool = true,
    buffer: [protocol.max_line_len * 2]u8 = undefined,
    pending: usize = 0,
    /// True while an over-long line is being discarded: everything up to and
    /// including the next newline is ignored (PROTOCOL.md §2), however many
    /// reads that takes.
    discarding: bool = false,

    /// Forks and execs `plan` with a fresh control pipe, then arms the
    /// heartbeat deadline with the boot grace (PROTOCOL.md §2 and §3).
    fn spawn(self: *Session, plan: recovery.Plan) void {
        // Before the fork: the child may reach ERTS's crash handler before
        // this process would otherwise have created the directory, and a dump
        // whose directory is missing is not written at all.
        if (self.disk_mounted) prepareCrashDir();

        var pipe_fds: [2]linux.fd_t = undefined;
        if (linux.errno(linux.pipe2(&pipe_fds, .{ .NONBLOCK = true })) != .SUCCESS) {
            log("cannot create the control pipe, powering off", .{});
            shutdown(.poweroff);
        }
        // epoll readiness can be stale by the time PID 1 reads: the read end
        // must return EAGAIN rather than suspend the loop. The BEAM's write
        // end stays a normal blocking one.
        _ = linux.fcntl(pipe_fds[1], linux.F.SETFL, 0);
        // The read end is deliberately NOT close-on-exec: the panic handler
        // execs this binary again, and the shim that comes back must inherit
        // the channel to the BEAM it adopts (ADR-004, M8). The BEAM itself
        // must not inherit it, or EOF would never arrive when it exits, so
        // the child closes it just before its own exec.

        const child = linux.fork();
        if (linux.errno(child) != .SUCCESS) {
            log("cannot fork, powering off", .{});
            shutdown(.poweroff);
        }
        if (child == 0) execErts(plan, pipe_fds[1], pipe_fds[0], self.disk_mounted);

        _ = linux.close(pipe_fds[1]);
        self.beam = @intCast(child);
        self.ctl_fd = pipe_fds[0];
        // The panic handler re-execs with this: a relaunch means a new pid, so
        // it is rebuilt every time.
        self.rearm();
        self.pending = 0;
        self.discarding = false;
        self.first_heartbeat_pending = true;
        self.plan = plan;
        self.state = plan.next_state;
        watch(self.epfd, pipe_fds[0]);
        armTimer(self.timerfd, self.settings.boot_grace_s);
    }

    /// Adopts the BEAM a re-exec left running (ADR-004, M8): no fork and no
    /// new control pipe - the read end is the one the old shim had, still
    /// open across execve - and the pid is still our child, so wait4 keeps
    /// seeing it. The BEAM has been running, so it owes its next heartbeat
    /// within the normal timeout, not the boot grace.
    fn adopt(self: *Session, a: rescue.Adopted) void {
        self.beam = a.beam_pid;
        self.ctl_fd = a.ctl_fd;
        self.pending = 0;
        self.discarding = false;
        self.first_heartbeat_pending = false;
        // A shutdown request the old shim had already read off the pipe: the
        // line cannot be replayed, so it is carried across the handoff.
        self.requested = a.requested;
        watch(self.epfd, a.ctl_fd);
        armTimer(self.timerfd, self.settings.heartbeat_timeout_s);
        self.rearm();
    }

    /// Refreshes the panic handler's argv: it carries the decisions that have
    /// changed since the last arming.
    fn rearm(self: *Session) void {
        rescue.arm(self.beam, self.ctl_fd, self.overrides.safe, self.disk_mounted, self.requested);
    }

    /// One read of the control pipe: applies what it can, reports whether
    /// anything was read, and closes the channel on EOF or a hard error.
    fn readControl(self: *Session) bool {
        const space = self.buffer.len - self.pending;
        const rc = linux.read(self.ctl_fd, self.buffer[self.pending..].ptr, space);
        const err = linux.errno(rc);
        if (err != .SUCCESS) {
            if (err == .INTR or err == .AGAIN) return false;
            self.forgetControl();
            return false;
        }
        if (rc == 0) {
            // EOF: every write end is closed. The BEAM may still be alive for
            // a moment (a requested shutdown); its exit decides what follows.
            self.forgetControl();
            return false;
        }

        self.pending += rc;
        var start: usize = 0;
        while (std.mem.indexOfScalarPos(u8, self.buffer[0..self.pending], start, '\n')) |newline| {
            if (self.discarding) {
                // The rest of an over-long line: discard it and resume
                // framing after its newline.
                self.discarding = false;
            } else {
                self.applyLine(self.buffer[start..newline]);
            }
            start = newline + 1;
        }
        const remaining = self.pending - start;
        if (remaining > 0) {
            std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[start..self.pending]);
        }
        self.pending = remaining;

        if (self.pending == self.buffer.len) {
            // A line that does not fit cannot be valid (PROTOCOL.md §2): it is
            // discarded up to its next newline, which may still be in a later
            // read, so framing does not resume at the buffer boundary.
            log("ignored control line (TooLong)", .{});
            self.pending = 0;
            self.discarding = true;
        }

        return true;
    }

    /// Reads until the pipe is empty: messages already written are still the
    /// BEAM's word, and a COMMIT, NEXT or POWEROFF must not be lost to an
    /// exit that arrived in the same epoll batch.
    fn drainControl(self: *Session) void {
        while (self.ctl_fd >= 0 and self.readControl()) {}
    }

    fn forgetControl(self: *Session) void {
        if (self.ctl_fd >= 0) {
            _ = linux.close(self.ctl_fd);
            self.ctl_fd = -1;
        }
    }

    /// One control line (PROTOCOL.md §2). Not a message is not fatal.
    fn applyLine(self: *Session, line: []const u8) void {
        const message = protocol.parse(line) catch |err| {
            log("ignored control line ({t})", .{err});
            return;
        };

        if (message == .heartbeat) {
            // The first heartbeat ends the boot grace (ARCHITECTURE.md §3.2).
            self.first_heartbeat_pending = false;
            armTimer(self.timerfd, self.settings.heartbeat_timeout_s);
            return;
        }

        const outcome = recovery.applyMessage(self.state, message);
        if (!std.meta.eql(outcome.state, self.state)) {
            self.state = outcome.state;
            if (self.disk_mounted) writeState(self.state);
            switch (message) {
                .commit => |generation| log("commit generation={d}", .{generation}),
                .next => |generation| log("next generation={d}", .{generation}),
                else => {},
            }
        }
        if (outcome.shutdown) |kind| {
            self.requested = kind;
            self.rearm();
        }
    }

    /// A signal arrived: SIGCHLD means a child exited (perhaps the BEAM);
    /// SIGTERM, SIGINT and SIGPWR are shutdown requests from outside.
    fn handleSignals(self: *Session) void {
        while (true) {
            var info: linux.signalfd_siginfo = undefined;
            const rc = linux.read(self.sigfd, @ptrCast(&info), @sizeOf(linux.signalfd_siginfo));
            const err = linux.errno(rc);
            if (err != .SUCCESS or rc == 0) return;

            switch (@as(linux.SIG, @fromBackingInt(@intCast(info.signo)))) {
                .CHLD => self.reap(),
                .INT => self.outsideShutdown(.reboot),
                .TERM, .PWR => self.outsideShutdown(.poweroff),
                else => {},
            }
        }
    }

    /// A shutdown request from outside: ask the BEAM to stop, and let the
    /// heartbeat deadline deal with it if it does not.
    fn outsideShutdown(self: *Session, kind: recovery.Shutdown) void {
        self.requested = kind;
        // The handoff carries the request: a panic between here and the
        // BEAM's exit must not turn the shutdown back into a relaunch.
        self.rearm();
        if (self.beam != 0) _ = linux.kill(self.beam, .TERM);
    }

    /// Reaps every child that has exited. PID 1 inherits orphans, so this runs
    /// for every child, not only the BEAM.
    fn reap(self: *Session) void {
        while (true) {
            var status: i32 = 0;
            const rc = linux.wait4(-1, &status, linux.W.NOHANG, null);
            if (linux.errno(rc) != .SUCCESS or rc == 0) return;
            const pid: linux.pid_t = @intCast(rc);
            if (pid == self.beam) self.beamExited(@bitCast(status));
            // Anything else was an orphan we inherited, now reaped.
        }
    }

    fn beamExited(self: *Session, status: u32) void {
        logBeamExit(status);
        // Anything the BEAM wrote before exiting still counts: shutdown
        // requests are remembered, and COMMIT/NEXT change the state.
        self.drainControl();
        self.forgetControl();
        self.beam = 0;

        // A generation override does not survive a crash: onBeamExit drops it
        // and keeps a safe override (ARCHITECTURE.md §3.3).
        const overrides: recovery.Overrides = .{ .safe = self.overrides.safe };

        switch (recovery.onBeamExit(self.state, self.policy, overrides, self.requested)) {
            .shutdown => |kind| shutdown(kind),
            .relaunch => |next| {
                logPlan(self.state, next, self.policy, overrides);
                // Persist before launching, so this attempt counts too.
                if (self.disk_mounted and !std.meta.eql(next.next_state, self.state)) {
                    writeState(next.next_state);
                }
                sleepMs(relaunch_backoff_ms);
                self.spawn(next);
            },
        }
    }

    /// The heartbeat deadline passed: to the shim a hang and a crash are the
    /// same event, so the BEAM is killed and its exit decides what follows.
    fn handleTimer(self: *Session) void {
        var expirations: u64 = undefined;
        const rc = linux.read(self.timerfd, @ptrCast(&expirations), @sizeOf(u64));
        // A cached event may outlive the deadline it was queued for (a
        // relaunch re-arms the timer): only a read that returned the count
        // means this deadline has passed.
        if (linux.errno(rc) != .SUCCESS or rc != @sizeOf(u64)) return;
        if (self.beam == 0) return;

        const seconds = if (self.first_heartbeat_pending)
            self.settings.boot_grace_s
        else
            self.settings.heartbeat_timeout_s;
        log("heartbeat timeout after {d}s, killing beam", .{seconds});
        _ = linux.kill(self.beam, .KILL);
    }
};

/// Watches the BEAM (ARCHITECTURE.md §3.1): an epoll loop over a signalfd, the
/// control pipe and a timerfd, reaping children and re-planning through
/// recovery.onBeamExit when the BEAM goes away. A crash and a hang are the
/// same event (ADR-007).
fn supervise(
    plan: recovery.Plan,
    settings: cmdline.Settings,
    overrides: recovery.Overrides,
    disk_mounted: bool,
    state: recovery.BootState,
    adopted: ?rescue.Adopted,
) noreturn {
    // Signals arrive through a signalfd: PID 1 must not die of SIGTERM, and
    // blocking them is exactly what signalfd needs.
    var mask = linux.sigemptyset();
    linux.sigaddset(&mask, .CHLD);
    linux.sigaddset(&mask, .TERM);
    linux.sigaddset(&mask, .INT);
    linux.sigaddset(&mask, .PWR);
    _ = linux.sigprocmask(sig_block, &mask, null);

    const sigfd = must(linux.signalfd(-1, &mask, linux.SFD.CLOEXEC | linux.SFD.NONBLOCK), "the signal fd");
    const timerfd = must(linux.timerfd_create(.MONOTONIC, .{ .CLOEXEC = true, .NONBLOCK = true }), "the timer");
    const epfd = must(linux.epoll_create1(linux.EPOLL.CLOEXEC), "the event loop");
    watch(epfd, sigfd);
    watch(epfd, timerfd);

    var session = Session{
        .settings = settings,
        .policy = .{ .max_attempts = settings.max_attempts },
        .overrides = overrides,
        .disk_mounted = disk_mounted,
        .epfd = epfd,
        .sigfd = sigfd,
        .timerfd = timerfd,
        .plan = plan,
        .state = state,
    };
    // An adopted state comes from disk: the running boot counted its attempt
    // when it started, and a fresh launch counts the plan's.
    if (adopted) |a| session.adopt(a) else session.spawn(plan);

    if (test_hooks) {
        if (session.settings.test_shim_panic_after_s) |seconds| {
            session.panic_deadline_ms = monotonicMs() + @as(i64, seconds) * 1000;
        }
    }

    while (true) {
        if (session.panic_deadline_ms) |deadline| {
            // QEMU test hook (ADR-018): panic on purpose so the handler above
            // is what gets exercised.
            if (monotonicMs() >= deadline) @panic("test hook: shim_panic_after");
        }

        var events: [4]linux.epoll_event = undefined;
        // With the panic hook armed, never sleep past its deadline: the
        // heartbeats that would normally wake this loop may have stopped, and
        // a heartbeat timeout would kill the BEAM before the hook fires.
        const wait_ms: i32 = if (session.panic_deadline_ms) |deadline|
            @intCast(std.math.clamp(deadline - monotonicMs(), 0, 60_000))
        else
            -1;
        const ready = linux.epoll_wait(epfd, &events, events.len, wait_ms);
        if (linux.errno(ready) != .SUCCESS) continue; // EINTR: look again

        if (session.panic_deadline_ms) |deadline| {
            // Checked again before dispatching: a heartbeat timeout event in
            // this batch must not kill the BEAM the hook was meant to adopt.
            if (monotonicMs() >= deadline) @panic("test hook: shim_panic_after");
        }
        for (events[0..ready]) |event| {
            const fd = event.data.fd;
            if (fd == sigfd) {
                session.handleSignals();
            } else if (fd == timerfd) {
                session.handleTimer();
            } else if (fd == session.ctl_fd) {
                _ = session.readControl();
            }
        }
    }
}

/// The lines every plan owes (PROTOCOL.md §6): the fallback first, then the
/// plan itself, both before the state is persisted.
fn logPlan(
    previous: recovery.BootState,
    plan: recovery.Plan,
    policy: recovery.Policy,
    overrides: recovery.Overrides,
) void {
    if (!overrides.safe and overrides.generation == null and
        previous.attempts >= policy.max_attempts and previous.current != previous.last_good)
    {
        log("fallback to last_good={d} after {d} attempts of generation={d}", .{
            previous.last_good,
            previous.attempts,
            previous.current,
        });
    }

    log("plan generation={d} mode={t} attempt={d}", .{
        plan.launch.generation,
        plan.launch.mode,
        plan.next_state.attempts,
    });
}

/// A child of PID 1 starts with a clean signal mask (see execErts).
fn unblockSignals() void {
    const empty = linux.sigemptyset();
    _ = linux.sigprocmask(sig_setmask, &empty, null);
}

/// A syscall that creates something PID 1 cannot run without. Failing it is
/// not a panic: say so and power off.
fn must(raw: usize, what: []const u8) linux.fd_t {
    if (linux.errno(raw) != .SUCCESS) {
        log("cannot create {s}, powering off", .{what});
        shutdown(.poweroff);
    }
    return @intCast(raw);
}

/// Registers `fd` in the event loop.
fn watch(epfd: linux.fd_t, fd: linux.fd_t) void {
    var event = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = fd } };
    _ = linux.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, fd, &event);
}

/// Arms the heartbeat deadline `seconds` from now: a one-shot, relative timer.
fn armTimer(timerfd: linux.fd_t, seconds: u32) void {
    const spec = linux.itimerspec{
        .it_interval = .{ .sec = 0, .nsec = 0 },
        .it_value = .{ .sec = @intCast(seconds), .nsec = 0 },
    };
    _ = linux.timerfd_settime(timerfd, .{}, &spec, null);
}

/// PROTOCOL.md §6: how the BEAM went away, exit status or signal.
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
    // Stragglers first (ARCHITECTURE.md §3.1): ask, then insist. -1 means
    // every process except us, which is what PID 1 is for.
    _ = linux.kill(-1, .TERM);
    sleepMs(50);
    _ = linux.kill(-1, .KILL);
    linux.sync();
    _ = linux.umount2("/priv", 0);
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
    const raw_dir = linux.open("/priv", .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
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

test "the rescue argv round-trips everything an adopted shim needs" {
    rescue.arm(4242, 7, true, false, .poweroff);

    const args = [_][]const u8{
        std.mem.span(rescue.argv[0].?),
        std.mem.span(rescue.argv[1].?),
        std.mem.span(rescue.argv[2].?),
        std.mem.span(rescue.argv[3].?),
        std.mem.span(rescue.argv[4].?),
        std.mem.span(rescue.argv[5].?),
        std.mem.span(rescue.argv[6].?),
    };
    const adopted = rescue.parse(&args) orelse return error.TestExpectedAdoption;
    try std.testing.expectEqual(@as(linux.pid_t, 4242), adopted.beam_pid);
    try std.testing.expectEqual(@as(linux.fd_t, 7), adopted.ctl_fd);
    // The boot that panicked may have been in rescue because its disk would
    // not mount, and may have a shutdown request already off the pipe.
    try std.testing.expectEqual(true, adopted.safe);
    try std.testing.expectEqual(false, adopted.disk_mounted);
    try std.testing.expectEqual(@as(?recovery.Shutdown, .poweroff), adopted.requested);
}

test "a fresh boot carries no adoption request" {
    const fresh = [_][]const u8{"init"};
    try std.testing.expectEqual(@as(?rescue.Adopted, null), rescue.parse(&fresh));

    const malformed = [_][]const u8{ "init", "--adopt", "nope", "7" };
    try std.testing.expectEqual(@as(?rescue.Adopted, null), rescue.parse(&malformed));
}

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
