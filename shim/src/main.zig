//! Elixos PID 1 shim (ADR-002..004, docs/ARCHITECTURE.md §3).
//!
//! Machine kernels exec this binary as /init and PID 1 never exits. The native
//! OCI build reuses the same supervisor, under namespace PID 1 or provider init;
//! only that build exits its process on namespace-local shutdown.
//!
//! Its jobs, built up over milestones M3..M8 (docs/ROADMAP.md):
//!
//!   1. Mount /proc, /sys, /dev (devtmpfs), /run and /tmp (tmpfs).
//!   2. Read /proc/cmdline -> cmdline.parse. Log the banner and invalid tokens.
//!   3. Use RAM-backed /priv for Live; otherwise mount elixos.data (ext4).
//!      Missing persistent storage: rescue.
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
pub const helpers = @import("helpers.zig");
pub const seal = @import("seal.zig");
pub const system_image = @import("system_image.zig");
pub const postgres_init = @import("postgres_init.zig");
pub const container = @import("container.zig");
pub const seed = @import("seed.zig");
pub const netif = @import("netif.zig");
pub const deck = @import("deck.zig");

/// `ELIXOS_DECK=<path>` (PROTOCOL.md §3, M33): resolved from elixos.deck once
/// per shim run, before the first launch, and passed to every BEAM it starts.
var deck_environment: [deck.max_path + "ELIXOS_DECK=".len + 1]u8 = undefined;
var deck_env: ?[*:0]const u8 = null;

/// OCI environment pointer storage is allocated only before supervision. The
/// original startup block remains untouched and is carried through panic exec.
var container_environment: ?container.Environment = null;

// The supervising frame lives until reboot. Shutdown can also happen before
// supervision exists, in which case there are no image-declared helpers.
var active_session: ?*Session = null;

var helper_list: helpers.AllowList = .{};

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
    var reply_text: [24]u8 = undefined;
    var generation_text: [16]u8 = undefined;
    var helpers_text: [helpers.max_helpers * 11]u8 = undefined;
    /// Includes the running generation and live helpers, not just NEXT's disk state.
    var argv: [11:null]?[*:0]const u8 = @splat(null);
    const empty_env = [_:null]?[*:0]const u8{};
    /// Machine PID 1 needs no inherited environment. OCI app secrets and the
    /// explicit runtime marker must survive adoption and later BEAM relaunches.
    var envp: [*:null]const ?[*:0]const u8 = &empty_env;

    fn inheritEnvironment(inherited: [:null]const ?[*:0]const u8) void {
        envp = inherited.ptr;
    }

    const Adopted = struct {
        beam_pid: linux.pid_t,
        ctl_fd: linux.fd_t,
        reply_fd: linux.fd_t,
        generation: u32,
        helper_pids: [helpers.max_helpers]linux.pid_t,
        /// The *effective* decisions of the boot that panicked. Rescue may
        /// have come from an unreadable state file or a missing disk, which
        /// the adopted shim cannot re-derive, and a shutdown request already
        /// read off the control pipe cannot be replayed.
        safe: bool,
        /// Writable /priv is available: persistent storage or the Live RAM rootfs.
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
        reply_fd: linux.fd_t,
        generation: u32,
        helper_pids: *const [helpers.max_helpers]linux.pid_t,
        safe: bool,
        disk_mounted: bool,
        requested: ?recovery.Shutdown,
    ) void {
        var offset: usize = 0;
        for (helper_pids, 0..) |pid, index| {
            if (index != 0) {
                helpers_text[offset] = ',';
                offset += 1;
            }
            const text = std.fmt.bufPrint(helpers_text[offset..], "{d}", .{pid}) catch {
                log("cannot format helper handoff, powering off", .{});
                shutdown(.poweroff);
            };
            offset += text.len;
        }
        helpers_text[offset] = 0;
        argv = .{
            init_path,
            "--adopt",
            zeroed(&pid_text, "{d}", .{beam_pid}),
            zeroed(&ctl_text, "{d}", .{ctl_fd}),
            if (safe) yes else no,
            if (disk_mounted) yes else no,
            requestName(requested),
            zeroed(&reply_text, "{d}", .{reply_fd}),
            zeroed(&generation_text, "{d}", .{generation}),
            @ptrCast(&helpers_text),
            null,
        };
    }

    /// The adoption request in our own command line:
    /// `--adopt <pid> <control fd> <safe> <mounted> <request> <reply fd> <generation> <helper pids>`.
    fn parse(args: []const []const u8) ?Adopted {
        if (args.len < 10) return null;
        if (!std.mem.eql(u8, args[1], "--adopt")) return null;
        const pid = std.fmt.parseInt(linux.pid_t, args[2], 10) catch return null;
        const fd = std.fmt.parseInt(linux.fd_t, args[3], 10) catch return null;
        const reply_fd = std.fmt.parseInt(linux.fd_t, args[7], 10) catch return null;
        const generation = decimal.parseU32(args[8]) orelse return null;
        var helper_pids: [helpers.max_helpers]linux.pid_t = undefined;
        var pids = std.mem.splitScalar(u8, args[9], ',');
        for (&helper_pids) |*value| {
            const pid_field = pids.next() orelse return null;
            const value_u32 = decimal.parseU32(pid_field) orelse return null;
            if (value_u32 > std.math.maxInt(linux.pid_t)) return null;
            value.* = @intCast(value_u32);
        }
        if (pids.next() != null) return null;
        return .{
            .beam_pid = pid,
            .ctl_fd = fd,
            .reply_fd = reply_fd,
            .generation = generation,
            .helper_pids = helper_pids,
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
    _ = linux.execve(init_path, @ptrCast(&rescue.argv), rescue.envp);

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
fn ownArgs(init: std.process.Init.Minimal, buffer: *[10][]const u8) []const []const u8 {
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
const state_tmp_path = "/priv/.seal/boot.state.tmp";

/// Crash dumps (PROTOCOL.md §7): ERTS writes them where the shim points
/// ERL_CRASH_DUMP. Persistent storage keeps the evidence across reboot;
/// Live keeps it only for the current RAM-backed session.
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
    if (container.enabled) {
        rescue.inheritEnvironment(init.environ.block.slice);
        container.validate(init.environ.block.slice) catch |err| {
            log("invalid container runtime ({t}), refusing startup", .{err});
            container.exit(1);
        };
        container.checkPriv() catch |err| {
            log("container /priv unavailable ({t}), exiting", .{err});
            container.exit(1);
        };
        container_environment = container.Environment.init(std.heap.page_allocator, init.environ.block.slice) catch {
            log("cannot preserve container environment, exiting", .{});
            container.exit(1);
        };
        log("container supervisor pid={d}, version " ++ version, .{linux.getpid()});
    } else {
        log("pid 1, version " ++ version, .{});
    }
    loadHelpers();

    // A re-exec after a panic (ADR-004): the mounts are still in place (they
    // are not per-process), the BEAM is still our child, and its session is
    // still running. Read what that boot decided and adopt it; nothing is
    // planned, persisted or launched, because the running boot already
    // counted its attempt.
    var cmdline_buffer: [4096]u8 = undefined;
    var argv_buffer: [10][]const u8 = undefined;
    if (rescue.parse(ownArgs(init, &argv_buffer))) |adopted| {
        if (container.enabled) {
            var owned = container.ownsChild(adopted.beam_pid);
            for (adopted.helper_pids) |pid| {
                if (pid != 0 and !container.ownsChild(pid)) owned = false;
            }
            if (!owned) {
                log("invalid container adoption, exiting", .{});
                container.exit(1);
            }
        }
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
        // An adopted BEAM's successors get the deck too; the device was
        // already found and granted, so this says nothing.
        if (!container.enabled) prepareDeck(settings, false);
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
    if (container.enabled) {
        const initialized = seed.initialize() catch |err| {
            log("container seed initialization refused ({t}), exiting", .{err});
            linux.exit_group(1);
        };
        if (initialized) log("container seed initialized", .{});
    }

    // 1. The filesystems the rest of the boot needs. A missing one is not
    //    fatal: it only costs us /proc/cmdline or a place to mount /priv.
    if (!container.enabled and !mountBase()) overrides.safe = true;

    // 1b. Loopback up: the kernel leaves `lo` down until someone asks, and
    //     everything local needs it - a provider an agent's action calls on
    //     127.0.0.1, a session's own services. One ioctl, as any init does.
    if (!container.enabled) bringLoopbackUp();

    // 2. Kernel command line (PROTOCOL.md §5). The buffer outlives the
    //    settings it is parsed into, for the whole of main.
    const settings = readSettings(&cmdline_buffer);
    if (settings.safe) overrides.safe = true;

    // 2b. The coprocessor link (M29, ADR-098): the BEAM cannot configure an
    //     interface (it has no CAP_NET_ADMIN), so the shim gives the named one
    //     its address and brings it up, as it does for loopback. Not fatal:
    //     without it only the coprocessor is unreachable.
    if (!container.enabled) {
        if (settings.coproc_link) |link| configureLink(link);
    }

    // 3+4. /priv and boot.state. Live keeps the initramfs's RAM-backed /priv,
    //      including its embedded service image and toolchain; never mount over
    //      those assets or copy them. Otherwise mount the data device even when
    //      safe is set: rescue is "the factory with /priv available".
    //      State accounting and sealing are identical for either storage choice.
    //      Only a plan that changes state is written (ADR-006).
    var state: recovery.BootState = .{};
    const disk_mounted = if (container.enabled) true else preparePriv(settings, mountData);
    if (disk_mounted) {
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

    seal.prepare() catch |err| {
        log("cannot prepare unprivileged state ({t}), powering off", .{err});
        shutdown(.poweroff);
    };
    if (!container.enabled) {
        prepareDeviceGroups("/dev", "fb", 27);
        prepareDeviceGroups("/dev/input", "event", 23);
        // The deck framebuffer (M33): after /dev and /sys exist, in normal
        // and rescue mode alike, never fatal.
        prepareDeck(settings, true);
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

/// /proc, /sys, /dev, /run, /tmp and /dev/shm. Failed mounts enter rescue.
fn mountBase() bool {
    const Mount = struct {
        target: [*:0]const u8,
        fstype: [*:0]const u8,
        data: usize = 0,
        create: ?linux.mode_t = null,
    };
    const mounts = [_]Mount{
        .{ .target = "/proc", .fstype = "proc" },
        .{ .target = "/sys", .fstype = "sysfs" },
        .{ .target = "/dev", .fstype = "devtmpfs" },
        .{ .target = "/run", .fstype = "tmpfs", .data = @intFromPtr("mode=0755") },
        .{ .target = "/tmp", .fstype = "tmpfs", .data = @intFromPtr("mode=1777") },
        // devtmpfs hides apko's /dev/shm mountpoint; recreate it on that mount.
        .{ .target = "/dev/shm", .fstype = "tmpfs", .data = @intFromPtr("mode=1777"), .create = 0o1777 },
    };
    var ok = true;
    for (mounts) |m| {
        var err: linux.E = .SUCCESS;
        if (m.create) |permissions| {
            err = linux.errno(linux.mkdirat(linux.AT.FDCWD, m.target, permissions));
            if (err == .EXIST) err = .SUCCESS;
        }
        if (err == .SUCCESS) err = linux.errno(linux.mount(m.fstype, m.target, m.fstype, 0, m.data));
        if (err != .SUCCESS) {
            // Not fatal in itself: losing /proc only costs us the command line.
            var name_buffer: [24]u8 = undefined;
            log("cannot mount {s} ({s}), entering rescue", .{ m.target, errnoName(&name_buffer, err) });
            ok = false;
        }
    }
    return ok;
}

/// Whether writable /priv is available, including Live's RAM-backed rootfs.
/// Live short-circuits before any physical-device mount or wait, independently
/// of the safe/generation overrides. The mount boundary is injectable for tests.
fn preparePriv(settings: cmdline.Settings, comptime mount_data: fn ([]const u8, u32) bool) bool {
    return settings.live or mount_data(settings.data_device, settings.data_wait_s);
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
/// loop inside one boot is bounded too - wherever writable /priv is available,
/// including Live's RAM-backed rootfs.
fn prepareCrashDir() void {
    _ = linux.mkdir(crash_dir, 0o755);
    // This directory may be new since seal.prepare() migrated existing state.
    // ERTS, not PID 1, writes the dump; never chown through a user-planted link.
    const ownership = linux.fchownat(linux.AT.FDCWD, crash_dir, seal.uid, seal.gid, linux.AT.SYMLINK_NOFOLLOW);
    if (linux.errno(ownership) != .SUCCESS) {
        log("cannot own crash directory ({t})", .{linux.errno(ownership)});
        return;
    }

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
        .{ .DIRECTORY = true, .CLOEXEC = true, .NOFOLLOW = true },
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
    if (container.enabled) return .{ .safe = container_environment.?.safe };
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
    reply_fd: linux.fd_t,
    reply_write_end: linux.fd_t,
    disk_mounted: bool,
) noreturn {
    var generation: [32]u8 = undefined;
    var attempt: [32]u8 = undefined;
    var control: [32]u8 = undefined;
    var reply: [32]u8 = undefined;
    var mode: [32]u8 = undefined;
    var crash: [80]u8 = undefined;

    // erlexec takes $ROOTDIR and $BINDIR from the environment (below) and
    // passes -root/-bindir to ERTS itself: repeating them here makes ERTS
    // exit with "no_or_multiple_root_variables". The boot script resolves its
    // $ROOT against that -root and its $RELEASE_LIB against the boot_var.
    const argv = [_]?[*:0]const u8{
        "erlexec",
        "-boot",
        boot_path,
        "-boot_var",
        "RELEASE_LIB",
        lib_path,
        "-config",
        sys_config_path,
        // Interactive, not embedded: Elixos loads code at run time - the live
        // image restores modules, and the box builds Mix projects - and the
        // embedded code server refuses to load anything from the code path.
        "-mode",
        "interactive",
        // The console is a tty that is not the shell's controlling terminal,
        // so without +Bc Ctrl+C does nothing at all and a runaway expression
        // can only be stopped with Ctrl+G then `i` (PROTOCOL.md §3).
        "+Bc",
        // No shell at boot: the login REPL asks user_drv for one when the
        // application is up (ADR-012), so the prompt never races the boot.
        "-noshell",
        null,
    };
    // Without writable /priv there is nowhere to keep a dump, and ERTS would
    // fail writing one: leave its default (the working directory) then.
    const crash_env: [2]?[*:0]const u8 = if (disk_mounted) .{
        zeroed(&crash, "ERL_CRASH_DUMP={s}/gen{d}-attempt{d}.dump", .{
            crash_dir,
            plan.launch.generation,
            plan.next_state.attempts,
        }),
        "ERL_CRASH_DUMP_BYTES=" ++ crash_dump_bytes,
    } else .{ null, null };

    // OCI's SDK is immutable and separate from the writable /priv volume.
    // Machine builds retain the persistent/Live toolchain layout (ADR-009).
    const path_env = if (container.enabled)
        "PATH=/toolchain:/usr/local/bin:/bin:/usr/bin"
    else if (disk_mounted)
        "PATH=/priv/toolchain:/usr/local/bin:/bin:/usr/bin"
    else
        "PATH=/usr/local/bin:/bin:/usr/bin";

    const contract = [_]?[*:0]const u8{
        "ROOTDIR=" ++ factory_path,
        "BINDIR=" ++ bindir_path,
        "EMU=beam",
        "PROGNAME=erl",
        "HOME=/priv/home",
        "TERM=linux",
        "LANG=C.UTF-8",
        path_env,
        zeroed(&generation, "ELIXOS_GENERATION={d}", .{plan.launch.generation}),
        zeroed(&mode, "ELIXOS_MODE={t}", .{plan.launch.mode}),
        zeroed(&attempt, "ELIXOS_ATTEMPT={d}", .{plan.next_state.attempts}),
        zeroed(&control, "ELIXOS_CTL_FD={d}", .{ctl_fd}),
        zeroed(&reply, "ELIXOS_REPLY_FD={d}", .{reply_fd}),
        if (container.enabled) "ELIXOS_RUNTIME=container" else "ELIXOS_RUNTIME=machine",
        if (container.enabled) (if (container_environment.?.console) "ELIXOS_CONSOLE=1" else "ELIXOS_CONSOLE=0") else null,
        if (container.enabled) null else deck_env,
        crash_env[0],
        crash_env[1],
    };
    // Compact optional entries for the machine build too: a null in the
    // middle would hide the crash limit and every following environment key.
    var machine_environment: [container.contract_capacity:null]container.Entry = @splat(null);
    const envp = if (container.enabled)
        container_environment.?.launch(&contract).ptr
    else blk: {
        var count: usize = 0;
        for (contract) |entry| {
            if (entry != null) {
                machine_environment[count] = entry;
                count += 1;
            }
        }
        break :blk @as([*:null]const container.Entry, &machine_environment);
    };

    // PID 1 blocks the signals it handles through the signalfd, and fork
    // keeps that mask: ERTS would inherit SIGTERM/SIGINT/SIGPWR blocked and
    // never see a shutdown request. The child gets a clean mask.
    unblockSignals();

    // PID 1's end of the control pipe, which the BEAM must not hold.
    _ = linux.close(ctl_read_end);
    _ = linux.close(reply_write_end);
    dropIdentity(1000, 1000, true) catch |err| {
        log("cannot drop BEAM privileges ({t}), exiting", .{err});
        _ = linux.exit_group(1);
    };

    log("launching generation={d} mode={t}", .{ plan.launch.generation, plan.launch.mode });
    _ = linux.execve(erlexec_path, @ptrCast(&argv), envp);
    // execve only returns on failure. Say why we are going away, and let the
    // shim count the attempt (ADR-007) instead of leaving a zombie half-boot.
    log("cannot exec {s}, exiting", .{erlexec_path});
    _ = linux.exit_group(1);
}

fn loadHelpers() void {
    var buffer: [helpers.max_helpers * (helpers.max_line_len + 1) + 1]u8 = undefined;
    const text = readFile("/etc/elixos/helpers", &buffer) catch |err| {
        log("helper list unavailable ({t}), no helpers", .{err});
        return;
    };
    helpers.parseAllowList(text, &helper_list) catch |err| {
        log("helper list invalid ({t}), no helpers", .{err});
    };
}

/// The only privilege retained by the BEAM is binding SSH's port 22.
fn dropIdentity(uid: u32, gid: u32, bind_service: bool) error{DropFailed}!void {
    const groups = [_]linux.gid_t{ 23, 27 };
    if (bind_service and linux.errno(linux.prctl(@backingInt(linux.PR.SET_KEEPCAPS), 1, 0, 0, 0)) != .SUCCESS)
        return error.DropFailed;
    if (linux.errno(linux.setgroups(if (bind_service) groups.len else 0, &groups)) != .SUCCESS or
        linux.errno(linux.setgid(gid)) != .SUCCESS or linux.errno(linux.setuid(uid)) != .SUCCESS)
        return error.DropFailed;
    if (bind_service) {
        // Linux UAPI uses a 32-bit pid; this nightly's cap_user_header_t uses usize.
        var header: extern struct { version: u32, pid: i32 } = .{ .version = 0x20080522, .pid = 0 };
        const bit: u32 = 1 << 10; // CAP_NET_BIND_SERVICE
        const caps = [_]linux.cap_user_data_t{
            .{ .effective = bit, .permitted = bit, .inheritable = bit },
            .{ .effective = 0, .permitted = 0, .inheritable = 0 },
        };
        if (linux.errno(linux.syscall2(.capset, @intFromPtr(&header), @intFromPtr(&caps))) != .SUCCESS or
            linux.errno(linux.prctl(@backingInt(linux.PR.CAP_AMBIENT), linux.PR.CAP_AMBIENT_CLEAR_ALL, 0, 0, 0)) != .SUCCESS or
            linux.errno(linux.prctl(@backingInt(linux.PR.CAP_AMBIENT), linux.PR.CAP_AMBIENT_RAISE, 10, 0, 0)) != .SUCCESS)
            return error.DropFailed;
    }
    if (linux.errno(linux.prctl(@backingInt(linux.PR.SET_NO_NEW_PRIVS), 1, 0, 0, 0)) != .SUCCESS)
        return error.DropFailed;
}

/// devtmpfs has no udev: group-only access is prepared before the tenant starts.
fn prepareDeviceGroups(path: [*:0]const u8, prefix: []const u8, gid: u32) void {
    const raw_dir = linux.open(path, .{ .DIRECTORY = true, .CLOEXEC = true, .NOFOLLOW = true }, 0);
    if (linux.errno(raw_dir) != .SUCCESS) return;
    const dir: linux.fd_t = @intCast(raw_dir);
    defer _ = linux.close(dir);
    var buffer: [4096]u8 align(@alignOf(linux.dirent64)) = undefined;
    while (true) {
        const rc = linux.getdents64(dir, &buffer, buffer.len);
        if (linux.errno(rc) != .SUCCESS or rc == 0) return;
        var offset: usize = 0;
        while (offset + @sizeOf(linux.dirent64) <= rc) {
            const entry: *align(1) const linux.dirent64 = @ptrCast(&buffer[offset]);
            if (entry.reclen < @sizeOf(linux.dirent64) or entry.reclen > rc - offset) return;
            const raw: [*:0]const u8 = @ptrCast(&entry.name);
            const name = std.mem.sliceTo(raw, 0);
            offset += entry.reclen;
            if (!std.mem.startsWith(u8, name, prefix) or name.len == prefix.len) continue;
            _ = decimal.parseU32(name[prefix.len..]) orelse continue;
            var st: linux.Statx = undefined;
            if (linux.errno(linux.statx(dir, raw, linux.AT.SYMLINK_NOFOLLOW, .{ .TYPE = true }, &st)) != .SUCCESS or
                st.mode & linux.S.IFMT != linux.S.IFCHR) continue;
            _ = linux.fchownat(dir, raw, 0, gid, linux.AT.SYMLINK_NOFOLLOW);
            _ = linux.fchmodat2(dir, raw, 0o660, linux.AT.SYMLINK_NOFOLLOW);
        }
    }
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
    /// Writable /priv is available, including the Live RAM rootfs, not just a disk.
    disk_mounted: bool,

    epfd: linux.fd_t,
    sigfd: linux.fd_t,
    timerfd: linux.fd_t,

    plan: recovery.Plan,
    /// What the running plan was made from: control messages apply to this.
    state: recovery.BootState,
    beam: linux.pid_t = 0,
    ctl_fd: linux.fd_t = -1,
    reply_fd: linux.fd_t = -1,
    helper_pids: [helpers.max_helpers]linux.pid_t = @splat(0),
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
        if (plan.launch.mode == .rescue) {
            self.stopHelpers();
            system_image.unmount() catch |err| log("cannot unmount system image ({t})", .{err});
        } else if (self.disk_mounted) {
            prepareSystem();
        }
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
        var reply_fds: [2]linux.fd_t = undefined;
        _ = must(linux.pipe2(&reply_fds, .{ .NONBLOCK = true }), "the helper reply pipe");
        // Reopening inherited pipes through /proc/self/fd checks inode permissions.
        _ = must(linux.fchown(pipe_fds[1], 1000, 1000), "control pipe ownership");
        _ = must(linux.fchmod(pipe_fds[1], 0o200), "control pipe permissions");
        _ = must(linux.fchown(reply_fds[0], 1000, 1000), "reply pipe ownership");
        _ = must(linux.fchmod(reply_fds[0], 0o400), "reply pipe permissions");
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
        if (child == 0) execErts(plan, pipe_fds[1], pipe_fds[0], reply_fds[0], reply_fds[1], self.disk_mounted);

        _ = linux.close(pipe_fds[1]);
        _ = linux.close(reply_fds[0]);
        self.reply_fd = reply_fds[1];
        self.beam = @intCast(child);
        self.ctl_fd = pipe_fds[0];
        // The panic handler re-execs with this: a relaunch means a new pid, so
        // it is rebuilt every time.
        self.plan = plan;
        self.state = plan.next_state;
        self.rearm();
        self.pending = 0;
        self.discarding = false;
        self.first_heartbeat_pending = true;
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
        self.reply_fd = a.reply_fd;
        self.plan.launch.generation = a.generation;
        self.helper_pids = a.helper_pids;
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
        rescue.arm(self.beam, self.ctl_fd, self.reply_fd, self.plan.launch.generation, &self.helper_pids, self.overrides.safe, self.disk_mounted, self.requested);
    }

    fn prepareSystem() void {
        system_image.mount() catch |err| {
            log("system image unavailable ({t}), services disabled", .{err});
            return;
        };
        system_image.preparePostgres() catch |err| {
            log("postgres directories unavailable ({t}), services disabled", .{err});
            system_image.unmount() catch |unmount_err| log("cannot unmount system image ({t})", .{unmount_err});
        };
    }

    /// The database remains alive until the BEAM has stopped. PostgreSQL's
    /// fast shutdown must complete before the generic straggler kill.
    fn stopHelpers(self: *Session) void {
        for (helper_list.helpers[0..helper_list.len], 0..) |*helper, index| {
            if (self.helper_pids[index] == 0 or !std.mem.eql(u8, helper.name[0..helper.name_len], "postgres")) continue;
            _ = linux.kill(self.helper_pids[index], .INT);
            if (!self.waitHelper(index, 30_000)) {
                log("helper shutdown timeout name=postgres, killing", .{});
                _ = linux.kill(self.helper_pids[index], .KILL);
            }
        }
        for (self.helper_pids) |pid| {
            if (pid != 0) _ = linux.kill(pid, .TERM);
        }
        sleepMs(50);
        for (self.helper_pids, 0..) |pid, index| {
            if (pid != 0 and !self.waitHelper(index, 0)) _ = linux.kill(pid, .KILL);
        }
        self.rearm();
    }

    fn waitHelper(self: *Session, index: usize, grace_ms: i64) bool {
        const deadline = monotonicMs() + grace_ms;
        while (true) {
            var status: i32 = 0;
            const result = linux.wait4(self.helper_pids[index], &status, linux.W.NOHANG, null);
            const err = linux.errno(result);
            if ((err == .SUCCESS and result != 0) or err == .CHILD) {
                self.helper_pids[index] = 0;
                return true;
            }
            if (err == .INTR) continue;
            if (err != .SUCCESS or monotonicMs() >= deadline) return false;
            sleepMs(25);
        }
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

    fn startHelper(self: *Session, name: []const u8) void {
        // No clock, DHCP, console handover or host hardware operations in
        // OCI, even if an image accidentally declares such a helper.
        if (container.enabled and !container.helperAllowed(name)) {
            log("helper refused name={s}", .{name});
            self.helperReply(name, null);
            return;
        }
        if ((std.mem.eql(u8, name, "postgres") or std.mem.eql(u8, name, "postgres-init")) and
            (self.plan.launch.mode != .normal or !system_image.mounted()))
        {
            log("helper refused name={s}", .{name});
            self.helperReply(name, null);
            return;
        }
        if (container.enabled) {
            // A baked tree remains present even after an ownership failure;
            // unmount() cannot be used as the machine-only availability flag.
            system_image.preparePostgres() catch |err| {
                log("postgres directories unavailable ({t}), services disabled", .{err});
                self.helperReply(name, null);
                return;
            };
        }
        for (helper_list.helpers[0..helper_list.len], 0..) |*helper, index| {
            if (!std.mem.eql(u8, helper.name[0..helper.name_len], name)) continue;
            if (self.helper_pids[index] != 0) {
                self.helperReply(name, @intCast(self.helper_pids[index]));
                return;
            }
            const child = linux.fork();
            if (linux.errno(child) != .SUCCESS) break;
            if (child == 0) {
                _ = linux.close(self.ctl_fd);
                _ = linux.close(self.reply_fd);
                unblockSignals();
                dropIdentity(helper.uid, helper.gid, false) catch {
                    log("cannot drop helper privileges name={s}, exiting", .{name});
                    _ = linux.exit_group(1);
                };
                var path: [helpers.max_line_len + 1]u8 = undefined;
                @memcpy(path[0..helper.path_len], helper.path[0..helper.path_len]);
                path[helper.path_len] = 0;
                var argv: [helpers.max_line_len / 2 + 2:null]?[*:0]const u8 = @splat(null);
                argv[0] = @ptrCast(&path);
                var offset: usize = 0;
                for (0..helper.argc) |i| {
                    const arg: [*:0]const u8 = @ptrCast(helper.args[offset..].ptr);
                    argv[i + 1] = arg;
                    offset += std.mem.sliceTo(arg, 0).len + 1;
                }
                const envp = [_:null]?[*:0]const u8{
                    system_image.path_environment,
                    system_image.library_environment,
                    "LANG=C.UTF-8",
                    "HOME=/priv",
                };
                _ = linux.execve(@ptrCast(&path), @ptrCast(&argv), &envp);
                log("cannot exec helper name={s}, exiting", .{name});
                _ = linux.exit_group(1);
            }
            self.helper_pids[index] = @intCast(child);
            self.rearm();
            self.helperReply(name, @intCast(child));
            return;
        }
        log("helper refused name={s}", .{name});
        self.helperReply(name, null);
    }

    fn helperReply(self: *Session, name: []const u8, pid: ?u32) void {
        var buffer: [protocol.max_line_len + 1]u8 = undefined;
        const reply = helpers.encodeReply(name, pid, &buffer) catch return;
        // A blocked or dead tenant must not suspend PID 1's event loop.
        _ = writeAll(self.reply_fd, reply);
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
        if (message == .helper) {
            const name = message.helper.name[0..message.helper.name_len];
            self.startHelper(name);
            return;
        }
        if (message == .commit) {
            const generation = message.commit;
            // NEXT may already name a different candidate; it is not running yet.
            if (generation != self.state.current or generation != self.plan.launch.generation) return;
            if (generation != 0) {
                seal.commit(generation) catch |err| {
                    log("commit refused generation={d} ({t})", .{ generation, err });
                    return;
                };
                // Sealing is PID 1's own work, not a missed BEAM heartbeat.
                armTimer(self.timerfd, self.settings.heartbeat_timeout_s);
            }
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
        if (container.enabled) {
            self.first_heartbeat_pending = false;
            armTimer(self.timerfd, self.settings.heartbeat_timeout_s);
        }
    }

    /// Reaps every child that has exited. PID 1 inherits orphans, so this runs
    /// for every child, not only the BEAM.
    fn reap(self: *Session) void {
        while (true) {
            var status: i32 = 0;
            const rc = linux.wait4(-1, &status, linux.W.NOHANG, null);
            if (linux.errno(rc) != .SUCCESS or rc == 0) return;
            const pid: linux.pid_t = @intCast(rc);
            if (pid == self.beam) {
                self.beamExited(@bitCast(status));
            } else {
                for (&self.helper_pids) |*helper_pid| {
                    if (helper_pid.* == pid) helper_pid.* = 0;
                }
                self.rearm();
            }
        }
    }

    fn beamExited(self: *Session, status: u32) void {
        logBeamExit(status);
        // Anything the BEAM wrote before exiting still counts: shutdown
        // requests are remembered, and COMMIT/NEXT change the state.
        self.drainControl();
        self.forgetControl();
        if (self.reply_fd >= 0) _ = linux.close(self.reply_fd);
        self.reply_fd = -1;
        self.beam = 0;
        if (container.enabled) stopOwnedChildren(&self.helper_pids);

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
    active_session = &session;
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
        log("beam killed by signal {d}", .{@backingInt(linux.W.TERMSIG(status))});
    }
}

/// Machine PID 1 never exits (ADR-002). OCI stops only this supervisor's
/// descendants and exits for its orchestrator; runtime volumes stay mounted.
fn shutdown(kind: recovery.Shutdown) noreturn {
    if (container.enabled) {
        if (active_session) |session| {
            // Most shutdowns arrive after BEAM exit. A fatal shim path may
            // still have a live BEAM: stop it before PostgreSQL, not after it.
            if (session.beam != 0) {
                _ = linux.kill(session.beam, .TERM);
                const deadline = monotonicMs() + @as(i64, session.settings.heartbeat_timeout_s) * 1000;
                var killed = false;
                while (true) {
                    var status: i32 = 0;
                    const result = linux.wait4(session.beam, &status, linux.W.NOHANG, null);
                    const err = linux.errno(result);
                    if ((err == .SUCCESS and result != 0) or err == .CHILD) break;
                    if (!killed and err != .INTR and monotonicMs() >= deadline) {
                        _ = linux.kill(session.beam, .KILL);
                        killed = true;
                    }
                    sleepMs(25);
                }
                session.beam = 0;
            }
            session.stopHelpers();
        }
        stopOwnedChildren(&.{});
        log("shutdown {t}", .{kind});
        linux.exit_group(container.exitStatus(kind));
    }
    if (active_session) |session| session.stopHelpers();
    // Stragglers first (ARCHITECTURE.md §3.1): ask, then insist. -1 means
    // every process except us, which is what PID 1 is for.
    _ = linux.kill(-1, .TERM);
    sleepMs(50);
    _ = linux.kill(-1, .KILL);
    linux.sync();
    system_image.unmount() catch |err| log("cannot unmount system image ({t})", .{err});
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

/// Child-tree cleanup works for both namespace PID 1 and a provider init's
/// subreaper child. It never sends a namespace-wide or host-wide signal.
fn stopOwnedChildren(excluded: []const linux.pid_t) void {
    const had_children = container.signalChildren(.TERM, excluded) catch |err| {
        log("cannot enumerate owned children ({t}), exiting", .{err});
        linux.exit_group(1);
    };
    if (!had_children) return;
    sleepMs(50);
    while (container.signalChildren(.KILL, excluded) catch |err| {
        log("cannot enumerate owned children ({t}), exiting", .{err});
        linux.exit_group(1);
    }) sleepMs(25);
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
        return std.fmt.bufPrint(buffer, "errno {d}", .{@backingInt(err)}) catch "errno ?";
    return std.fmt.bufPrint(buffer, "E{s}", .{name}) catch "E?";
}

/// Loopback up. A socket to ask with, the flags to keep, one more ioctl to
/// set them; nothing here speaks the network. Not fatal on failure: a boot
/// with no loopback only costs what would have listened on it.
fn bringLoopbackUp() void {
    const fd = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (linux.errno(fd) != .SUCCESS) return;
    defer _ = linux.close(@intCast(fd));

    var flags = netif.interfaceFlags(@intCast(fd), "lo") catch return;
    flags.UP = true;
    flags.RUNNING = true;

    var request: linux.ifreq = std.mem.zeroes(linux.ifreq);
    @memcpy(request.ifrn.name[0..2], "lo");
    request.ifru.flags = flags;
    _ = linux.ioctl(@intCast(fd), linux.SIOCSIFFLAGS, @intFromPtr(&request));
}

/// Address, netmask, then up: the coprocessor link from elixos.coproc_link.
/// Logs the result either way; a failure leaves the boot alone.
fn configureLink(link: cmdline.Link) void {
    const a = link.address;
    if (netif.setLink(link)) |_| {
        log("coproc link {s} {d}.{d}.{d}.{d}/{d}", .{ link.interface, a[0], a[1], a[2], a[3], link.prefix });
    } else |err| {
        log("coproc link {s} failed ({t})", .{ link.interface, err });
    }
}

/// The deck framebuffer from elixos.deck (M33, PROTOCOL.md §12): finds the
/// device, grants it to the BEAM's `video` group and remembers its path for
/// the launch environment. `announce` logs the outcome (§6); a failure only
/// costs the panel.
fn prepareDeck(settings: cmdline.Settings, announce: bool) void {
    const spec = settings.deck orelse return;
    var path_buffer: [deck.max_path + 1]u8 = undefined;
    if (deck.prepareDevice(spec, &path_buffer)) |path| {
        deck_env = zeroed(&deck_environment, "ELIXOS_DECK={s}", .{path});
        if (announce) log("deck {s}", .{path});
    } else |err| {
        if (announce) log("deck {s} failed ({t})", .{ spec.text, err });
    }
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
    // Never truncate a BEAM-owned temporary inode or follow its symlink.
    _ = linux.unlink(tmp_path);
    const raw_fd = linux.open(tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true, .CLOEXEC = true }, 0o644);
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

test "live keeps writable RAM storage without attempting a physical mount" {
    const MountData = struct {
        var calls: usize = 0;

        fn mount(_: []const u8, _: u32) bool {
            calls += 1;
            return false;
        }
    };
    const cases = [_]struct {
        text: []const u8,
        generation: u32 = 0,
        mode: recovery.Mode = .normal,
        attempts: u32 = 1,
    }{
        .{ .text = "elixos.live" },
        .{ .text = "elixos.live=1 elixos.data=/dev/vda elixos.data_wait=4294967295" },
        .{ .text = "elixos.data=/dev/sda elixos.live" },
        .{ .text = "elixos.live elixos.data=/dev/nvme0n1" },
        .{ .text = "elixos.live elixos.safe elixos.generation=9", .mode = .rescue, .attempts = 0 },
        .{ .text = "elixos.safe elixos.live", .mode = .rescue, .attempts = 0 },
        .{ .text = "elixos.live elixos.generation=9", .generation = 9, .attempts = 0 },
    };
    MountData.calls = 0;
    for (cases) |case| {
        const settings = cmdline.parse(case.text);
        const disk_mounted = preparePriv(settings, MountData.mount);
        try std.testing.expect(disk_mounted);
        try std.testing.expectEqual(@as(usize, 0), MountData.calls);
        const plan = recovery.planLaunch(.{}, .{ .max_attempts = settings.max_attempts }, .{
            .safe = settings.safe or !disk_mounted,
            .generation = settings.generation,
        });
        try std.testing.expectEqualDeep(recovery.Plan{
            .launch = .{ .generation = case.generation, .mode = case.mode },
            .next_state = .{ .attempts = case.attempts },
        }, plan);
    }
}

test "persistent storage retains its device, wait and mount-failure behavior" {
    const MountData = struct {
        var calls: usize = 0;
        var seen_device: []const u8 = "";
        var seen_wait_s: u32 = 0;
        var succeeds: bool = false;

        fn mount(device: []const u8, wait_s: u32) bool {
            calls += 1;
            seen_device = device;
            seen_wait_s = wait_s;
            return succeeds;
        }
    };
    const cases = [_]struct {
        text: []const u8,
        device: []const u8 = "/dev/vda",
        wait_s: u32 = 10,
    }{
        .{ .text = "" },
        .{ .text = "elixos.safe" },
        .{ .text = "elixos.live=0 elixos.data=/dev/sda2 elixos.data_wait=3", .device = "/dev/sda2", .wait_s = 3 },
        .{ .text = "elixos.live elixos.live=0 elixos.data=/dev/vdb elixos.data_wait=0", .device = "/dev/vdb", .wait_s = 0 },
        .{ .text = "elixos.live=bad" },
        .{ .text = "elixos.live=0 elixos.live=bad" },
    };
    for (cases) |case| {
        for ([_]bool{ true, false }) |succeeds| {
            MountData.calls = 0;
            MountData.succeeds = succeeds;
            try std.testing.expectEqual(succeeds, preparePriv(cmdline.parse(case.text), MountData.mount));
            try std.testing.expectEqual(@as(usize, 1), MountData.calls);
            try std.testing.expectEqualStrings(case.device, MountData.seen_device);
            try std.testing.expectEqual(case.wait_s, MountData.seen_wait_s);
        }
    }
}

test "a live normal session preserves writable RAM availability in its panic handoff" {
    const helper_pids: [helpers.max_helpers]linux.pid_t = @splat(0);
    rescue.arm(4242, 7, 8, 3, &helper_pids, false, true, null);
    var args: [10][]const u8 = undefined;
    for (&args, 0..) |*arg, index| arg.* = std.mem.span(rescue.argv[index].?);

    const adopted = rescue.parse(&args) orelse return error.TestExpectedAdoption;
    try std.testing.expect(!adopted.safe);
    try std.testing.expect(adopted.disk_mounted);
    try std.testing.expectEqual(@as(u32, 3), adopted.generation);
    try std.testing.expectEqual(@as(linux.pid_t, 4242), adopted.beam_pid);
    try std.testing.expectEqual(@as(linux.fd_t, 7), adopted.ctl_fd);
    try std.testing.expectEqual(@as(linux.fd_t, 8), adopted.reply_fd);
    try std.testing.expectEqual(@as(?recovery.Shutdown, null), adopted.requested);
}

test "the rescue argv round-trips everything an adopted shim needs" {
    var helper_pids: [helpers.max_helpers]linux.pid_t = @splat(0);
    helper_pids[0] = 41;
    helper_pids[31] = 1234;
    rescue.arm(4242, 7, 8, 3, &helper_pids, true, false, .poweroff);

    const args = [_][]const u8{
        std.mem.span(rescue.argv[0].?),
        std.mem.span(rescue.argv[1].?),
        std.mem.span(rescue.argv[2].?),
        std.mem.span(rescue.argv[3].?),
        std.mem.span(rescue.argv[4].?),
        std.mem.span(rescue.argv[5].?),
        std.mem.span(rescue.argv[6].?),
        std.mem.span(rescue.argv[7].?),
        std.mem.span(rescue.argv[8].?),
        std.mem.span(rescue.argv[9].?),
    };
    const adopted = rescue.parse(&args) orelse return error.TestExpectedAdoption;
    try std.testing.expectEqual(@as(linux.pid_t, 4242), adopted.beam_pid);
    try std.testing.expectEqual(@as(linux.fd_t, 7), adopted.ctl_fd);
    try std.testing.expectEqual(@as(linux.fd_t, 8), adopted.reply_fd);
    try std.testing.expectEqual(@as(u32, 3), adopted.generation);
    try std.testing.expectEqualSlices(linux.pid_t, &helper_pids, &adopted.helper_pids);
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

test "interface flags: a real interface parses, a missing one is an error" {
    const fd = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (linux.errno(fd) != .SUCCESS) return error.SkipZigTest;
    defer _ = linux.close(@intCast(fd));

    // Whatever the flags are, a real interface parses; a name the kernel does
    // not know is the ioctl's error, which is what the caller tolerates.
    _ = try netif.interfaceFlags(@intCast(fd), "lo");
    try std.testing.expectError(error.IoctlFailed, netif.interfaceFlags(@intCast(fd), "no_such_if0"));
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
    std.testing.refAllDecls(helpers);
    std.testing.refAllDecls(seal);
    std.testing.refAllDecls(system_image);
    std.testing.refAllDecls(postgres_init);
    std.testing.refAllDecls(container);
    std.testing.refAllDecls(seed);
    std.testing.refAllDecls(@import("gui_io.zig"));
    std.testing.refAllDecls(@import("console_handover.zig"));
    std.testing.refAllDecls(netif);
    std.testing.refAllDecls(@import("ring.zig"));
    std.testing.refAllDecls(@import("link.zig"));
    std.testing.refAllDecls(deck);
    std.testing.refAllDecls(@import("deck_fb.zig"));
}

test "panic adoption preserves the original OCI environment for later relaunch" {
    const before = rescue.envp;
    defer rescue.envp = before;
    const inherited = [_:null]container.Entry{
        "container=oci",
        "ELIXOS_CONSOLE=1",
        "APP_SECRET=never-truncated",
        "ERL_AFLAGS=-eval rejected-on-launch",
    };
    rescue.inheritEnvironment(&inherited);
    const helper_pids: [helpers.max_helpers]linux.pid_t = @splat(0);
    rescue.arm(4242, 7, 8, 3, &helper_pids, false, true, .reboot);
    try std.testing.expectEqual(@as([*:null]const container.Entry, &inherited), rescue.envp);
    try std.testing.expectEqualStrings("APP_SECRET=never-truncated", std.mem.span(rescue.envp[2].?));
    var args: [10][]const u8 = undefined;
    for (&args, 0..) |*arg, index| arg.* = std.mem.span(rescue.argv[index].?);
    const adopted = rescue.parse(&args) orelse return error.TestExpectedAdoption;
    try std.testing.expectEqual(@as(?recovery.Shutdown, .reboot), adopted.requested);
    try std.testing.expect(adopted.disk_mounted);
}
