//! M18's service tree: read-only machine image or baked native OCI directory.
const std = @import("std");
const linux = std.os.linux;
const milestone = @import("milestone.zig");
const container_profile = @import("build_options").container;

pub const postgres_uid: linux.uid_t = 70;
pub const postgres_gid: linux.gid_t = 70;
pub const library_environment = "LD_LIBRARY_PATH=/system/lib:/system/usr/lib:/system/usr/lib/postgresql17";
pub const path_environment = "PATH=/system/usr/libexec/postgresql17:/usr/bin:/bin:/usr/sbin:/sbin";

pub const Error = error{ OpenFailed, StatFailed, UnsafePath, LoopFailed, MountFailed, OwnershipFailed, UnmountFailed };

// Linux UAPI linux/loop.h: LOOP_CONFIGURE configures the read-only backing
// descriptor and autoclear atomically, instead of exposing a half-bound loop.
const LoopInfo = extern struct {
    device: u64 = 0,
    inode: u64 = 0,
    rdevice: u64 = 0,
    offset: u64 = 0,
    size_limit: u64 = 0,
    number: u32 = 0,
    encryption_type: u32 = 0,
    encryption_key_size: u32 = 0,
    flags: u32 = 1 | 4, // LO_FLAGS_READ_ONLY | LO_FLAGS_AUTOCLEAR
    file_name: [64]u8 = @splat(0),
    crypt_name: [64]u8 = @splat(0),
    encryption_key: [32]u8 = @splat(0),
    init: [2]u64 = @splat(0),
};
const LoopConfig = extern struct {
    fd: u32,
    block_size: u32 = 0,
    info: LoopInfo = .{},
    reserved: [8]u64 = @splat(0),
};

// Alpine builds ICU and PostgreSQL against absolute data paths. Export only
// those read-only assets; neither the factory nor a BEAM-owned copy carries them.
const data_mounts = [_]struct { source: [*:0]const u8, target: [*:0]const u8 }{
    .{ .source = "/system/usr/share/icu", .target = "/usr/share/icu" },
    .{ .source = "/system/usr/share/zoneinfo", .target = "/usr/share/zoneinfo" },
};

pub fn mounted() bool {
    if (container_profile) {
        verifyBaked() catch return false;
        return true;
    }
    const root_id = mountId("/") catch return false;
    if ((mountId("/system") catch return false) == root_id) return false;
    for (data_mounts) |data| {
        if ((mountId(data.target) catch return false) == root_id) return false;
    }
    return true;
}

fn mountId(path: [*:0]const u8) Error!u64 {
    var metadata: linux.Statx = undefined;
    if (linux.errno(linux.statx(linux.AT.FDCWD, path, linux.AT.SYMLINK_NOFOLLOW, .{ .MNT_ID = true }, &metadata)) != .SUCCESS or !metadata.mask.MNT_ID)
        return error.StatFailed;
    return metadata.mnt_id;
}

pub fn mount() Error!void {
    if (container_profile) return verifyBaked();
    const root_id = try mountId("/");
    if ((try mountId("/system")) == root_id) try mountSystem();
    for (data_mounts) |data| {
        if ((try mountId(data.target)) != root_id) continue;
        if (linux.errno(linux.mount(data.source, data.target, null, linux.MS.BIND, 0)) != .SUCCESS) {
            try unmount();
            return error.MountFailed;
        }
    }
}

fn mountSystem() Error!void {
    const priv = try directory(linux.AT.FDCWD, "/priv");
    defer _ = linux.close(priv);
    const priv_info = try info(priv);
    const system = try directory(priv, "system");
    defer _ = linux.close(system);
    const system_info = try info(system);
    if (system_info.uid != 0 or system_info.gid != 0 or system_info.mode & 0o022 != 0 or system_info.mnt_id != priv_info.mnt_id)
        return error.UnsafePath;
    const raw = linux.openat(system, "system.squashfs", .{ .NOFOLLOW = true, .NONBLOCK = true, .CLOEXEC = true }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.OpenFailed;
    const image: linux.fd_t = @intCast(raw);
    defer _ = linux.close(image);
    const image_info = try info(image);
    if (!trustedImage(&image_info, priv_info.mnt_id)) return error.UnsafePath;

    const control_raw = linux.openat(linux.AT.FDCWD, "/dev/loop-control", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
    if (linux.errno(control_raw) != .SUCCESS) return error.LoopFailed;
    const control: linux.fd_t = @intCast(control_raw);
    defer _ = linux.close(control);
    const index = linux.ioctl(control, 0x4C82, 0); // LOOP_CTL_GET_FREE
    if (linux.errno(index) != .SUCCESS) return error.LoopFailed;
    var buffer: [48]u8 = undefined;
    const loop_path = std.mem.printSentinel(&buffer, "/dev/loop{d}", .{index}, 0) catch return error.LoopFailed;
    const loop_raw = linux.openat(linux.AT.FDCWD, loop_path.ptr, .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
    if (linux.errno(loop_raw) != .SUCCESS) return error.LoopFailed;
    const loop: linux.fd_t = @intCast(loop_raw);
    defer _ = linux.close(loop);
    var config: LoopConfig = .{ .fd = @intCast(image) };
    if (linux.errno(linux.ioctl(loop, 0x4C0A, @intFromPtr(&config))) != .SUCCESS) return error.LoopFailed;
    if (linux.errno(linux.mount(loop_path.ptr, "/system", "squashfs", linux.MS.RDONLY | linux.MS.NOSUID | linux.MS.NODEV, 0)) != .SUCCESS)
        return error.MountFailed;
}

pub fn unmount() Error!void {
    if (container_profile) return;
    const root_id = try mountId("/");
    var failed = false;
    for (data_mounts) |data| {
        const id = mountId(data.target) catch {
            failed = true;
            continue;
        };
        if (id != root_id and linux.errno(linux.umount2(data.target, 0)) != .SUCCESS) failed = true;
    }
    if ((try mountId("/system")) != root_id and linux.errno(linux.umount2("/system", 0)) != .SUCCESS) failed = true;
    if (failed) return error.UnmountFailed;
}

/// OCI supplies a regular, root-owned immutable image tree. ICU and zoneinfo
/// are baked symlinks, never bind mounts. The image producer owns tree-content
/// integrity; this boundary rejects writable roots and unexpected data links.
fn verifyBaked() Error!void {
    const system = try directory(linux.AT.FDCWD, "/system");
    defer _ = linux.close(system);
    if (!trustedBakedDirectory(&(try info(system)))) return error.UnsafePath;
    for (data_mounts) |data| {
        const source = try directory(linux.AT.FDCWD, data.source);
        defer _ = linux.close(source);
        if (!trustedBakedDirectory(&(try info(source)))) return error.UnsafePath;
        var link_buffer: [128]u8 = undefined;
        const length = linux.readlinkat(linux.AT.FDCWD, data.target, &link_buffer, link_buffer.len);
        if (linux.errno(length) != .SUCCESS or length == link_buffer.len or
            !std.mem.eql(u8, link_buffer[0..length], std.mem.span(data.source))) return error.UnsafePath;
    }
}

fn trustedBakedDirectory(metadata: *const linux.Statx) bool {
    return linux.S.ISDIR(metadata.mode) and metadata.uid == 0 and metadata.gid == 0 and metadata.mode & 0o022 == 0;
}

/// Only root or the database account may already own the cluster directories.
/// Never transfer a directory the BEAM may hold open to the database identity.
pub fn preparePostgres() Error!void {
    const priv = try directory(linux.AT.FDCWD, "/priv");
    defer _ = linux.close(priv);
    const mount_id = (try info(priv)).mnt_id;
    const postgres = try ownedDirectory(priv, "postgres", 0, 0, 0o755, mount_id);
    defer _ = linux.close(postgres);
    const data = try ownedDirectory(postgres, "data", postgres_uid, postgres_gid, 0o700, mount_id);
    defer _ = linux.close(data);
    const logs = try ownedDirectory(postgres, "log", postgres_uid, postgres_gid, 0o755, mount_id);
    defer _ = linux.close(logs);
}

fn directory(parent: linux.fd_t, name: [*:0]const u8) Error!linux.fd_t {
    const raw = linux.openat(parent, name, .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.OpenFailed;
    return @intCast(raw);
}

fn info(fd: linux.fd_t) Error!linux.Statx {
    var metadata: linux.Statx = undefined;
    if (linux.errno(linux.statx(fd, "", linux.AT.EMPTY_PATH | linux.AT.SYMLINK_NOFOLLOW, .{
        .TYPE = true,
        .MODE = true,
        .UID = true,
        .GID = true,
        .NLINK = true,
        .MNT_ID = true,
    }, &metadata)) != .SUCCESS) return error.StatFailed;
    if (!metadata.mask.TYPE or !metadata.mask.MODE or !metadata.mask.UID or !metadata.mask.GID or !metadata.mask.NLINK or !metadata.mask.MNT_ID)
        return error.StatFailed;
    return metadata;
}

fn trustedImage(metadata: *const linux.Statx, mount_id: u64) bool {
    return linux.S.ISREG(metadata.mode) and metadata.uid == 0 and metadata.gid == 0 and
        metadata.mode & 0o222 == 0 and metadata.nlink == 1 and metadata.mnt_id == mount_id;
}

fn ownedDirectory(parent: linux.fd_t, name: [*:0]const u8, uid: linux.uid_t, gid: linux.gid_t, permissions: linux.mode_t, mount_id: u64) Error!linux.fd_t {
    const created = linux.errno(linux.mkdirat(parent, name, permissions));
    if (created != .SUCCESS and created != .EXIST) return error.OpenFailed;
    const fd = try directory(parent, name);
    errdefer _ = linux.close(fd);
    const metadata = try info(fd);
    if (metadata.mnt_id != mount_id or (metadata.uid != 0 and metadata.uid != uid)) return error.UnsafePath;
    if (linux.errno(linux.fchown(fd, uid, gid)) != .SUCCESS or linux.errno(linux.fchmod(fd, permissions)) != .SUCCESS)
        return error.OwnershipFailed;
    return fd;
}

test "system image rejects writable, foreign-owned and aliased executable images" {
    try milestone.require(18);
    var metadata = std.mem.zeroes(linux.Statx);
    metadata.mode = linux.S.IFREG | 0o444;
    metadata.nlink = 1;
    metadata.mnt_id = 9;
    try std.testing.expect(trustedImage(&metadata, 9));
    metadata.mode |= 0o200;
    try std.testing.expect(!trustedImage(&metadata, 9));
    metadata.mode = linux.S.IFREG | 0o444;
    metadata.uid = 1000;
    try std.testing.expect(!trustedImage(&metadata, 9));
    metadata.uid = 0;
    metadata.nlink = 2;
    try std.testing.expect(!trustedImage(&metadata, 9));
    metadata.nlink = 1;
    try std.testing.expect(!trustedImage(&metadata, 10));
    metadata.mode = linux.S.IFLNK | 0o444;
    try std.testing.expect(!trustedImage(&metadata, 9));
}

test "baked service tree accepts regular immutable roots without requiring another mount" {
    var metadata = std.mem.zeroes(linux.Statx);
    metadata.mode = linux.S.IFDIR | 0o555;
    metadata.mnt_id = 1;
    try std.testing.expect(trustedBakedDirectory(&metadata));
    metadata.mode = linux.S.IFDIR | 0o755;
    try std.testing.expect(trustedBakedDirectory(&metadata));
    metadata.mode |= 0o020;
    try std.testing.expect(!trustedBakedDirectory(&metadata));
    metadata.mode = linux.S.IFLNK | 0o755;
    try std.testing.expect(!trustedBakedDirectory(&metadata));
    metadata.mode = linux.S.IFDIR | 0o555;
    metadata.uid = 1000;
    try std.testing.expect(!trustedBakedDirectory(&metadata));
}
