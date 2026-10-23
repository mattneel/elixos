//! The deck framebuffer (docs/PROTOCOL.md §12, M33): the region's layout,
//! shared by the shim and `elixos-deck-fb` (deck_fb.zig), and the shim's
//! `elixos.deck=<spec>` parameter (§5): which device holds the region, found
//! and granted to the BEAM before ERTS starts.
//!
//! The BEAM is unprivileged (M17) and cannot find a PCI BAR, enable the
//! device or open a root-only sysfs/UIO node. PID 1 resolves the spec to a
//! path once, makes it read-write for the `video` group the BEAM belongs to
//! (as it does for /dev/fb*), and passes the path as `ELIXOS_DECK` (§3).
const std = @import("std");
const linux = std.os.linux;
const milestone = @import("milestone.zig");

// ---------------------------------------------------------------------------
// Layout (§12). All integers little-endian u32.

pub const magic: u32 = 0x44584C45; // "ELXD"
pub const version: u32 = 1;
pub const width: u32 = 568;
pub const height: u32 = 1232;
pub const stride: u32 = width * 2;
/// 1 = RGB565, little-endian per pixel.
pub const format_rgb565: u32 = 1;
pub const header_size: usize = 4096;
/// The smallest region that holds the header and every pixel: 1,403,648.
pub const region_size: usize = header_size + @as(usize, stride) * height;

pub const Field = enum(usize) {
    magic = 0,
    version = 4,
    width = 8,
    height = 12,
    stride = 16,
    format = 20,
    seq = 24,
    damage_x = 28,
    damage_y = 32,
    damage_w = 36,
    damage_h = 40,
    shown = 44,
};

fn word(region: []align(4096) u8, field: Field) *u32 {
    return @ptrCast(@alignCast(&region[@backingInt(field)]));
}

pub fn get(region: []align(4096) u8, field: Field) u32 {
    return std.mem.littleToNative(u32, @atomicLoad(u32, word(region, field), .acquire));
}

fn set(region: []align(4096) u8, field: Field, value: u32) void {
    @atomicStore(u32, word(region, field), std.mem.nativeToLittle(u32, value), .monotonic);
}

/// True when the header describes this protocol's panel exactly.
pub fn valid(region: []align(4096) u8) bool {
    return get(region, .magic) == magic and get(region, .version) == version and
        get(region, .width) == width and get(region, .height) == height and
        get(region, .stride) == stride and get(region, .format) == format_rgb565;
}

/// Initialises a header that is not valid: zero the header page, write the
/// fields, then (after a write fence) the magic. A valid header is kept, its
/// `seq` included, so a restarted helper continues where the last one was.
/// Returns true when it initialised.
pub fn prepare(region: []align(4096) u8) bool {
    if (valid(region)) return false;
    set(region, .magic, 0);
    @memset(region[4..header_size], 0);
    set(region, .version, version);
    set(region, .width, width);
    set(region, .height, height);
    set(region, .stride, stride);
    set(region, .format, format_rgb565);
    @atomicStore(u32, word(region, .magic), std.mem.nativeToLittle(u32, magic), .release);
    return true;
}

pub const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

/// A non-empty rectangle inside the panel.
pub fn inside(rect: Rect) bool {
    return rect.w > 0 and rect.h > 0 and rect.x < width and rect.y < height and
        rect.w <= width - rect.x and rect.h <= height - rect.y;
}

/// Commits: damage first, then (after a write fence) seq + 1. Returns the
/// new seq. The pixels were written before this is called.
pub fn commit(region: []align(4096) u8, damage: Rect) u32 {
    set(region, .damage_x, damage.x);
    set(region, .damage_y, damage.y);
    set(region, .damage_w, damage.w);
    set(region, .damage_h, damage.h);
    const next = get(region, .seq) +% 1;
    @atomicStore(u32, word(region, .seq), std.mem.nativeToLittle(u32, next), .release);
    return next;
}

// ---------------------------------------------------------------------------
// elixos.deck=<spec> (§5)

pub const Spec = struct {
    /// The parameter's value as written, for the console line.
    text: []const u8,
    target: Target,
};

pub const Target = union(enum) {
    /// `pci:<vendor>:<device>`, ids as sysfs prints them (`0x1af4`): the
    /// device's BAR 2 (`resource2`), as QEMU's ivshmem-plain exposes its memory.
    pci: struct { vendor: []const u8, device: []const u8 },
    /// `uio:<name>`: the UIO device whose sysfs `name` is <name> (a device
    /// tree node's name, e.g. `deck-fb`); its map 0 at offset 0.
    uio: []const u8,
    /// An absolute device path under /dev.
    path: []const u8,
};

/// Null for anything malformed.
pub fn parseSpec(value: ?[]const u8) ?Spec {
    const text = value orelse return null;
    if (std.mem.cutPrefix(u8, text, "pci:")) |ids| {
        const colon = std.mem.indexOfScalar(u8, ids, ':') orelse return null;
        const vendor = ids[0..colon];
        const device = ids[colon + 1 ..];
        if (!validId(vendor) or !validId(device)) return null;
        return .{ .text = text, .target = .{ .pci = .{ .vendor = vendor, .device = device } } };
    }
    if (std.mem.cutPrefix(u8, text, "uio:")) |name| {
        if (name.len == 0 or name.len > 64) return null;
        for (name) |c| {
            if (!std.ascii.isAlphanumeric(c) and std.mem.indexOfScalar(u8, "_.,+-", c) == null) return null;
        }
        return .{ .text = text, .target = .{ .uio = name } };
    }
    const device = std.mem.cutPrefix(u8, text, "/dev/") orelse return null;
    if (device.len == 0 or text.len > max_path) return null;
    var parts = std.mem.splitScalar(u8, device, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return null;
    }
    return .{ .text = text, .target = .{ .path = text } };
}

/// `0x` and four lowercase hex digits, the form of sysfs `vendor`/`device`.
fn validId(id: []const u8) bool {
    if (id.len != 6 or !std.mem.startsWith(u8, id, "0x")) return false;
    for (id[2..]) |c| {
        if (!std.ascii.isDigit(c) and (c < 'a' or c > 'f')) return false;
    }
    return true;
}

pub const max_path = 96;

pub const Error = error{ NotFound, NotADevice, Enable, Grant, System };

/// Finds the spec's device, enables a PCI device's memory decoding if it is
/// not yet enabled, and grants it to the `video` group read-write (0660).
/// Returns the path, NUL-terminated in `buffer`.
pub fn prepareDevice(spec: Spec, buffer: *[max_path + 1]u8) Error![:0]const u8 {
    const path = try resolve(spec.target, buffer);
    if (spec.target == .pci) try enable(path);
    if (linux.errno(linux.fchownat(linux.AT.FDCWD, path, 0, video_gid, 0)) != .SUCCESS or
        linux.errno(linux.fchmodat2(linux.AT.FDCWD, path, 0o660, 0)) != .SUCCESS)
        return error.Grant;
    return path;
}

const video_gid = 27;

fn resolve(target: Target, buffer: *[max_path + 1]u8) Error![:0]const u8 {
    switch (target) {
        .path => |path| {
            const text = std.fmt.bufPrintSentinel(buffer, "{s}", .{path}, 0) catch return error.System;
            var st: linux.Statx = undefined;
            switch (linux.errno(linux.statx(linux.AT.FDCWD, text, 0, .{ .TYPE = true }, &st))) {
                .SUCCESS => {},
                .NOENT => return error.NotFound,
                else => return error.System,
            }
            if (st.mode & linux.S.IFMT != linux.S.IFCHR) return error.NotADevice;
            return text;
        },
        .pci => |ids| {
            var it = try Entries.open("/sys/bus/pci/devices");
            defer it.close();
            while (it.next()) |name| {
                if (!attributeIs("/sys/bus/pci/devices", name, "vendor", ids.vendor)) continue;
                if (!attributeIs("/sys/bus/pci/devices", name, "device", ids.device)) continue;
                return std.fmt.bufPrintSentinel(buffer, "/sys/bus/pci/devices/{s}/resource2", .{name}, 0) catch error.System;
            }
            return error.NotFound;
        },
        .uio => |wanted| {
            var it = try Entries.open("/sys/class/uio");
            defer it.close();
            while (it.next()) |name| {
                if (!attributeIs("/sys/class/uio", name, "name", wanted)) continue;
                return std.fmt.bufPrintSentinel(buffer, "/dev/{s}", .{name}, 0) catch error.System;
            }
            return error.NotFound;
        },
    }
}

/// `enable` beside the resource file: "1" once decoding is on. Written only
/// when it reads "0", so a re-exec'd shim does not count another enable.
fn enable(resource: [:0]const u8) Error!void {
    var buffer: [max_path + 1]u8 = undefined;
    const dir = resource[0 .. std.mem.lastIndexOfScalar(u8, resource, '/') orelse return error.System];
    const path = std.fmt.bufPrintSentinel(&buffer, "{s}/enable", .{dir}, 0) catch return error.System;
    var current: [8]u8 = undefined;
    const state = readSmall(path, &current) catch return error.Enable;
    if (std.mem.eql(u8, state, "1")) return;
    const fd = linux.openat(linux.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
    if (linux.errno(fd) != .SUCCESS) return error.Enable;
    defer _ = linux.close(@intCast(fd));
    if (linux.errno(linux.write(@intCast(fd), "1", 1)) != .SUCCESS) return error.Enable;
}

/// True when `<dir>/<name>/<attribute>` holds `expected` (one trailing
/// newline ignored).
fn attributeIs(dir: []const u8, name: []const u8, attribute: []const u8, expected: []const u8) bool {
    var path_buffer: [max_path + 1]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&path_buffer, "{s}/{s}/{s}", .{ dir, name, attribute }, 0) catch return false;
    var content: [80]u8 = undefined;
    const text = readSmall(path, &content) catch return false;
    return std.mem.eql(u8, text, expected);
}

fn readSmall(path: [*:0]const u8, buffer: []u8) error{System}![]const u8 {
    const raw = linux.openat(linux.AT.FDCWD, path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(raw) != .SUCCESS) return error.System;
    const fd: linux.fd_t = @intCast(raw);
    defer _ = linux.close(fd);
    const n = linux.read(fd, buffer.ptr, buffer.len);
    if (linux.errno(n) != .SUCCESS) return error.System;
    return trimNewline(buffer[0..n]);
}

pub fn trimNewline(text: []const u8) []const u8 {
    return std.mem.trimEnd(u8, text, "\n");
}

/// Directory entries other than `.` and `..`, without allocation.
const Entries = struct {
    fd: linux.fd_t,
    buffer: [2048]u8 align(@alignOf(linux.dirent64)) = undefined,
    len: usize = 0,
    offset: usize = 0,

    fn open(path: [*:0]const u8) Error!Entries {
        const raw = linux.open(path, .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
        return switch (linux.errno(raw)) {
            .SUCCESS => .{ .fd = @intCast(raw) },
            .NOENT => error.NotFound,
            else => error.System,
        };
    }

    fn close(self: *Entries) void {
        _ = linux.close(self.fd);
    }

    fn next(self: *Entries) ?[]const u8 {
        while (true) {
            if (self.offset + @sizeOf(linux.dirent64) > self.len) {
                const rc = linux.getdents64(self.fd, &self.buffer, self.buffer.len);
                if (linux.errno(rc) != .SUCCESS or rc == 0) return null;
                self.len = rc;
                self.offset = 0;
            }
            const entry: *align(1) const linux.dirent64 = @ptrCast(&self.buffer[self.offset]);
            if (entry.reclen < @sizeOf(linux.dirent64) or entry.reclen > self.len - self.offset) return null;
            const raw: [*:0]const u8 = @ptrCast(&entry.name);
            const name = std.mem.sliceTo(raw, 0);
            self.offset += entry.reclen;
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            return name;
        }
    }
};

test "M33 deck: the region layout" {
    try milestone.require(33);
    // 4096 + 1136 * 1232. (PROTOCOL.md §12 first said 1,403,712: a slip.)
    try std.testing.expectEqual(@as(usize, 1_403_648), region_size);
    const S = struct {
        var region: [region_size]u8 align(4096) = undefined;
    };
    @memset(&S.region, 0xAA);
    try std.testing.expect(!valid(&S.region));
    try std.testing.expect(prepare(&S.region));
    const expected = [_]u32{ magic, version, 568, 1232, 1136, 1, 0, 0, 0, 0, 0, 0 };
    for (expected, 0..) |value, i| {
        try std.testing.expectEqual(value, std.mem.readInt(u32, S.region[i * 4 ..][0..4], .little));
    }
    for (S.region[48..header_size]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    // Pixels are not the header's business.
    try std.testing.expectEqual(@as(u8, 0xAA), S.region[header_size]);

    try std.testing.expectEqual(@as(u32, 1), commit(&S.region, .{ .x = 1, .y = 2, .w = 3, .h = 4 }));
    try std.testing.expectEqual(@as(u32, 2), commit(&S.region, .{ .x = 0, .y = 0, .w = 568, .h = 1232 }));
    try std.testing.expectEqual(@as(u32, 568), get(&S.region, .damage_w));
    // A valid header survives a restart, seq included.
    try std.testing.expect(!prepare(&S.region));
    try std.testing.expectEqual(@as(u32, 2), get(&S.region, .seq));
    // Any wrong field means re-initialisation.
    std.mem.writeInt(u32, S.region[16..20], 1137, .little);
    try std.testing.expect(prepare(&S.region));
    try std.testing.expectEqual(@as(u32, 0), get(&S.region, .seq));
    // seq wraps at 2^32.
    std.mem.writeInt(u32, S.region[24..28], 0xFFFF_FFFF, .little);
    try std.testing.expectEqual(@as(u32, 0), commit(&S.region, .{ .x = 0, .y = 0, .w = 1, .h = 1 }));
}

test "M33 deck: damage rectangles stay inside the panel" {
    try milestone.require(33);
    try std.testing.expect(inside(.{ .x = 0, .y = 0, .w = 568, .h = 1232 }));
    try std.testing.expect(inside(.{ .x = 567, .y = 1231, .w = 1, .h = 1 }));
    try std.testing.expect(!inside(.{ .x = 0, .y = 0, .w = 0, .h = 1 }));
    try std.testing.expect(!inside(.{ .x = 1, .y = 0, .w = 568, .h = 1 }));
    try std.testing.expect(!inside(.{ .x = 0, .y = 1232, .w = 1, .h = 1 }));
    try std.testing.expect(!inside(.{ .x = 0xFFFF_FFFF, .y = 0, .w = 2, .h = 1 }));
}

test "M33 deck: elixos.deck specs" {
    try milestone.require(33);
    const pci = parseSpec("pci:0x1af4:0x1110").?;
    try std.testing.expectEqualStrings("0x1af4", pci.target.pci.vendor);
    try std.testing.expectEqualStrings("0x1110", pci.target.pci.device);
    try std.testing.expectEqualStrings("pci:0x1af4:0x1110", pci.text);
    try std.testing.expectEqualStrings("deck-fb", parseSpec("uio:deck-fb").?.target.uio);
    try std.testing.expectEqualStrings("/dev/uio0", parseSpec("/dev/uio0").?.target.path);
    for ([_][]const u8{
        "",                   "pci:",                "pci:1af4:1110", "pci:0x1AF4:0x1110", "pci:0x1af4",
        "pci:0x1af4:0x11100", "pci:0x1af4:0x1110:0", "uio:",          "uio:a b",           "uio:a/b",
        "/dev/",              "/dev/../etc/shadow",  "/dev//uio0",    "/etc/passwd",       "dev/uio0",
        "uio0",
    }) |bad| {
        if (parseSpec(bad) != null) {
            std.debug.print("accepted {s}\n", .{bad});
            return error.TestUnexpectedSpec;
        }
    }
    try std.testing.expect(parseSpec(null) == null);
}
