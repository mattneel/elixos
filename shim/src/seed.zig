//! One-time initialization of a native application image's runtime volume.
//! A committed, immutable /usr/share/elixos/seed is never an upgrade mechanism:
//! existing boot.state always wins, and interrupted/non-pristine volumes fail
//! closed. The normal state parser, sealing and recovery run after publication.
const std = @import("std");
const linux = std.os.linux;
const statefile = @import("statefile.zig");
const seal = @import("seal.zig");

const seed_path = "/usr/share/elixos/seed";
const seed_state = ".container.boot.state";
const pending_path = ".container.seed.pending";
const max_depth = 64;

pub const Error = error{ OpenFailed, StatFailed, ReadFailed, UnsafeSeed, PopulatedVolume, OwnershipFailed, CopyFailed, SyncFailed, PublishFailed, TooDeep };
pub const Selection = enum { existing, absent, initialize, refuse };

pub fn select(has_state: bool, has_seed: bool, is_pristine: bool) Selection {
    if (has_state) return .existing;
    if (!has_seed) return .absent;
    return if (is_pristine) .initialize else .refuse;
}

pub fn initialize() Error!bool {
    const priv = try directory(linux.AT.FDCWD, "/priv");
    defer _ = linux.close(priv);
    // Even an invalid existing state is evidence, not permission to replace it.
    if (try exists(priv, "boot.state")) return false;
    const seed_raw = linux.openat(linux.AT.FDCWD, seed_path, .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (linux.errno(seed_raw) == .NOENT) return false;
    if (linux.errno(seed_raw) != .SUCCESS) return error.UnsafeSeed;
    const source: linux.fd_t = @intCast(seed_raw);
    defer _ = linux.close(source);
    const source_info = try info(source);
    if (!trustedEntry(&source_info, source_info.mnt_id)) return error.UnsafeSeed;
    try walk(source, source_info.mnt_id, 0, .source, false);
    try checkState(source);
    const mount_id = (try info(priv)).mnt_id;
    if (select(false, true, try pristine(priv, mount_id)) != .initialize) return error.PopulatedVolume;

    // Close the only writable namespace before root's cp runs. Empty initial
    // directories are claimed too, so a retained unprivileged descriptor cannot
    // plant destination links after the pristine scan. No populated path is
    // ever copied over, removed, or recursively ownership-migrated here.
    if (linux.errno(linux.fchmod(priv, 0o755)) != .SUCCESS) return error.OwnershipFailed;
    var initial = Reader{ .fd = priv };
    while (try initial.next()) |name| {
        const fd = try directory(priv, name.ptr);
        defer _ = linux.close(fd);
        if (linux.errno(linux.fchown(fd, 0, 0)) != .SUCCESS or linux.errno(linux.fchmod(fd, 0o700)) != .SUCCESS)
            return error.OwnershipFailed;
    }
    if (!try pristine(priv, mount_id)) return error.PopulatedVolume;
    const pending_raw = linux.openat(priv, pending_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true, .CLOEXEC = true }, 0o600);
    if (linux.errno(pending_raw) != .SUCCESS) return error.PopulatedVolume;
    const pending: linux.fd_t = @intCast(pending_raw);
    defer _ = linux.close(pending);
    if (linux.errno(linux.fsync(pending)) != .SUCCESS or linux.errno(linux.fsync(priv)) != .SUCCESS) return error.SyncFailed;

    try copy();
    // Sync only copied files/directories, never the kernel's global sync or an
    // entire possibly shared filesystem. A durable boot.state publishes last.
    try walk(priv, mount_id, 0, .copied, false);
    try checkState(priv);
    if (linux.errno(linux.unlinkat(priv, pending_path, 0)) != .SUCCESS or linux.errno(linux.fsync(priv)) != .SUCCESS)
        return error.SyncFailed;
    if (linux.errno(linux.renameat2(priv, seed_state, priv, "boot.state", .{ .NOREPLACE = true })) != .SUCCESS)
        return error.PublishFailed;
    if (linux.errno(linux.fsync(priv)) != .SUCCESS) return error.SyncFailed;
    return true;
}

fn copy() Error!void {
    const child = linux.fork();
    if (linux.errno(child) != .SUCCESS) return error.CopyFailed;
    if (child == 0) {
        // The validated seed roots are disjoint from the only allowed empty
        // initial directories, and /priv's namespace is already root-closed.
        // BusyBox -n would skip the existing /priv directory itself, including
        // every child; no-clobber comes from the pristine check, not cp flags.
        // No shell, inherited environment or VM environment mutation.
        _ = linux.syscall1(.umask, 0o022);
        const argv = [_:null]?[*:0]const u8{ "/bin/busybox", "cp", "-R", "-P", seed_path ++ "/.", "/priv/" };
        const envp = [_:null]?[*:0]const u8{ "PATH=/bin:/usr/bin", "LANG=C" };
        _ = linux.execve("/bin/busybox", &argv, &envp);
        linux.exit_group(1);
    }
    while (true) {
        var status: i32 = 0;
        const result = linux.wait4(@intCast(child), &status, 0, null);
        const err = linux.errno(result);
        if (err == .INTR) continue;
        if (err != .SUCCESS or result != child or !linux.W.IFEXITED(@bitCast(status)) or linux.W.EXITSTATUS(@bitCast(status)) != 0)
            return error.CopyFailed;
        return;
    }
}

const WalkMode = enum { source, copied };

fn walk(parent: linux.fd_t, mount_id: u64, depth: usize, mode: WalkMode, writable: bool) Error!void {
    if (depth == max_depth) return error.TooDeep;
    const scan = try directory(parent, ".");
    defer _ = linux.close(scan);
    var reader = Reader{ .fd = scan };
    while (try reader.next()) |name| {
        if (depth == 0) {
            if (mode == .copied and std.mem.eql(u8, name, pending_path)) continue;
            if (mode == .copied and initialDirectory(name)) {
                const empty = try directory(parent, name.ptr);
                defer _ = linux.close(empty);
                const metadata = try info(empty);
                if (!trustedInitialDirectory(name, &metadata, mount_id) or !try emptyDirectory(empty)) return error.PopulatedVolume;
                if (linux.errno(linux.fsync(empty)) != .SUCCESS) return error.SyncFailed;
                continue;
            }
            if (!seedRoot(name)) return error.UnsafeSeed;
        }
        const raw = linux.openat(parent, name.ptr, .{ .PATH = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
        if (linux.errno(raw) != .SUCCESS) return error.UnsafeSeed;
        const fd: linux.fd_t = @intCast(raw);
        defer _ = linux.close(fd);
        const metadata = try info(fd);
        if (!trustedEntry(&metadata, mount_id)) return error.UnsafeSeed;
        if (depth == 0 and (directoryRoot(name) != linux.S.ISDIR(metadata.mode))) return error.UnsafeSeed;
        const mutable = mode == .copied and (writable or (depth == 0 and writableRoot(name)));
        if (linux.S.ISDIR(metadata.mode)) {
            const child = try directory(fd, ".");
            defer _ = linux.close(child);
            try walk(child, mount_id, depth + 1, mode, mutable);
        } else if (mode == .copied) {
            const file_raw = linux.openat(parent, name.ptr, .{ .NOFOLLOW = true, .NONBLOCK = true, .CLOEXEC = true }, 0);
            if (linux.errno(file_raw) != .SUCCESS) return error.UnsafeSeed;
            const file: linux.fd_t = @intCast(file_raw);
            defer _ = linux.close(file);
            const copied_info = try info(file);
            if (!trustedEntry(&copied_info, mount_id)) return error.UnsafeSeed;
            if (mutable and linux.errno(linux.fchmod(file, runtimeFilePermissions(copied_info.mode, depth == 0 and std.mem.eql(u8, name, "journal.log")))) != .SUCCESS)
                return error.OwnershipFailed;
            if (linux.errno(linux.fsync(file)) != .SUCCESS) return error.SyncFailed;
        }
    }
    if (mode == .copied) {
        // apps/hex and the journal are normal writable installed state, unlike
        // the root-sealed generations/store. seal.prepare owns the former for
        // BEAM1000 and retains the latter's existing recovery boundary.
        if (writable and linux.errno(linux.fchmod(parent, 0o755)) != .SUCCESS) return error.OwnershipFailed;
        if (linux.errno(linux.fsync(parent)) != .SUCCESS) return error.SyncFailed;
    }
}

fn writableRoot(name: []const u8) bool {
    return std.mem.eql(u8, name, "apps") or std.mem.eql(u8, name, "hex") or std.mem.eql(u8, name, "journal.log");
}

fn runtimeFilePermissions(mode: linux.mode_t, journal: bool) linux.mode_t {
    return if (journal) 0o644 else if (mode & 0o111 != 0) 0o755 else 0o644;
}

fn seedRoot(name: []const u8) bool {
    return directoryRoot(name) or std.mem.eql(u8, name, "journal.log") or std.mem.eql(u8, name, seed_state);
}

fn directoryRoot(name: []const u8) bool {
    for ([_][]const u8{ "apps", "generations", "store", "hex" }) |allowed| {
        if (std.mem.eql(u8, name, allowed)) return true;
    }
    return false;
}

fn initialDirectory(name: []const u8) bool {
    return std.mem.eql(u8, name, "home") or std.mem.eql(u8, name, "postgres") or std.mem.eql(u8, name, "lost+found");
}

fn trustedEntry(metadata: *const linux.Statx, mount_id: u64) bool {
    const permissions = metadata.mode & 0o7777;
    return ((linux.S.ISDIR(metadata.mode) and permissions == 0o555) or
        (linux.S.ISREG(metadata.mode) and metadata.nlink == 1 and (permissions == 0o444 or permissions == 0o555))) and
        metadata.uid == 0 and metadata.gid == 0 and metadata.mnt_id == mount_id;
}

fn trustedInitialDirectory(name: []const u8, metadata: *const linux.Statx, mount_id: u64) bool {
    const home = std.mem.eql(u8, name, "home");
    return initialDirectory(name) and linux.S.ISDIR(metadata.mode) and metadata.mnt_id == mount_id and metadata.mode & 0o022 == 0 and
        (metadata.uid == 0 or (home and metadata.uid == seal.uid)) and (metadata.gid == 0 or (home and metadata.gid == seal.gid));
}

fn pristine(parent: linux.fd_t, mount_id: u64) Error!bool {
    // Each reader owns an independent directory offset, including rescans.
    const scan = try directory(parent, ".");
    defer _ = linux.close(scan);
    var reader = Reader{ .fd = scan };
    while (try reader.next()) |name| {
        if (!initialDirectory(name)) return false;
        const fd = directory(parent, name.ptr) catch return false;
        defer _ = linux.close(fd);
        const metadata = try info(fd);
        if (!trustedInitialDirectory(name, &metadata, mount_id) or !try emptyDirectory(fd)) return false;
    }
    return true;
}

fn emptyDirectory(fd: linux.fd_t) Error!bool {
    var reader = Reader{ .fd = fd };
    return (try reader.next()) == null;
}

fn exists(parent: linux.fd_t, name: [*:0]const u8) Error!bool {
    const raw = linux.openat(parent, name, .{ .PATH = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (linux.errno(raw) == .NOENT) return false;
    if (linux.errno(raw) != .SUCCESS) return error.OpenFailed;
    _ = linux.close(@intCast(raw));
    return true;
}

fn checkState(parent: linux.fd_t) Error!void {
    const raw = linux.openat(parent, seed_state, .{ .NOFOLLOW = true, .NONBLOCK = true, .CLOEXEC = true }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.UnsafeSeed;
    const fd: linux.fd_t = @intCast(raw);
    defer _ = linux.close(fd);
    var buffer: [128]u8 = undefined;
    var used: usize = 0;
    while (used < buffer.len) {
        const count = linux.read(fd, buffer[used..].ptr, buffer.len - used);
        if (linux.errno(count) == .INTR) continue;
        if (linux.errno(count) != .SUCCESS) return error.ReadFailed;
        if (count == 0) {
            const state = statefile.parse(buffer[0..used]) catch return error.UnsafeSeed;
            if (state.current == 0 or state.current != state.last_good) return error.UnsafeSeed;
            return;
        }
        used += count;
    }
    return error.UnsafeSeed;
}

fn directory(parent: linux.fd_t, name: [*:0]const u8) Error!linux.fd_t {
    const raw = linux.openat(parent, name, .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.OpenFailed;
    return @intCast(raw);
}

fn info(fd: linux.fd_t) Error!linux.Statx {
    var metadata: linux.Statx = undefined;
    if (linux.errno(linux.statx(fd, "", linux.AT.EMPTY_PATH, .{ .TYPE = true, .MODE = true, .UID = true, .GID = true, .NLINK = true, .MNT_ID = true }, &metadata)) != .SUCCESS or
        !metadata.mask.TYPE or !metadata.mask.MODE or !metadata.mask.UID or !metadata.mask.GID or !metadata.mask.NLINK or !metadata.mask.MNT_ID)
        return error.StatFailed;
    return metadata;
}

const Reader = struct {
    fd: linux.fd_t,
    buffer: [4096]u8 align(@alignOf(linux.dirent64)) = undefined,
    used: usize = 0,
    cursor: usize = 0,

    fn next(self: *Reader) Error!?[:0]const u8 {
        while (true) {
            if (self.cursor == self.used) {
                const count = linux.getdents64(self.fd, &self.buffer, self.buffer.len);
                if (linux.errno(count) == .INTR) continue;
                if (linux.errno(count) != .SUCCESS) return error.ReadFailed;
                if (count == 0) return null;
                self.used = count;
                self.cursor = 0;
            }
            if (self.used - self.cursor < @sizeOf(linux.dirent64)) return error.ReadFailed;
            const entry: *align(1) const linux.dirent64 = @ptrCast(&self.buffer[self.cursor]);
            if (entry.reclen < @sizeOf(linux.dirent64) or entry.reclen > self.used - self.cursor) return error.ReadFailed;
            const bytes = self.buffer[self.cursor + @offsetOf(linux.dirent64, "name") .. self.cursor + entry.reclen];
            const end = std.mem.indexOfScalar(u8, bytes, 0) orelse return error.ReadFailed;
            self.cursor += entry.reclen;
            const name = bytes[0..end :0];
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            return name;
        }
    }
};

test "seed selection never replaces existing state and refuses partial initialization" {
    for ([_]bool{ false, true }) |has_seed| {
        for ([_]bool{ false, true }) |is_pristine| {
            try std.testing.expectEqual(Selection.existing, select(true, has_seed, is_pristine));
        }
    }
    try std.testing.expectEqual(Selection.absent, select(false, false, false));
    try std.testing.expectEqual(Selection.initialize, select(false, true, true));
    try std.testing.expectEqual(Selection.refuse, select(false, true, false));
    try std.testing.expect(!seedRoot("boot.state"));
    for ([_][]const u8{ "home", "postgres", "crash", "data", "toolchain", "system", pending_path }) |name| {
        try std.testing.expect(!seedRoot(name));
    }
}

test "seed trust rejects writable foreign aliased linked and mounted artifacts" {
    var metadata = std.mem.zeroes(linux.Statx);
    metadata.mode = linux.S.IFREG | 0o444;
    metadata.nlink = 1;
    metadata.mnt_id = 9;
    try std.testing.expect(trustedEntry(&metadata, 9));
    metadata.mode |= 0o200;
    try std.testing.expect(!trustedEntry(&metadata, 9));
    metadata.mode = linux.S.IFLNK | 0o444;
    try std.testing.expect(!trustedEntry(&metadata, 9));
    metadata.mode = linux.S.IFREG | 0o444;
    metadata.nlink = 2;
    try std.testing.expect(!trustedEntry(&metadata, 9));
    metadata.nlink = 1;
    metadata.uid = 1000;
    try std.testing.expect(!trustedEntry(&metadata, 9));
    metadata.uid = 0;
    try std.testing.expect(!trustedEntry(&metadata, 10));
}

test "seed pristine boundary rejects links populated paths and interrupted copies" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    const parent = temporary.dir.handle;
    const mount_id = (try info(parent)).mnt_id;
    try std.testing.expect(try pristine(parent, mount_id));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.symlinkat("/tmp", parent, "home")));
    try std.testing.expect(!try pristine(parent, mount_id));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.unlinkat(parent, "home", 0)));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.mkdirat(parent, "apps", 0o755)));
    try std.testing.expect(!try pristine(parent, mount_id));
    try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(linux.unlinkat(parent, "apps", linux.AT.REMOVEDIR)));
    const raw = linux.openat(parent, pending_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .CLOEXEC = true }, 0o600);
    if (linux.errno(raw) != .SUCCESS) return error.OpenFailed;
    _ = linux.close(@intCast(raw));
    try std.testing.expect(!try pristine(parent, mount_id));
    try std.testing.expect(try exists(parent, pending_path));
    try std.testing.expect(!try exists(parent, "boot.state"));
}

test "seed runtime permissions restore journal and installed state without changing recovery roots" {
    try std.testing.expect(writableRoot("apps"));
    try std.testing.expect(writableRoot("hex"));
    try std.testing.expect(writableRoot("journal.log"));
    try std.testing.expect(!writableRoot("store"));
    try std.testing.expect(!writableRoot("generations"));
    try std.testing.expect(!writableRoot(seed_state));
    try std.testing.expectEqual(@as(linux.mode_t, 0o644), runtimeFilePermissions(0o444, false));
    try std.testing.expectEqual(@as(linux.mode_t, 0o755), runtimeFilePermissions(0o555, false));
    try std.testing.expectEqual(@as(linux.mode_t, 0o644), runtimeFilePermissions(0o555, true));
}
