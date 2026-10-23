//! Native OCI boundaries for the existing shim, not a second service runtime.
//! The image bakes /etc/elixos/runtime as `container\n` and sets `container=oci`.
//! Those explicit markers permit both Docker namespace PID 1 and a Fly-owned
//! init's child entrypoint. The latter becomes a subreaper; neither may signal
//! unrelated processes, mount/unmount runtime filesystems or reboot the kernel.
const std = @import("std");
const linux = std.os.linux;
const decimal = @import("decimal.zig");
const recovery = @import("recovery.zig");

pub const enabled = @import("build_options").container;
pub const Entry = ?[*:0]const u8;
pub const contract_capacity = 17;
pub const Error = error{ InvalidIdentity, MissingMarker, UnsafeMarker, InvalidProc, SubreaperFailed, UnsafePriv, UnwritablePriv, ChildrenUnavailable };

/// Linux's include/linux/proc_ns.h reserves this inode for the initial PID
/// namespace. Reject global PID 1 even if the container binary and markers were
/// accidentally installed as a machine's init. A provider-owned init may run
/// this supervisor as a child in its private VM's initial namespace.
const initial_pid_namespace = 0xEFFFFFFC;

pub fn identityAllowed(pid: linux.pid_t, uid: linux.uid_t, euid: linux.uid_t, pid_namespace: u64, marker: ?[]const u8) bool {
    return pid > 0 and uid == 0 and euid == 0 and
        !(pid == 1 and pid_namespace == initial_pid_namespace) and
        std.mem.eql(u8, marker orelse return false, "oci");
}

/// Refusing a mistaken machine boot must not itself panic the host kernel.
/// An unverified PID namespace is treated conservatively when we are PID 1.
pub fn canExit(pid: linux.pid_t, pid_namespace: ?u64) bool {
    return pid != 1 or (pid_namespace != null and pid_namespace.? != initial_pid_namespace);
}

pub fn exit(status: i32) noreturn {
    if (linux.getpid() == 1) {
        var namespace: linux.Statx = undefined;
        const result = linux.statx(linux.AT.FDCWD, "/proc/self/ns/pid", 0, .{ .INO = true }, &namespace);
        const inode = if (linux.errno(result) == .SUCCESS and namespace.mask.INO) namespace.ino else null;
        if (!canExit(1, inode)) {
            while (true) _ = linux.pause();
        }
    }
    linux.exit_group(status);
}

pub fn value(inherited: []const Entry, key: []const u8) ?[]const u8 {
    var result: ?[]const u8 = null;
    for (inherited) |entry| {
        const text = std.mem.span(entry orelse continue);
        const equals = std.mem.indexOfScalar(u8, text, '=') orelse continue;
        if (std.mem.eql(u8, text[0..equals], key)) result = text[equals + 1 ..];
    }
    return result;
}

pub fn validate(inherited: []const Entry) Error!void {
    // Verify /proc belongs to our PID view, rather than trusting a host bind
    // mount. This read never consults host boot parameters or mount paths.
    var self_buffer: [24]u8 = undefined;
    const self_length = linux.readlinkat(linux.AT.FDCWD, "/proc/self", &self_buffer, self_buffer.len);
    if (linux.errno(self_length) != .SUCCESS or self_length == self_buffer.len) return error.InvalidProc;
    const proc_pid = decimal.parseU32(self_buffer[0..self_length]) orelse return error.InvalidProc;
    if (proc_pid != @as(u32, @intCast(linux.getpid()))) return error.InvalidProc;
    var namespace: linux.Statx = undefined;
    if (linux.errno(linux.statx(linux.AT.FDCWD, "/proc/self/ns/pid", 0, .{ .INO = true }, &namespace)) != .SUCCESS or !namespace.mask.INO)
        return error.InvalidProc;
    if (!identityAllowed(linux.getpid(), linux.getuid(), linux.geteuid(), namespace.ino, value(inherited, "container")))
        return error.InvalidIdentity;

    const raw = linux.openat(linux.AT.FDCWD, "/etc/elixos/runtime", .{ .NOFOLLOW = true, .NONBLOCK = true, .CLOEXEC = true }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.MissingMarker;
    const fd: linux.fd_t = @intCast(raw);
    defer _ = linux.close(fd);
    var metadata: linux.Statx = undefined;
    if (linux.errno(linux.statx(fd, "", linux.AT.EMPTY_PATH, .{ .TYPE = true, .MODE = true, .UID = true, .GID = true, .NLINK = true }, &metadata)) != .SUCCESS or
        !metadata.mask.TYPE or !metadata.mask.MODE or !metadata.mask.UID or !metadata.mask.GID or !metadata.mask.NLINK or
        !linux.S.ISREG(metadata.mode) or metadata.uid != 0 or metadata.gid != 0 or metadata.mode & 0o022 != 0 or metadata.nlink != 1)
        return error.UnsafeMarker;
    var marker: [11]u8 = undefined;
    var used: usize = 0;
    while (used < marker.len) {
        const count = linux.read(fd, marker[used..].ptr, marker.len - used);
        if (linux.errno(count) == .INTR) continue;
        if (linux.errno(count) != .SUCCESS) return error.UnsafeMarker;
        if (count == 0) break;
        used += count;
    }
    if (!std.mem.eql(u8, marker[0..used], "container\n")) return error.UnsafeMarker;
    if (linux.errno(linux.prctl(@backingInt(linux.PR.SET_CHILD_SUBREAPER), 1, 0, 0, 0)) != .SUCCESS)
        return error.SubreaperFailed;
}

pub fn trustedPriv(metadata: *const linux.Statx) bool {
    return linux.S.ISDIR(metadata.mode) and metadata.uid == 0 and metadata.gid == 0 and
        (metadata.mode & 0o022 == 0 or metadata.mode & 0o7777 == 0o1777);
}

/// The runtime supplies /priv. Do not create it or chase a volume-root symlink.
/// The descriptor access check rejects read-only mounts; seal.prepare performs
/// the actual writes and retains all existing state/ownership/sealing checks.
pub fn checkPriv() Error!void {
    const raw = linux.openat(linux.AT.FDCWD, "/priv", .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.UnsafePriv;
    const fd: linux.fd_t = @intCast(raw);
    defer _ = linux.close(fd);
    var metadata: linux.Statx = undefined;
    if (linux.errno(linux.statx(fd, "", linux.AT.EMPTY_PATH, .{ .TYPE = true, .MODE = true, .UID = true, .GID = true }, &metadata)) != .SUCCESS or
        !metadata.mask.TYPE or !metadata.mask.MODE or !metadata.mask.UID or !metadata.mask.GID or !trustedPriv(&metadata))
        return error.UnsafePriv;
    if (linux.errno(linux.faccessat(fd, ".", linux.W_OK | linux.X_OK, 0)) != .SUCCESS) return error.UnwritablePriv;
}

/// All launch-owned names are filtered before adding exactly one authoritative
/// value. ERTS flag/library/loader variables must not bypass the release argv,
/// restore generation, crash limits or the real control/helper descriptors.
pub fn reserved(key: []const u8) bool {
    for ([_][]const u8{
        "ROOTDIR",           "BINDIR",      "EMU",            "PROGNAME",      "HOME",            "TERM",           "LANG",           "PATH",
        "ELIXOS_GENERATION", "ELIXOS_MODE", "ELIXOS_ATTEMPT", "ELIXOS_CTL_FD", "ELIXOS_REPLY_FD", "ELIXOS_RUNTIME", "ELIXOS_CONSOLE",
        // M33: a machine-only device grant; never forwarded from a container's caller.
        "ELIXOS_DECK",
    }) |name| {
        if (std.mem.eql(u8, key, name)) return true;
    }
    return std.mem.startsWith(u8, key, "ERL_") or std.mem.startsWith(u8, key, "ERTS_") or std.mem.startsWith(u8, key, "LD_");
}

fn forwarded(entry: Entry) bool {
    const text = std.mem.span(entry orelse return false);
    const equals = std.mem.indexOfScalar(u8, text, '=') orelse return false;
    return equals != 0 and !reserved(text[0..equals]);
}

/// Only pointer slots are allocated, once before supervision. Strings borrow
/// the immutable startup block. Every relaunch fills the reserved tail in its
/// forked child, without allocation or mutation of the supervisor environment.
pub const Environment = struct {
    entries: [:null]Entry,
    inherited_count: usize,
    console: bool,
    safe: bool,

    pub fn init(allocator: std.mem.Allocator, inherited: []const Entry) !Environment {
        var count: usize = 0;
        for (inherited) |entry| {
            if (forwarded(entry)) count += 1;
        }
        const entries = try allocator.allocSentinel(Entry, count + contract_capacity, null);
        var offset: usize = 0;
        for (inherited) |entry| {
            if (forwarded(entry)) {
                entries[offset] = entry;
                offset += 1;
            }
        }
        return .{
            .entries = entries,
            .inherited_count = count,
            .console = std.mem.eql(u8, value(inherited, "ELIXOS_CONSOLE") orelse "0", "1"),
            .safe = std.mem.eql(u8, value(inherited, "ELIXOS_SAFE") orelse "0", "1"),
        };
    }

    pub fn deinit(self: Environment, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
    }

    pub fn launch(self: *Environment, contract: []const Entry) [:null]const Entry {
        std.debug.assert(contract.len <= contract_capacity);
        var offset = self.inherited_count;
        for (contract) |entry| {
            if (entry != null) {
                self.entries[offset] = entry;
                offset += 1;
            }
        }
        self.entries[offset] = null;
        return self.entries[0..offset :null];
    }
};

pub fn helperAllowed(name: []const u8) bool {
    return std.mem.eql(u8, name, "postgres-init") or std.mem.eql(u8, name, "postgres");
}

/// Adoption arguments are only a handoff, not authority to signal an arbitrary
/// provider process. WNOWAIT proves parenthood without consuming a BEAM/helper
/// exit that the restored supervisor still has to account for.
pub fn ownsChild(pid: linux.pid_t) bool {
    if (pid <= 0) return false;
    while (true) {
        var info: linux.siginfo_t = undefined;
        const result = linux.waitid(.PID, pid, &info, linux.W.EXITED | linux.W.NOHANG | linux.W.NOWAIT, null);
        const err = linux.errno(result);
        if (err == .INTR) continue;
        return err == .SUCCESS;
    }
}

pub fn exitStatus(kind: recovery.Shutdown) i32 {
    return switch (kind) {
        .poweroff, .halt => 0,
        .reboot => 75,
    };
}

/// Enumerate procfs, but signal only PIDs for which wait4 confirms this
/// supervisor is the parent. A live child cannot have its PID reused until we
/// reap it: this process is single-threaded and SIGCHLD is blocked. Deeper
/// descendants reparent to this subreaper and appear in the next pass, even if
/// they escaped a process group. No optional /proc/.../children interface is
/// required. Tracked helpers are excluded during BEAM crash recovery.
pub fn signalChildren(signal: linux.SIG, excluded: []const linux.pid_t) Error!bool {
    const raw = linux.openat(linux.AT.FDCWD, "/proc", .{ .DIRECTORY = true, .CLOEXEC = true, .NOFOLLOW = true }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.ChildrenUnavailable;
    const fd: linux.fd_t = @intCast(raw);
    defer _ = linux.close(fd);
    var buffer: [4096]u8 align(@alignOf(linux.dirent64)) = undefined;
    var found = false;
    while (true) {
        const count = linux.getdents64(fd, &buffer, buffer.len);
        if (linux.errno(count) == .INTR) continue;
        if (linux.errno(count) != .SUCCESS) return error.ChildrenUnavailable;
        if (count == 0) break;
        var offset: usize = 0;
        while (offset < count) {
            if (count - offset < @sizeOf(linux.dirent64)) return error.ChildrenUnavailable;
            const entry: *align(1) const linux.dirent64 = @ptrCast(&buffer[offset]);
            if (entry.reclen < @sizeOf(linux.dirent64) or entry.reclen > count - offset) return error.ChildrenUnavailable;
            const name_bytes = buffer[offset + @offsetOf(linux.dirent64, "name") .. offset + entry.reclen];
            const end = std.mem.indexOfScalar(u8, name_bytes, 0) orelse return error.ChildrenUnavailable;
            offset += entry.reclen;
            const number = decimal.parseU32(name_bytes[0..end]) orelse continue;
            found = signalChild(number, signal, excluded) or found;
        }
    }
    return found;
}

fn signalChild(number: u32, signal: linux.SIG, excluded: []const linux.pid_t) bool {
    if (number == 0 or number > std.math.maxInt(linux.pid_t)) return false;
    const pid: linux.pid_t = @intCast(number);
    for (excluded) |protected| {
        if (pid == protected) return false;
    }
    var status: i32 = 0;
    while (true) {
        const result = linux.wait4(pid, &status, linux.W.NOHANG, null);
        const err = linux.errno(result);
        if (err == .INTR) continue;
        if (err != .SUCCESS) return false; // Not our child: never signal it.
        if (result != 0) return true; // Reaped; rescan for adopted descendants.
        break;
    }
    _ = linux.kill(pid, signal);
    // Reap only this exact child, never consuming a tracked helper's exit.
    _ = linux.wait4(pid, &status, linux.W.NOHANG, null);
    return true;
}

test "refusing an unverified or initial namespace PID1 never permits kernel-panic exit" {
    try std.testing.expect(!canExit(1, null));
    try std.testing.expect(!canExit(1, initial_pid_namespace));
    try std.testing.expect(canExit(1, 12345));
    try std.testing.expect(canExit(42, null));
    try std.testing.expect(canExit(42, initial_pid_namespace));
}

test "container selection requires explicit markers and root but supports provider init" {
    try std.testing.expect(identityAllowed(1, 0, 0, 12345, "oci"));
    try std.testing.expect(identityAllowed(42, 0, 0, initial_pid_namespace, "oci"));
    try std.testing.expect(!identityAllowed(1, 0, 0, initial_pid_namespace, "oci"));
    try std.testing.expect(!identityAllowed(1, 1000, 0, 12345, "oci"));
    try std.testing.expect(!identityAllowed(1, 0, 1000, 12345, "oci"));
    try std.testing.expect(!identityAllowed(1, 0, 0, 12345, null));
    try std.testing.expect(!identityAllowed(1, 0, 0, 12345, "docker"));
}

test "container rescue is an explicit startup choice without host kernel overrides" {
    for ([_][]const Entry{
        &.{},
        &.{"ELIXOS_SAFE=0"},
        &.{"ELIXOS_SAFE=bad"},
        &.{"ELIXOS_SAFE=1"},
    }, 0..) |inherited, index| {
        const environment = try Environment.init(std.testing.allocator, inherited);
        defer environment.deinit(std.testing.allocator);
        try std.testing.expectEqual(index == 3, environment.safe);
    }
}

test "container environment filters every reserved duplicate without copying secrets" {
    const inherited = [_]Entry{
        "DATABASE_URL=postgres://secret", "ROOTDIR=/untrusted",     "ROOTDIR=/also-untrusted", "ELIXOS_CTL_FD=99",
        "ELIXOS_REPLY_FD=98",             "ELIXOS_RUNTIME=machine", "ELIXOS_CONSOLE=1",        "ERL_AFLAGS=-eval bad",
        "ERTS_LIB_DIR=/bad",              "LD_PRELOAD=/bad.so",     "PATH=/bad",               "SECRET_KEY_BASE=with=equals",
        "ELIXOS_APP_PORT=4000",           "EMPTY=",                 "=invalid",                "invalid",
    };
    var environment = try Environment.init(std.testing.allocator, &inherited);
    defer environment.deinit(std.testing.allocator);
    const contract = [_]Entry{ "ROOTDIR=/factory", "ELIXOS_CTL_FD=7", "ELIXOS_REPLY_FD=8", "ELIXOS_RUNTIME=container", "ELIXOS_CONSOLE=1" };
    const launched = environment.launch(&contract);
    try std.testing.expect(environment.console);
    try std.testing.expectEqual(@as(usize, 4), environment.inherited_count);
    try std.testing.expectEqual(@as(usize, 9), launched.len);
    try std.testing.expectEqual(inherited[0], launched[0]);
    try std.testing.expectEqualStrings("with=equals", value(launched, "SECRET_KEY_BASE").?);
    try std.testing.expectEqualStrings("4000", value(launched, "ELIXOS_APP_PORT").?);
    try std.testing.expectEqualStrings("", value(launched, "EMPTY").?);
    try std.testing.expectEqualStrings("/factory", value(launched, "ROOTDIR").?);
    try std.testing.expect(value(launched, "ERL_AFLAGS") == null);
    try std.testing.expect(value(launched, "LD_PRELOAD") == null);
    try std.testing.expectEqualStrings("/untrusted", std.mem.span(inherited[1].?)["ROOTDIR=".len..]);
    try std.testing.expect(launched.ptr[launched.len] == null);
}

test "container environment counts are not capped and console defaults headless" {
    var inherited: [2048]Entry = @splat("APP_SECRET=preserved");
    inherited[inherited.len - 1] = "LAST_SECRET=not-truncated";
    var environment = try Environment.init(std.testing.allocator, &inherited);
    defer environment.deinit(std.testing.allocator);
    const launched = environment.launch(&.{ "ELIXOS_RUNTIME=container", "ELIXOS_CONSOLE=0", null });
    try std.testing.expect(!environment.console);
    try std.testing.expectEqual(inherited.len + 2, launched.len);
    try std.testing.expectEqualStrings("not-truncated", value(launched, "LAST_SECRET").?);
    try std.testing.expect(launched.ptr[launched.len] == null);
}

test "container only permits namespace-local database helpers and shutdown statuses" {
    try std.testing.expect(helperAllowed("postgres-init"));
    try std.testing.expect(helperAllowed("postgres"));
    for ([_][]const u8{ "console-handover", "clock", "dhcp", "hardware", "postgres-extra" }) |name| {
        try std.testing.expect(!helperAllowed(name));
    }
    try std.testing.expectEqual(@as(i32, 0), exitStatus(.poweroff));
    try std.testing.expectEqual(@as(i32, 0), exitStatus(.halt));
    try std.testing.expectEqual(@as(i32, 75), exitStatus(.reboot));
}

test "container volume root must be root owned and cannot be an alias or unsafe writable directory" {
    var metadata = std.mem.zeroes(linux.Statx);
    metadata.mode = linux.S.IFDIR | 0o755;
    try std.testing.expect(trustedPriv(&metadata));
    metadata.mode = linux.S.IFDIR | 0o1777;
    try std.testing.expect(trustedPriv(&metadata));
    metadata.mode = linux.S.IFDIR | 0o777;
    try std.testing.expect(!trustedPriv(&metadata));
    metadata.mode = linux.S.IFLNK | 0o755;
    try std.testing.expect(!trustedPriv(&metadata));
    metadata.mode = linux.S.IFDIR | 0o755;
    metadata.uid = 1000;
    try std.testing.expect(!trustedPriv(&metadata));
}

fn pauseChild() noreturn {
    while (true) _ = linux.pause();
}

fn killAndReap(pid: linux.pid_t) void {
    var status: i32 = 0;
    while (true) {
        const result = linux.wait4(pid, &status, linux.W.NOHANG, null);
        const err = linux.errno(result);
        if (err == .INTR) continue;
        // It has already been reaped: never signal a potentially reused PID.
        if (err != .SUCCESS or result != 0) return;
        _ = linux.kill(pid, .KILL);
        while (linux.errno(linux.wait4(pid, &status, 0, null)) == .INTR) {}
        return;
    }
}

fn childTreeScenario() noreturn {
    exerciseOwnedTree() catch linux.exit_group(1);
    linux.exit_group(0);
}

fn cleanupFixtureChildren() void {
    const delay = linux.timespec{ .sec = 0, .nsec = 1_000_000 };
    for (0..2000) |_| {
        if (!(signalChildren(.KILL, &.{}) catch return)) return;
        _ = linux.nanosleep(&delay, null);
    }
}

fn exerciseOwnedTree() !void {
    if (linux.errno(linux.prctl(@backingInt(linux.PR.SET_CHILD_SUBREAPER), 1, 0, 0, 0)) != .SUCCESS) return error.FixtureFailed;
    defer cleanupFixtureChildren();
    const helper = linux.fork();
    if (linux.errno(helper) != .SUCCESS) return error.FixtureFailed;
    if (helper == 0) pauseChild();
    if (!ownsChild(@intCast(helper)) or ownsChild(linux.getppid()) or ownsChild(0) or ownsChild(-1))
        return error.FixtureFailed;
    var ready: [2]linux.fd_t = undefined;
    if (linux.errno(linux.pipe2(&ready, .{ .CLOEXEC = true, .NONBLOCK = true })) != .SUCCESS) return error.FixtureFailed;
    defer _ = linux.close(ready[0]);
    defer _ = linux.close(ready[1]);
    const owned = linux.fork();
    if (linux.errno(owned) != .SUCCESS) return error.FixtureFailed;
    if (owned == 0) {
        const grandchild = linux.fork();
        if (linux.errno(grandchild) != .SUCCESS) {
            _ = linux.write(ready[1], "0", 1);
            linux.exit_group(1);
        }
        if (grandchild == 0) pauseChild();
        if (linux.write(ready[1], "1", 1) != 1) linux.exit_group(1);
        pauseChild();
    }
    const delay = linux.timespec{ .sec = 0, .nsec = 1_000_000 };
    var ready_seen = false;
    for (0..2000) |_| {
        var byte: [1]u8 = undefined;
        const count = linux.read(ready[0], &byte, 1);
        if (count == 1) {
            if (byte[0] != '1') return error.FixtureFailed;
            ready_seen = true;
            break;
        }
        if (linux.errno(count) != .AGAIN and linux.errno(count) != .INTR) return error.FixtureFailed;
        _ = linux.nanosleep(&delay, null);
    }
    if (!ready_seen) return error.FixtureFailed;
    const excluded = [_]linux.pid_t{@intCast(helper)};
    for (0..2000) |_| {
        if (!(try signalChildren(.KILL, &excluded))) {
            var status: i32 = 0;
            if (linux.wait4(@intCast(helper), &status, linux.W.NOHANG, null) != 0) return error.FixtureFailed;
            // A direct helper and its still-running process are preserved.
            killAndReap(@intCast(helper));
            // A killed parent's grandchildren have all been adopted/reaped.
            if (linux.errno(linux.wait4(-1, &status, linux.W.NOHANG, null)) != .CHILD) return error.FixtureFailed;
            return;
        }
        _ = linux.nanosleep(&delay, null);
    }
    return error.FixtureFailed;
}

test "container subreaper cleanup stops owned descendants but preserves helper and platform siblings" {
    const sibling = linux.fork();
    if (linux.errno(sibling) != .SUCCESS) return error.ForkFailed;
    if (sibling == 0) pauseChild();
    defer killAndReap(@intCast(sibling));
    const supervisor = linux.fork();
    if (linux.errno(supervisor) != .SUCCESS) return error.ForkFailed;
    if (supervisor == 0) childTreeScenario();
    defer killAndReap(@intCast(supervisor));
    const delay = linux.timespec{ .sec = 0, .nsec = 5_000_000 };
    for (0..1000) |_| {
        var status: i32 = 0;
        const result = linux.wait4(@intCast(supervisor), &status, linux.W.NOHANG, null);
        if (result == supervisor) {
            try std.testing.expect(linux.W.IFEXITED(@bitCast(status)));
            try std.testing.expectEqual(@as(u32, 0), linux.W.EXITSTATUS(@bitCast(status)));
            try std.testing.expectEqual(@as(usize, 0), linux.wait4(@intCast(sibling), &status, linux.W.NOHANG, null));
            return;
        }
        if (linux.errno(result) != .SUCCESS and linux.errno(result) != .INTR) return error.WaitFailed;
        _ = linux.nanosleep(&delay, null);
    }
    return error.ChildTreeShutdownTimedOut;
}
