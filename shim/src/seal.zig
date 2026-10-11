//! M17's root-owned recovery boundary. Only the single-threaded shim calls this
//! module: fixed storage is shared between startup ownership migration and COMMIT.
//! Candidate descriptors always retain the old inode, never the published copy.
const std = @import("std");
const linux = std.os.linux;
const milestone = @import("milestone.zig");

pub const uid: linux.uid_t = 1000;
pub const gid: linux.gid_t = 1000;
pub const supplementary_groups = [_]linux.gid_t{ 23, 27 };

pub const Error = error{
    OpenFailed,
    StatFailed,
    UnsafePath,
    OwnershipFailed,
    PermissionFailed,
    ReadFailed,
    WriteFailed,
    SyncFailed,
    RenameFailed,
    RemoveFailed,
    TooLarge,
    TooDeep,
    InvalidManifest,
    InvalidGeneration,
    TooManyModules,
    HashMismatch,
};

const max_manifest = 4 * 1024 * 1024;
const max_modules = 4096;
const max_depth = 64;
const hex = "0123456789abcdef";
var manifest_buffer: [max_manifest]u8 = undefined;
var module_offsets: [max_modules]u32 = undefined;
var copy_buffer: [64 * 1024]u8 = undefined;

const Frame = struct {
    fd: linux.fd_t,
    buffer: [4096]u8 = undefined,
    used: usize = 0,
    cursor: usize = 0,
};
var frames: [max_depth]Frame = undefined;

/// Prepare even a rescue boot without a mounted disk. Ownership migration never
/// descends through links or changes an inode shared with a protected file.
pub fn prepare() Error!void {
    const root = try openDirectory(linux.AT.FDCWD, "/");
    defer _ = linux.close(root);
    const priv = try makeDirectory(root, "priv", 0o1777, null);
    defer _ = linux.close(priv);
    const location = try info(priv);
    const generations = try makeDirectory(priv, "generations", 0o1777, location.mnt_id);
    defer _ = linux.close(generations);
    const store = try makeDirectory(priv, "store", 0o1777, location.mnt_id);
    defer _ = linux.close(store);
    const staging = try makeDirectory(priv, ".seal", 0o700, location.mnt_id);
    defer _ = linux.close(staging);

    for (0..256) |index| {
        const name: [2:0]u8 = .{ hex[index >> 4], hex[index & 15] };
        const fanout = try makeDirectory(store, &name, 0o1777, location.mnt_id);
        _ = linux.close(fanout);
    }

    const state_raw = linux.openat(priv, "boot.state", .{
        .NOFOLLOW = true,
        .NONBLOCK = true,
        .CLOEXEC = true,
    }, 0);
    if (linux.errno(state_raw) == .SUCCESS) {
        const state: linux.fd_t = @intCast(state_raw);
        defer _ = linux.close(state);
        const metadata = try info(state);
        if (!linux.S.ISREG(metadata.mode) or metadata.mnt_id != location.mnt_id)
            return error.UnsafePath;
        try own(state, 0, 0);
        try mode(state, 0o644);
        try sync(state);
    } else if (linux.errno(state_raw) != .NOENT) {
        return error.UnsafePath;
    }
    try migrateWritable(priv, staging, location.mnt_id);
    try sync(staging);
    try sync(generations);
    try sync(store);
    try sync(priv);
}

/// Snapshot the actual ETF manifest, verify its references, then publish the
/// manifest last. A failure may leave verified sealed blobs, but never advances
/// boot.state: its publication is the caller's responsibility after success.
pub fn commit(generation: u32) Error!void {
    if (generation == 0) return error.InvalidGeneration;
    const root = try openDirectory(linux.AT.FDCWD, "/");
    defer _ = linux.close(root);
    const priv = try trustedDirectory(root, "priv", 0o1777, null);
    defer _ = linux.close(priv);
    const location = try info(priv);
    const generations = try trustedDirectory(priv, "generations", 0o1777, location.mnt_id);
    defer _ = linux.close(generations);
    const store = try trustedDirectory(priv, "store", 0o1777, location.mnt_id);
    defer _ = linux.close(store);
    const staging = try trustedDirectory(priv, ".seal", 0o700, location.mnt_id);
    defer _ = linux.close(staging);
    const name = generationName(generation);
    const source = try openRegular(generations, &name, location.mnt_id);
    defer _ = linux.close(source);
    const metadata = try info(source);
    if (metadata.size > max_manifest) return error.TooLarge;
    const length: usize = @intCast(metadata.size);
    try readExact(source, manifest_buffer[0..length]);
    try expectEof(source);

    // EXCL plus a root-private parent gives a fresh inode even after a crash or
    // when an attacker planted this pathname before the initial preparation.
    const snapshot = try temporary(staging, "manifest.tmp");
    defer _ = linux.close(snapshot);
    defer _ = linux.unlinkat(staging, "manifest.tmp", 0);
    try writeAll(snapshot, manifest_buffer[0..length]);
    const count = try parseManifest(manifest_buffer[0..length], generation, &module_offsets);
    const bytes: []const u8 = manifest_buffer[0..length];
    std.mem.sortUnstable(u32, module_offsets[0..count], bytes, lessHash);
    var previous: ?u32 = null;
    for (module_offsets[0..count]) |offset| {
        const start: usize = offset;
        const hash = bytes[start..][0..64];
        if (previous) |old| {
            if (std.mem.eql(u8, bytes[old..][0..64], hash)) continue;
        }
        try sealBlob(store, staging, location.mnt_id, hash);
        previous = offset;
    }
    try own(snapshot, 0, 0);
    try mode(snapshot, 0o444);
    try sync(snapshot);
    if (linux.errno(linux.renameat(staging, "manifest.tmp", generations, &name)) != .SUCCESS)
        return error.RenameFailed;
    try sync(generations);
    try sync(staging);
}

fn lessHash(bytes: []const u8, left: u32, right: u32) bool {
    return std.mem.order(u8, bytes[left..][0..64], bytes[right..][0..64]) == .lt;
}

fn sealBlob(store: linux.fd_t, staging: linux.fd_t, mount: u64, hash: []const u8) Error!void {
    const directory_name: [2:0]u8 = .{ hash[0], hash[1] };
    const directory = try trustedDirectory(store, &directory_name, 0o1777, mount);
    defer _ = linux.close(directory);
    var name: [62:0]u8 = undefined;
    @memcpy(name[0..62], hash[2..64]);
    name[62] = 0;
    const source = try openRegular(directory, &name, mount);
    defer _ = linux.close(source);
    const metadata = try info(source);
    const already_sealed = metadata.uid == 0 and metadata.gid == 0 and
        metadata.mode & 0o7777 == 0o444;
    if (already_sealed) {
        // Never overwrite recovery content, even when its name is right but its
        // bytes are damaged. Reuse is safe only after verifying the inode itself.
        try stream(source, null, metadata.size, hash);
        return;
    }
    const destination = try temporary(staging, "blob.tmp");
    defer _ = linux.close(destination);
    defer _ = linux.unlinkat(staging, "blob.tmp", 0);
    try stream(source, destination, metadata.size, hash);
    try own(destination, 0, 0);
    try mode(destination, 0o444);
    try sync(destination);
    if (linux.errno(linux.renameat(staging, "blob.tmp", directory, &name)) != .SUCCESS)
        return error.RenameFailed;
    try sync(directory);
    try sync(staging);
}

fn generationName(generation: u32) [14:0]u8 {
    var result: [14:0]u8 = @splat(0);
    var digits: [10]u8 = undefined;
    var count: usize = 0;
    var number = generation;
    while (true) {
        digits[count] = '0' + @as(u8, @intCast(number % 10));
        count += 1;
        number /= 10;
        if (number == 0) break;
    }
    for (0..count) |index| result[index] = digits[count - index - 1];
    @memcpy(result[count..][0..4], ".gen");
    return result;
}

fn openDirectory(parent: linux.fd_t, name: [*:0]const u8) Error!linux.fd_t {
    const raw = linux.openat(parent, name, .{
        .DIRECTORY = true,
        .NOFOLLOW = true,
        .CLOEXEC = true,
    }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.OpenFailed;
    return @intCast(raw);
}

fn makeDirectory(parent: linux.fd_t, name: [*:0]const u8, permissions: linux.mode_t, mount: ?u64) Error!linux.fd_t {
    const created = linux.errno(linux.mkdirat(parent, name, permissions));
    if (created != .SUCCESS and created != .EXIST) return error.OpenFailed;
    const fd = try openDirectory(parent, name);
    errdefer _ = linux.close(fd);
    const metadata = try info(fd);
    if (mount) |expected| {
        if (metadata.mnt_id != expected) return error.UnsafePath;
    }
    try own(fd, 0, 0);
    try mode(fd, permissions);
    try sync(fd);
    return fd;
}

fn trustedDirectory(parent: linux.fd_t, name: [*:0]const u8, permissions: linux.mode_t, mount: ?u64) Error!linux.fd_t {
    const fd = try openDirectory(parent, name);
    errdefer _ = linux.close(fd);
    const metadata = try info(fd);
    if (metadata.uid != 0 or metadata.gid != 0 or metadata.mode & 0o7777 != permissions)
        return error.UnsafePath;
    if (mount) |expected| {
        if (metadata.mnt_id != expected) return error.UnsafePath;
    }
    return fd;
}

fn openRegular(parent: linux.fd_t, name: [*:0]const u8, mount: u64) Error!linux.fd_t {
    const raw = linux.openat(parent, name, .{
        .NOFOLLOW = true,
        .NONBLOCK = true,
        .CLOEXEC = true,
    }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.OpenFailed;
    const fd: linux.fd_t = @intCast(raw);
    errdefer _ = linux.close(fd);
    const metadata = try info(fd);
    if (!linux.S.ISREG(metadata.mode) or metadata.mnt_id != mount) return error.UnsafePath;
    return fd;
}

fn info(fd: linux.fd_t) Error!linux.Statx {
    var metadata: linux.Statx = undefined;
    const rc = linux.statx(fd, "", linux.AT.EMPTY_PATH | linux.AT.SYMLINK_NOFOLLOW, .{
        .TYPE = true,
        .MODE = true,
        .NLINK = true,
        .UID = true,
        .GID = true,
        .SIZE = true,
        .MNT_ID = true,
    }, &metadata);
    if (linux.errno(rc) != .SUCCESS) return error.StatFailed;
    const mask = metadata.mask;
    if (!mask.TYPE or !mask.MODE or !mask.NLINK or !mask.UID or !mask.GID or !mask.SIZE or !mask.MNT_ID)
        return error.StatFailed;
    return metadata;
}

fn own(fd: linux.fd_t, owner: linux.uid_t, group: linux.gid_t) Error!void {
    if (linux.errno(linux.fchown(fd, owner, group)) != .SUCCESS) return error.OwnershipFailed;
}

fn mode(fd: linux.fd_t, permissions: linux.mode_t) Error!void {
    if (linux.errno(linux.fchmod(fd, permissions)) != .SUCCESS) return error.PermissionFailed;
}

fn sync(fd: linux.fd_t) Error!void {
    while (true) {
        switch (linux.errno(linux.fsync(fd))) {
            .SUCCESS => return,
            .INTR => continue,
            else => return error.SyncFailed,
        }
    }
}

fn temporary(staging: linux.fd_t, name: [*:0]const u8) Error!linux.fd_t {
    const removed = linux.errno(linux.unlinkat(staging, name, 0));
    if (removed != .SUCCESS and removed != .NOENT) return error.RemoveFailed;
    const raw = linux.openat(staging, name, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .EXCL = true,
        .NOFOLLOW = true,
        .CLOEXEC = true,
    }, 0o600);
    if (linux.errno(raw) != .SUCCESS) return error.OpenFailed;
    return @intCast(raw);
}

fn readSome(fd: linux.fd_t, buffer: []u8) Error!usize {
    while (true) {
        const rc = linux.read(fd, buffer.ptr, buffer.len);
        switch (linux.errno(rc)) {
            .SUCCESS => return rc,
            .INTR => continue,
            else => return error.ReadFailed,
        }
    }
}

fn readExact(fd: linux.fd_t, buffer: []u8) Error!void {
    var offset: usize = 0;
    while (offset < buffer.len) {
        const count = try readSome(fd, buffer[offset..]);
        if (count == 0) return error.ReadFailed;
        offset += count;
    }
}

fn expectEof(fd: linux.fd_t) Error!void {
    var extra: [1]u8 = undefined;
    if (try readSome(fd, &extra) != 0) return error.ReadFailed;
}

fn writeAll(fd: linux.fd_t, bytes: []const u8) Error!void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const rc = linux.write(fd, bytes.ptr + offset, bytes.len - offset);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return error.WriteFailed;
                offset += rc;
            },
            .INTR => continue,
            else => return error.WriteFailed,
        }
    }
}

fn stream(source: linux.fd_t, destination: ?linux.fd_t, length: u64, expected_hash: ?[]const u8) Error!void {
    var remaining = length;
    var digest: std.crypto.hash.sha2.Sha256 = if (expected_hash != null)
        std.crypto.hash.sha2.Sha256.init(.{})
    else
        undefined;
    while (remaining != 0) {
        const wanted: usize = @intCast(@min(remaining, copy_buffer.len));
        const count = try readSome(source, copy_buffer[0..wanted]);
        if (count == 0) return error.ReadFailed;
        if (destination) |fd| try writeAll(fd, copy_buffer[0..count]);
        if (expected_hash != null) digest.update(copy_buffer[0..count]);
        remaining -= count;
    }
    try expectEof(source);
    if (expected_hash) |expected| {
        var bytes: [32]u8 = undefined;
        digest.final(&bytes);
        for (bytes, 0..) |byte, index| {
            if (expected[index * 2] != hex[byte >> 4] or expected[index * 2 + 1] != hex[byte & 15])
                return error.HashMismatch;
        }
    }
}

fn protected(name: []const u8) bool {
    const names = [_][]const u8{ "boot.state", "generations", "store", "toolchain", ".seal", "postgres", "system" };
    for (names) |reserved| {
        if (std.mem.eql(u8, name, reserved)) return true;
    }
    return false;
}

fn migrateWritable(priv: linux.fd_t, staging: linux.fd_t, mount: u64) Error!void {
    var depth: usize = 0;
    frames[0] = .{ .fd = priv };
    defer {
        while (depth != 0) : (depth -= 1) _ = linux.close(frames[depth].fd);
    }
    while (true) {
        const frame = &frames[depth];
        const entry = try nextEntry(frame);
        if (entry == null) {
            if (depth == 0) break;
            _ = linux.close(frame.fd);
            depth -= 1;
            continue;
        }
        const name = entry.?;
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (depth == 0 and protected(name)) continue;
        // O_PATH does not open devices, block on FIFOs, or follow a symlink.
        const raw = linux.openat(frame.fd, name.ptr, .{
            .PATH = true,
            .NOFOLLOW = true,
            .CLOEXEC = true,
        }, 0);
        if (linux.errno(raw) != .SUCCESS) return error.OpenFailed;
        const fd: linux.fd_t = @intCast(raw);
        defer _ = linux.close(fd);
        const metadata = try info(fd);
        if (metadata.mnt_id != mount) return error.UnsafePath;
        if (linux.S.ISDIR(metadata.mode)) {
            if (depth + 1 == frames.len) return error.TooDeep;
            const directory = try openDirectory(fd, ".");
            errdefer _ = linux.close(directory);
            try own(directory, uid, gid);
            depth += 1;
            frames[depth] = .{ .fd = directory };
        } else if (linux.S.ISREG(metadata.mode) and metadata.nlink > 1) {
            // An alias to boot.state/a sealed blob must not transfer that
            // protected inode's ownership. Replace just this writable path.
            const source = try openRegular(frame.fd, name.ptr, mount);
            defer _ = linux.close(source);
            const source_metadata = try info(source);
            const destination = try temporary(staging, "state.tmp");
            defer _ = linux.close(destination);
            defer _ = linux.unlinkat(staging, "state.tmp", 0);
            try stream(source, destination, source_metadata.size, null);
            try own(destination, uid, gid);
            try mode(destination, source_metadata.mode & 0o7777);
            try sync(destination);
            if (linux.errno(linux.renameat(staging, "state.tmp", frame.fd, name.ptr)) != .SUCCESS)
                return error.RenameFailed;
            try sync(frame.fd);
        } else {
            const kind = metadata.mode & linux.S.IFMT;
            if (kind == linux.S.IFCHR or kind == linux.S.IFBLK) return error.UnsafePath;
            if (linux.errno(linux.fchownat(fd, "", uid, gid, linux.AT.EMPTY_PATH | linux.AT.SYMLINK_NOFOLLOW)) != .SUCCESS)
                return error.OwnershipFailed;
        }
    }
}

fn nextEntry(frame: *Frame) Error!?[:0]const u8 {
    if (frame.cursor == frame.used) {
        while (true) {
            const rc = linux.getdents64(frame.fd, &frame.buffer, frame.buffer.len);
            switch (linux.errno(rc)) {
                .SUCCESS => {
                    if (rc == 0) return null;
                    frame.used = rc;
                    frame.cursor = 0;
                    break;
                },
                .INTR => continue,
                else => return error.ReadFailed,
            }
        }
    }
    const name_offset = @offsetOf(linux.dirent64, "name");
    if (frame.used - frame.cursor < name_offset + 1) return error.ReadFailed;
    const entry: *align(1) const linux.dirent64 = @ptrCast(&frame.buffer[frame.cursor]);
    const length: usize = entry.reclen;
    if (length < name_offset + 1 or length > frame.used - frame.cursor) return error.ReadFailed;
    const bytes = frame.buffer[frame.cursor + name_offset .. frame.cursor + length];
    frame.cursor += length;
    for (bytes, 0..) |byte, index| {
        if (byte == 0) return bytes[0..index :0];
    }
    return error.ReadFailed;
}

// The external term parser recognizes the real Generation.write/2 envelope,
// not a second sidecar format. Unsupported/compressed/distribution-only terms
// fail closed; unrelated ordinary ETF fields are fully bounded and skipped.
const Parser = struct {
    bytes: []const u8,
    cursor: usize = 0,

    fn take(self: *Parser, length: usize) Error![]const u8 {
        if (length > self.bytes.len - self.cursor) return error.InvalidManifest;
        const start = self.cursor;
        self.cursor += length;
        return self.bytes[start..self.cursor];
    }

    fn byte(self: *Parser) Error!u8 {
        return (try self.take(1))[0];
    }

    fn word(self: *Parser) Error!u16 {
        const bytes = try self.take(2);
        return (@as(u16, bytes[0]) << 8) | bytes[1];
    }

    fn long(self: *Parser) Error!u32 {
        const bytes = try self.take(4);
        return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) |
            (@as(u32, bytes[2]) << 8) | bytes[3];
    }

    fn atom(self: *Parser) Error![]const u8 {
        const tag = try self.byte();
        const length: usize = switch (tag) {
            100, 118 => try self.word(),
            115, 119 => try self.byte(),
            else => return error.InvalidManifest,
        };
        const value = try self.take(length);
        if (tag == 118 or tag == 119) {
            if (length > 1020) return error.InvalidManifest;
            const count = std.unicode.utf8CountCodepoints(value) catch return error.InvalidManifest;
            if (count > 255) return error.InvalidManifest;
        } else if (length > 255) return error.InvalidManifest;
        return value;
    }

    fn unsigned(self: *Parser) Error!u32 {
        const tag = try self.byte();
        switch (tag) {
            97 => return try self.byte(),
            98 => {
                const value = try self.long();
                if (value & 0x80000000 != 0) return error.InvalidManifest;
                return value;
            },
            110, 111 => {
                const length: usize = if (tag == 110) try self.byte() else try self.long();
                if (length > 4 or try self.byte() != 0) return error.InvalidManifest;
                const digits = try self.take(length);
                var result: u32 = 0;
                for (digits, 0..) |digit, index|
                    result |= @as(u32, digit) << @as(u5, @intCast(index * 8));
                return result;
            },
            else => return error.InvalidManifest,
        }
    }

    fn tuple(self: *Parser) Error!u32 {
        return switch (try self.byte()) {
            104 => try self.byte(),
            105 => try self.long(),
            else => error.InvalidManifest,
        };
    }

    fn map(self: *Parser) Error!u32 {
        if (try self.byte() != 116) return error.InvalidManifest;
        return try self.long();
    }

    fn children(self: *Parser, count: usize, depth: usize) Error!void {
        if (count > self.bytes.len - self.cursor) return error.InvalidManifest;
        for (0..count) |_| try self.skip(depth);
    }

    fn skip(self: *Parser, depth: usize) Error!void {
        if (depth >= max_depth) return error.TooDeep;
        const tag = try self.byte();
        switch (tag) {
            70 => _ = try self.take(8), // NEW_FLOAT_EXT
            97 => _ = try self.take(1),
            98 => _ = try self.take(4),
            99 => _ = try self.take(31), // legacy FLOAT_EXT
            100, 115, 118, 119 => {
                self.cursor -= 1;
                _ = try self.atom();
            },
            104 => try self.children(try self.byte(), depth + 1),
            105 => try self.children(try self.long(), depth + 1),
            106 => {},
            107 => _ = try self.take(try self.word()),
            108 => {
                try self.children(try self.long(), depth + 1);
                try self.skip(depth + 1); // also supports an improper list tail
            },
            109 => _ = try self.take(try self.long()),
            77 => {
                const length = try self.long();
                const bits = try self.byte();
                if (length == 0 or bits == 0 or bits > 8) return error.InvalidManifest;
                _ = try self.take(length);
            },
            110, 111 => {
                const length: usize = if (tag == 110) try self.byte() else try self.long();
                if (try self.byte() > 1) return error.InvalidManifest;
                _ = try self.take(length);
            },
            116 => {
                const count: usize = try self.long();
                if (count > (self.bytes.len - self.cursor) / 2) return error.InvalidManifest;
                try self.children(count * 2, depth + 1);
            },
            101, 102, 103, 88, 89, 120 => {
                _ = try self.atom();
                _ = try self.take(switch (tag) {
                    101, 102 => 5,
                    103 => 9,
                    88, 120 => 12,
                    89 => 8,
                    else => return error.InvalidManifest,
                });
            },
            114, 90 => {
                const count: usize = try self.word();
                if (count == 0 or count > 5) return error.InvalidManifest;
                _ = try self.atom();
                _ = try self.take(if (tag == 114) 1 else 4);
                _ = try self.take(count * 4);
            },
            113 => {
                _ = try self.atom();
                _ = try self.atom();
                if (try self.unsigned() > 255) return error.InvalidManifest;
            },
            117 => {
                const count = try self.long();
                try self.skip(depth + 1); // pid
                _ = try self.atom();
                _ = try self.unsigned();
                _ = try self.unsigned();
                try self.children(count, depth + 1);
            },
            112 => {
                const start = self.cursor;
                const length: usize = try self.long();
                if (length < 4 or length > self.bytes.len - start) return error.InvalidManifest;
                const end = start + length;
                _ = try self.take(1 + 16 + 4); // arity, uniq, index
                const count = try self.long();
                _ = try self.atom();
                _ = try self.unsigned();
                _ = try self.unsigned();
                try self.skip(depth + 1); // pid
                try self.children(count, depth + 1);
                if (self.cursor != end) return error.InvalidManifest;
            },
            else => return error.InvalidManifest,
        }
    }
};

fn parseManifest(bytes: []const u8, generation: u32, offsets: []u32) Error!usize {
    if (bytes.len > max_manifest) return error.TooLarge;
    var parser: Parser = .{ .bytes = bytes };
    if (try parser.byte() != 131 or try parser.tuple() != 3 or
        !std.mem.eql(u8, try parser.atom(), "elixos_generation") or try parser.unsigned() != 1)
        return error.InvalidManifest;
    const fields = try parser.map();
    if (fields > (bytes.len - parser.cursor) / 2) return error.InvalidManifest;
    var found_number = false;
    var found_modules = false;
    var count: usize = 0;
    for (0..fields) |_| {
        const key = try parser.atom();
        if (std.mem.eql(u8, key, "number")) {
            if (found_number) return error.InvalidManifest;
            found_number = true;
            if (try parser.unsigned() != generation or generation == 0) return error.InvalidGeneration;
        } else if (std.mem.eql(u8, key, "modules")) {
            if (found_modules) return error.InvalidManifest;
            found_modules = true;
            count = try parser.map();
            if (count > max_modules or count > offsets.len) return error.TooManyModules;
            for (offsets[0..count]) |*offset| {
                _ = try parser.atom(); // module name; never a pathname
                if (try parser.byte() != 109 or try parser.long() != 64) return error.InvalidManifest;
                offset.* = @intCast(parser.cursor);
                const hash = try parser.take(64);
                for (hash) |digit| {
                    if (!(digit >= '0' and digit <= '9') and !(digit >= 'a' and digit <= 'f'))
                        return error.InvalidManifest;
                }
            }
        } else {
            try parser.skip(2);
        }
    }
    if (!found_number or !found_modules or parser.cursor != bytes.len) return error.InvalidManifest;
    return count;
}

// Real uncompressed :erlang.term_to_binary/1 bytes (OTP 29), with DateTime and
// nested boot arguments. Keep this independent of the parser's own encoder.
const reference =
    "\x83\x68\x03\x77\x11elixos_generation\x61\x01\x74\x00\x00\x00\x05" ++
    "\x77\x06parent\x61\x06\x77\x04boot\x6c\x00\x00\x00\x01\x68\x03" ++
    "\x77\x12Elixir.SealFixture\x77\x05start\x6c\x00\x00\x00\x01\x6c\x00\x00\x00\x06" ++
    "\x61\x01\x62\xff\xff\xff\xfe\x46\x3f\xf8\x00\x00\x00\x00\x00\x00" ++
    "\x6d\x00\x00\x00\x02\x01\x02\x68\x02\x77\x02ok\x77\x04true" ++
    "\x74\x00\x00\x00\x01\x77\x08argument\x6d\x00\x00\x00\x05value\x6a\x6a\x6a" ++
    "\x77\x07modules\x74\x00\x00\x00\x01\x77\x12Elixir.SealFixture\x6d\x00\x00\x00\x40" ++
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ++
    "\x77\x06number\x61\x07\x77\x0acreated_at\x74\x00\x00\x00\x0d" ++
    "\x77\x0bmicrosecond\x68\x02\x61\x00\x61\x00\x77\x06second\x61\x00" ++
    "\x77\x08calendar\x77\x13Elixir.Calendar.ISO\x77\x05month\x61\x0a" ++
    "\x77\x0a__struct__\x77\x0fElixir.DateTime\x77\x03day\x61\x09" ++
    "\x77\x04year\x62\x00\x00\x07\xea\x77\x06minute\x61\x00\x77\x04hour\x61\x14" ++
    "\x77\x09time_zone\x6d\x00\x00\x00\x07Etc/UTC\x77\x09zone_abbr\x6d\x00\x00\x00\x03UTC" ++
    "\x77\x0autc_offset\x61\x00\x77\x0astd_offset\x61\x00";
const maximum_generation_reference =
    "\x83\x68\x03\x77\x11elixos_generation\x61\x01\x74\x00\x00\x00\x02" ++
    "\x77\x07modules\x74\x00\x00\x00\x00\x77\x06number\x6e\x04\x00\xff\xff\xff\xff";
const multiple_modules_reference =
    "\x83\x68\x03\x77\x11elixos_generation\x61\x01\x74\x00\x00\x00\x02" ++
    "\x77\x07modules\x74\x00\x00\x00\x02\x77\x0aElixir.Foo\x6d\x00\x00\x00\x40" ++
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ++
    "\x77\x0aElixir.Bar\x6d\x00\x00\x00\x40" ++
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ++
    "\x77\x06number\x61\x07";

const testing = std.testing;

test "seal: real ETF DateTime and boot args yield every module reference" {
    try milestone.require(17);
    var offsets: [4]u32 = undefined;
    const count = try parseManifest(reference, 7, &offsets);
    try testing.expectEqual(@as(usize, 486), reference.len);
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqualSlices(u8, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", reference[offsets[0]..][0..64]);
    try testing.expectEqual(@as(usize, 0), try parseManifest(maximum_generation_reference, 4294967295, &offsets));
    const name = generationName(4294967295);
    try testing.expectEqualSlices(u8, "4294967295.gen", name[0..14]);
}

test "seal: references after the first module are validated too" {
    try milestone.require(17);
    var offsets: [2]u32 = undefined;
    try testing.expectEqual(@as(usize, 2), try parseManifest(multiple_modules_reference, 7, &offsets));
    try testing.expectEqualSlices(u8, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", multiple_modules_reference[offsets[1]..][0..64]);
    var changed: [multiple_modules_reference.len]u8 = multiple_modules_reference.*;
    changed[offsets[1]] = 'B';
    try testing.expectError(error.InvalidManifest, parseManifest(&changed, 7, &offsets));
}

test "seal: every truncation fails closed and ETF trailing bytes are refused" {
    try milestone.require(17);
    var offsets: [4]u32 = undefined;
    for (0..reference.len) |length| {
        try testing.expectError(error.InvalidManifest, parseManifest(reference[0..length], 7, &offsets));
    }
    try testing.expectError(error.InvalidManifest, parseManifest(reference ++ "\x6a", 7, &offsets));
    try testing.expectError(error.InvalidManifest, parseManifest("\x83\x50\x00\x00\x01\x00", 7, &offsets));
    try testing.expectError(error.InvalidGeneration, parseManifest(reference, 8, &offsets));
}

test "seal: only exact lowercase hash binaries are accepted" {
    try milestone.require(17);
    var offsets: [4]u32 = undefined;
    _ = try parseManifest(reference, 7, &offsets);
    var changed: [reference.len]u8 = reference.*;
    const start: usize = offsets[0];
    for ([_]u8{ 'A', 'g', '/', 0, 255 }) |invalid| {
        changed[start] = invalid;
        try testing.expectError(error.InvalidManifest, parseManifest(&changed, 7, &offsets));
    }
    changed[start] = 'a';
    changed[start - 1] = 63;
    try testing.expectError(error.InvalidManifest, parseManifest(&changed, 7, &offsets));
    changed[start - 1] = 64;
    changed[start - 5] = 107; // a string/list is not a hash binary
    try testing.expectError(error.InvalidManifest, parseManifest(&changed, 7, &offsets));
}

test "seal: missing and duplicate trusted fields and module overflow are refused" {
    try milestone.require(17);
    var offsets: [4]u32 = undefined;
    const envelope = "\x83\x68\x03\x77\x11elixos_generation\x61\x01\x74";
    const number = "\x77\x06number\x61\x07";
    const modules = "\x77\x07modules\x74\x00\x00\x00\x00";
    try testing.expectError(error.InvalidManifest, parseManifest(envelope ++ "\x00\x00\x00\x01" ++ number, 7, &offsets));
    try testing.expectError(error.InvalidManifest, parseManifest(envelope ++ "\x00\x00\x00\x03" ++ number ++ number ++ modules, 7, &offsets));
    try testing.expectError(error.InvalidManifest, parseManifest(envelope ++ "\x00\x00\x00\x03" ++ number ++ modules ++ modules, 7, &offsets));
    try testing.expectError(error.TooManyModules, parseManifest(envelope ++ "\x00\x00\x00\x02" ++ number ++ "\x77\x07modules\x74\x00\x00\x10\x01", 7, &offsets));
    var no_space: [0]u32 = .{};
    try testing.expectError(error.TooManyModules, parseManifest(reference, 7, &no_space));
}

test "seal: nested ETF fields have a hard depth bound and sizes cannot overflow" {
    try milestone.require(17);
    var nested: [max_depth * 2 + 1]u8 = undefined;
    for (0..max_depth) |index| {
        nested[index * 2] = 104;
        nested[index * 2 + 1] = 1;
    }
    nested[nested.len - 1] = 106;
    var deep: Parser = .{ .bytes = &nested };
    try testing.expectError(error.TooDeep, deep.skip(0));
    var huge_map: Parser = .{ .bytes = "\x74\xff\xff\xff\xff" };
    try testing.expectError(error.InvalidManifest, huge_map.skip(0));
    var huge_list: Parser = .{ .bytes = "\x6c\xff\xff\xff\xff" };
    try testing.expectError(error.InvalidManifest, huge_list.skip(0));
    var bad_utf8: Parser = .{ .bytes = "\x77\x01\xff" };
    try testing.expectError(error.InvalidManifest, bad_utf8.skip(0));
}
