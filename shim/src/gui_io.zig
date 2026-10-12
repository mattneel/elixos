//! Unprivileged fbdev/evdev Port. All paths are fixed; the root broker owns fbcon.
const std = @import("std");
const linux = std.os.linux;
const milestone = @import("milestone.zig");
const Failure = error{ System, Unsupported, Protocol, Closed };
const Field = extern struct { offset: u32, length: u32, msb_right: u32 };
// Linux UAPI linux/fb.h: unsigned long is 64-bit on both supported targets.
const Fixed = extern struct {
    id: [16]u8,
    smem_start: usize,
    smem_len: u32,
    kind: u32,
    type_aux: u32,
    visual: u32,
    xpanstep: u16,
    ypanstep: u16,
    ywrapstep: u16,
    line_length: u32,
    mmio_start: usize,
    mmio_len: u32,
    accel: u32,
    capabilities: u16,
    reserved: [2]u16,
};
const Variable = extern struct {
    xres: u32,
    yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,
    bits_per_pixel: u32,
    grayscale: u32,
    red: Field,
    green: Field,
    blue: Field,
    transp: Field,
    nonstd: u32,
    activate: u32,
    height: u32,
    width: u32,
    accel_flags: u32,
    pixclock: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
    hsync_len: u32,
    vsync_len: u32,
    sync: u32,
    vmode: u32,
    rotate: u32,
    colorspace: u32,
    reserved: [4]u32,
};
const Event = extern struct { sec: isize, usec: isize, kind: u16, code: u16, value: i32 };
const Abs = extern struct { value: i32, minimum: i32, maximum: i32, fuzz: i32, flat: i32, resolution: i32 };
const Unix = extern struct { family: u16 = 1, path: [108]u8 = @splat(0) };
comptime {
    if (@sizeOf(Fixed) != 80 or @offsetOf(Fixed, "line_length") != 48 or
        @sizeOf(Variable) != 160 or @sizeOf(Event) != 24 or @sizeOf(Abs) != 24)
        @compileError("unsupported Linux framebuffer/input ABI");
}

fn checked(raw: usize) Failure!usize {
    return switch (linux.errno(raw)) {
        .SUCCESS => raw,
        else => error.System,
    };
}
fn open(path: [*:0]const u8, writable: bool) Failure!linux.fd_t {
    return @intCast(try checked(linux.openat(linux.AT.FDCWD, path, .{
        .ACCMODE = if (writable) .RDWR else .RDONLY,
        .NOFOLLOW = true,
        .CLOEXEC = true,
        .NONBLOCK = true,
    }, 0)));
}
fn lease() Failure!linux.fd_t {
    const fd: linux.fd_t = @intCast(try checked(linux.socket(1, 1 | 0x80000, 0)));
    errdefer _ = linux.close(fd);
    var address: Unix = .{};
    const path = "/run/elixos-console.sock";
    @memcpy(address.path[0..path.len], path);
    _ = try checked(linux.connect(fd, &address, @sizeOf(Unix)));
    var ack: [1]u8 = undefined;
    if (try checked(linux.read(fd, &ack, 1)) != 1 or ack[0] != 'R') return error.Protocol;
    return fd;
}
fn fieldMask(field: Field, bits: u32) Failure!u32 {
    if (field.length == 0) return 0;
    if (field.length > 8 or field.offset >= bits or field.length > bits - field.offset or field.msb_right != 0)
        return error.Unsupported;
    return ((@as(u32, 1) << @intCast(field.length)) - 1) << @intCast(field.offset);
}
fn validate(f: Fixed, v: Variable) Failure!usize {
    if (f.kind != 0 or f.visual != 2 or v.nonstd != 0 or v.grayscale != 0 or v.rotate != 0 or
        (v.vmode & 256) != 0 or (v.bits_per_pixel != 16 and v.bits_per_pixel != 24 and v.bits_per_pixel != 32) or
        v.xres == 0 or v.yres == 0 or v.xres > 8192 or v.yres > 8192 or
        @as(u64, v.xoffset) + v.xres > v.xres_virtual or @as(u64, v.yoffset) + v.yres > v.yres_virtual)
        return error.Unsupported;
    var occupied: u32 = 0;
    for ([_]Field{ v.red, v.green, v.blue, v.transp }, 0..) |field, index| {
        const mask = try fieldMask(field, v.bits_per_pixel);
        if ((index < 3 and mask == 0) or occupied & mask != 0) return error.Unsupported;
        occupied |= mask;
    }
    const row_end = (@as(u64, v.xoffset) + v.xres) * (v.bits_per_pixel / 8);
    const end = (@as(u64, v.yoffset) + v.yres - 1) * f.line_length + row_end;
    if (row_end > f.line_length or end > f.smem_len) return error.Unsupported;
    return @as(usize, v.xres) * v.yres * 4;
}
fn channel(value: u8, field: Field) u32 {
    if (field.length == 0) return 0;
    return (@as(u32, value) >> @intCast(8 - field.length)) << @intCast(field.offset);
}
fn pixel(rgba: *const [4]u8, v: Variable) u32 {
    return channel(rgba[0], v.red) | channel(rgba[1], v.green) |
        channel(rgba[2], v.blue) | channel(rgba[3], v.transp);
}
fn present(memory: [*]volatile u8, frame: []const u8, f: Fixed, v: Variable) void {
    const bytes: usize = v.bits_per_pixel / 8;
    for (0..v.yres) |y| {
        const row = (y + v.yoffset) * f.line_length + @as(usize, v.xoffset) * bytes;
        for (0..v.xres) |x| {
            const source = (y * v.xres + x) * 4;
            const value = pixel(frame[source..][0..4], v);
            for (0..bytes) |b| memory[row + x * bytes + b] = @truncate(value >> @intCast(b * 8));
        }
    }
}
fn packetLength(header: [4]u8) u32 {
    return (@as(u32, header[0]) << 24) | (@as(u32, header[1]) << 16) | (@as(u32, header[2]) << 8) | header[3];
}
fn send(payload: []const u8, owner: linux.fd_t) Failure!void {
    var buffer: [132]u8 = undefined;
    if (payload.len > buffer.len - 4) return error.Protocol;
    const n: u32 = @intCast(payload.len);
    buffer[0] = @truncate(n >> 24);
    buffer[1] = @truncate(n >> 16);
    buffer[2] = @truncate(n >> 8);
    buffer[3] = @truncate(n);
    @memcpy(buffer[4..][0..payload.len], payload);
    var offset: usize = 0;
    while (offset < payload.len + 4) {
        const raw = linux.write(1, buffer[offset..].ptr, payload.len + 4 - offset);
        switch (linux.errno(raw)) {
            .SUCCESS => {
                if (raw == 0) return error.Closed;
                offset += raw;
            },
            .INTR => continue,
            .AGAIN => {
                var polls = [_]linux.pollfd{ .{ .fd = 1, .events = linux.POLL.OUT }, .{ .fd = 0, .events = 0 }, .{ .fd = owner, .events = linux.POLL.IN } };
                _ = try checked(linux.poll(&polls, polls.len, 1000));
                if (polls[1].revents != 0 or polls[2].revents != 0 or polls[0].revents & (linux.POLL.ERR | linux.POLL.HUP) != 0)
                    return error.Closed;
            },
            else => return error.System,
        }
    }
}
fn release(owner: linux.fd_t) Failure!void {
    const closing = "C";
    if (try checked(linux.write(owner, closing.ptr, closing.len)) != 1) return error.Protocol;
    var polls = [_]linux.pollfd{.{ .fd = owner, .events = linux.POLL.IN }};
    if (try checked(linux.poll(&polls, polls.len, 5000)) == 0) return error.System;
    var acknowledged: [1]u8 = undefined;
    if (try checked(linux.read(owner, &acknowledged, 1)) != 1 or acknowledged[0] != 'C')
        return error.Protocol;
}
const Device = struct {
    fd: linux.fd_t,
    x: ?Abs = null,
    y: ?Abs = null,
    pointer_dirty: bool = false,
};
fn absolute(value: i32, range: Abs, extent: u32) i32 {
    if (range.maximum <= range.minimum or extent == 0) return 0;
    const position = std.math.clamp(@as(i64, value), range.minimum, range.maximum) - range.minimum;
    return @intCast(@divTrunc(position * (extent - 1), @as(i64, range.maximum) - range.minimum));
}
fn input(device: *Device, event: Event, x: *i32, y: *i32, v: Variable, owner: linux.fd_t) Failure!void {
    var text: [96]u8 = undefined;
    // A lost evdev packet invalidates pressed-key state: close the session
    // instead of inventing releases or leaving a stuck key/grab behind.
    if (event.kind == 0 and event.code == 3) return error.Protocol;
    if (event.kind == 1) {
        if (event.value < 0 or event.value > 2) return error.Protocol;
        // Motion and a click can share one SYN_REPORT. Publish the position
        // before the button, not after it, so the click hits this location.
        if (buttonCode(event.code) and device.pointer_dirty) {
            try send(std.fmt.bufPrint(&text, "POINTER {d} {d}", .{ x.*, y.* }) catch return error.Protocol, owner);
            device.pointer_dirty = false;
        }
        const label: []const u8 = if (buttonCode(event.code)) "BUTTON" else "KEY";
        try send(std.fmt.bufPrint(&text, "{s} {d} {d}", .{ label, event.code, event.value }) catch return error.Protocol, owner);
    } else if (event.kind == 2 and (event.code == 0 or event.code == 1)) {
        if (event.code == 0) x.* = @intCast(std.math.clamp(@as(i64, x.*) + event.value, 0, v.xres - 1)) else y.* = @intCast(std.math.clamp(@as(i64, y.*) + event.value, 0, v.yres - 1));
        device.pointer_dirty = true;
    } else if (event.kind == 3 and (event.code == 0 or event.code == 1)) {
        if (event.code == 0) {
            if (device.x) |range| x.* = absolute(event.value, range, v.xres);
        } else {
            if (device.y) |range| y.* = absolute(event.value, range, v.yres);
        }
        device.pointer_dirty = true;
    } else if (event.kind == 0 and event.code == 0 and device.pointer_dirty) {
        try send(std.fmt.bufPrint(&text, "POINTER {d} {d}", .{ x.*, y.* }) catch return error.Protocol, owner);
        device.pointer_dirty = false;
    }
}
fn buttonCode(code: u16) bool {
    return (code >= 0x100 and code < 0x160) or (code >= 0x2c0 and code <= 0x2ff);
}
fn run() Failure!void {
    const owner = try lease();
    defer _ = linux.close(owner);
    const fb = try open("/dev/fb0", true);
    defer _ = linux.close(fb);
    var f: Fixed = undefined;
    var v: Variable = undefined;
    _ = try checked(linux.ioctl(fb, 0x4602, @intFromPtr(&f)));
    _ = try checked(linux.ioctl(fb, 0x4600, @intFromPtr(&v)));
    const size = try validate(f, v);
    const fb_address = try checked(linux.mmap(null, f.smem_len, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fb, 0));
    const memory: [*]u8 = @ptrFromInt(fb_address);
    defer _ = linux.munmap(memory, f.smem_len);
    const frame_address = try checked(linux.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0));
    const frame = @as([*]u8, @ptrFromInt(frame_address))[0..size];
    defer _ = linux.munmap(frame.ptr, size);
    var devices: [256]Device = undefined;
    var count: usize = 0;
    defer {
        for (devices[0..count]) |device| {
            _ = linux.close(device.fd);
        }
    }
    var path_buffer: [64]u8 = undefined;
    for (0..256) |number| {
        const path = std.fmt.bufPrintSentinel(&path_buffer, "/dev/input/event{d}", .{number}, 0) catch return error.System;
        const fd = open(path, false) catch continue;
        if (linux.errno(linux.ioctl(fd, 0x40044590, 1)) != .SUCCESS) {
            _ = linux.close(fd);
            return error.System;
        }
        devices[count] = .{ .fd = fd };
        var range: Abs = undefined;
        if (linux.errno(linux.ioctl(fd, 0x80184540, @intFromPtr(&range))) == .SUCCESS) devices[count].x = range;
        if (linux.errno(linux.ioctl(fd, 0x80184541, @intFromPtr(&range))) == .SUCCESS) devices[count].y = range;
        count += 1;
    }
    for ([_]linux.fd_t{ 0, 1 }) |fd| {
        const flags = try checked(linux.fcntl(fd, linux.F.GETFL, 0));
        _ = try checked(linux.fcntl(fd, linux.F.SETFL, flags | 0x800));
    }
    var text: [96]u8 = undefined;
    try send(std.fmt.bufPrint(&text, "READY {d} {d}", .{ v.xres, v.yres }) catch return error.Protocol, owner);
    var polls: [258]linux.pollfd = undefined;
    polls[0] = .{ .fd = 0, .events = linux.POLL.IN };
    polls[1] = .{ .fd = owner, .events = linux.POLL.IN };
    for (devices[0..count], 0..) |device, i| polls[i + 2] = .{ .fd = device.fd, .events = linux.POLL.IN };
    var header: [4]u8 = undefined;
    var header_used: usize = 0;
    var frame_used: usize = 0;
    var x: i32 = 0;
    var y: i32 = 0;
    while (true) {
        const polled = linux.poll(&polls, count + 2, -1);
        if (linux.errno(polled) == .INTR) continue;
        _ = try checked(polled);
        if (polls[1].revents != 0) return error.Closed;
        if (polls[0].revents & (linux.POLL.ERR | linux.POLL.NVAL) != 0) return error.Closed;
        if (polls[0].revents & (linux.POLL.IN | linux.POLL.HUP) != 0) {
            const target = if (header_used < 4) header[header_used..] else frame[frame_used..];
            const raw = linux.read(0, target.ptr, target.len);
            switch (linux.errno(raw)) {
                .SUCCESS => {
                    if (raw == 0) return;
                    if (header_used < 4) {
                        header_used += raw;
                        if (header_used == 4) {
                            const length = packetLength(header);
                            if (length == 0) {
                                for (devices[0..count]) |device| _ = linux.close(device.fd);
                                count = 0;
                                try release(owner);
                                return;
                            }
                            if (length != size) return error.Protocol;
                        }
                    } else {
                        frame_used += raw;
                        if (frame_used == size) {
                            present(memory, frame, f, v);
                            try send("PRESENTED", owner);
                            header_used = 0;
                            frame_used = 0;
                        }
                    }
                },
                .INTR, .AGAIN => {},
                else => return error.System,
            }
        }
        for (devices[0..count], 0..) |*device, i| {
            if (polls[i + 2].revents & (linux.POLL.HUP | linux.POLL.ERR | linux.POLL.NVAL) != 0) return error.Closed;
            if (polls[i + 2].revents & linux.POLL.IN == 0) continue;
            var events: [32]Event = undefined;
            const raw = linux.read(device.fd, @ptrCast(&events), @sizeOf(@TypeOf(events)));
            if (linux.errno(raw) == .AGAIN or linux.errno(raw) == .INTR) continue;
            const length = try checked(raw);
            if (length == 0 or length % @sizeOf(Event) != 0) return error.Protocol;
            for (events[0 .. length / @sizeOf(Event)]) |event| try input(device, event, &x, &y, v, owner);
        }
    }
}
pub fn main(_: std.process.Init.Minimal) noreturn {
    run() catch {
        const message = "elixos-gui-io: framebuffer/input session failed\n";
        _ = linux.write(2, message.ptr, message.len);
        linux.exit_group(1);
    };
    linux.exit_group(0);
}

test "M27 packet lengths are unsigned network order" {
    try milestone.require(27);
    try std.testing.expectEqual(@as(u32, 0x80010203), packetLength(.{ 0x80, 1, 2, 3 }));
    try std.testing.expectEqual(@as(u32, 0), packetLength(.{ 0, 0, 0, 0 }));
}
test "M27 channel conversion preserves RGB565 endpoints and rejects reversed fields" {
    try milestone.require(27);
    try std.testing.expectEqual(@as(u32, 0xf800), channel(255, .{ .offset = 11, .length = 5, .msb_right = 0 }));
    try std.testing.expectEqual(@as(u32, 0), channel(7, .{ .offset = 11, .length = 5, .msb_right = 0 }));
    try std.testing.expectError(error.Unsupported, fieldMask(.{ .offset = 0, .length = 8, .msb_right = 1 }, 32));
    try std.testing.expectError(error.Unsupported, fieldMask(.{ .offset = 15, .length = 8, .msb_right = 0 }, 16));
}
test "M27 absolute pointer scaling clamps signed ranges" {
    try milestone.require(27);
    const range: Abs = .{ .value = 0, .minimum = -100, .maximum = 100, .fuzz = 0, .flat = 0, .resolution = 0 };
    try std.testing.expectEqual(@as(i32, 0), absolute(-200, range, 101));
    try std.testing.expectEqual(@as(i32, 50), absolute(0, range, 101));
    try std.testing.expectEqual(@as(i32, 100), absolute(200, range, 101));
}
test "M27 extended keyboard codes are not mouse buttons" {
    try milestone.require(27);
    try std.testing.expect(buttonCode(0x110));
    try std.testing.expect(buttonCode(0x2c0));
    try std.testing.expect(!buttonCode(0x160));
    try std.testing.expect(!buttonCode(28));
}
test "M27 framebuffer rows preserve padding and visible offsets" {
    try milestone.require(27);
    var f = std.mem.zeroes(Fixed);
    f.visual = 2;
    f.line_length = 12;
    f.smem_len = 24;
    var v = std.mem.zeroes(Variable);
    v.xres = 1;
    v.yres = 1;
    v.xres_virtual = 3;
    v.yres_virtual = 2;
    v.xoffset = 1;
    v.yoffset = 1;
    v.bits_per_pixel = 24;
    v.red = .{ .offset = 16, .length = 8, .msb_right = 0 };
    v.green = .{ .offset = 8, .length = 8, .msb_right = 0 };
    v.blue = .{ .offset = 0, .length = 8, .msb_right = 0 };
    try std.testing.expectEqual(@as(usize, 4), try validate(f, v));
    var memory: [24]u8 = @splat(0xaa);
    present(&memory, &.{ 0x12, 0x34, 0x56, 0xff }, f, v);
    try std.testing.expectEqual(@as(u8, 0xaa), memory[14]);
    try std.testing.expectEqualSlices(u8, &.{ 0x56, 0x34, 0x12 }, memory[15..18]);
    try std.testing.expectEqual(@as(u8, 0xaa), memory[18]);
    f.smem_len = 17;
    try std.testing.expectError(error.Unsupported, validate(f, v));
    f.smem_len = 24;
    v.green.offset = 16;
    try std.testing.expectError(error.Unsupported, validate(f, v));
}
