//! Fixed-path, single-lease fbcon broker. No caller-controlled privileged operations.
const std = @import("std");
const linux = std.os.linux;
const milestone = @import("milestone.zig");
const Failure = error{ System, Unsafe, Protocol };
const Unix = extern struct { family: u16 = 1, path: [108]u8 = @splat(0) };
const Credentials = extern struct { pid: i32, uid: u32, gid: u32 };
const bad_events = linux.POLL.ERR | linux.POLL.HUP | linux.POLL.NVAL;
fn checked(raw: usize) Failure!usize {
    return switch (linux.errno(raw)) {
        .SUCCESS => raw,
        else => error.System,
    };
}
fn metadata(fd: linux.fd_t) Failure!linux.Statx {
    var value: linux.Statx = undefined;
    _ = try checked(linux.statx(fd, "", linux.AT.EMPTY_PATH | linux.AT.SYMLINK_NOFOLLOW, .{ .TYPE = true, .MODE = true, .UID = true }, &value));
    if (!value.mask.TYPE or !value.mask.MODE or !value.mask.UID) return error.Unsafe;
    return value;
}
fn directory(parent: linux.fd_t, path: [*:0]const u8) Failure!linux.fd_t {
    const fd: linux.fd_t = @intCast(try checked(linux.openat(parent, path, .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0)));
    errdefer _ = linux.close(fd);
    const info = try metadata(fd);
    if (info.uid != 0 or info.mode & 0o022 != 0 or !linux.S.ISDIR(info.mode)) return error.Unsafe;
    return fd;
}
fn grant(parent: linux.fd_t, name: [*:0]const u8, group: u32) Failure!void {
    const raw = linux.openat(parent, name, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (linux.errno(raw) == .NOENT) return;
    const fd: linux.fd_t = @intCast(try checked(raw));
    defer _ = linux.close(fd);
    const info = try metadata(fd);
    if (!linux.S.ISCHR(info.mode) or info.uid != 0) return error.Unsafe;
    _ = try checked(linux.fchown(fd, 0, group));
    _ = try checked(linux.fchmod(fd, 0o660));
}
fn grantDevices() Failure!void {
    const dev = try directory(linux.AT.FDCWD, "/dev");
    defer _ = linux.close(dev);
    try grant(dev, "fb0", 27);
    const raw = linux.openat(dev, "input", .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (linux.errno(raw) == .NOENT) return;
    const input: linux.fd_t = @intCast(try checked(raw));
    defer _ = linux.close(input);
    const info = try metadata(input);
    if (info.uid != 0 or info.mode & 0o022 != 0) return error.Unsafe;
    var buffer: [32]u8 = undefined;
    for (0..256) |number| {
        const name = std.fmt.bufPrintSentinel(&buffer, "event{d}", .{number}, 0) catch return error.System;
        try grant(input, name, 23);
    }
}
fn framebufferName(name: []const u8) bool {
    // The kernel's vtconsole name is "(M) frame buffer device". Never touch
    // dummy or serial console bindings, nor match arbitrary partial names.
    return std.mem.eql(u8, name, "(M) frame buffer device") or
        std.mem.eql(u8, name, "(M) frame buffer device\n");
}
const Consoles = struct {
    fds: [64]linux.fd_t = @splat(-1),
    count: usize = 0,
    fn discover(self: *Consoles) Failure!void {
        var buffer: [128]u8 = undefined;
        // /sys/class/vtconsole/vtconN are symlinks. Use the real kernel-owned
        // virtual-device directory, and reject symlinks on every opened leaf.
        const raw = linux.openat(linux.AT.FDCWD, "/sys/devices/virtual/vtconsole", .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
        if (linux.errno(raw) == .NOENT) return;
        const root: linux.fd_t = @intCast(try checked(raw));
        defer _ = linux.close(root);
        for (0..64) |number| {
            const name = std.fmt.bufPrintSentinel(&buffer, "vtcon{d}", .{number}, 0) catch return error.System;
            const entry_raw = linux.openat(root, name, .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
            if (linux.errno(entry_raw) == .NOENT) continue;
            const entry: linux.fd_t = @intCast(try checked(entry_raw));
            defer _ = linux.close(entry);
            const name_fd: linux.fd_t = @intCast(try checked(linux.openat(entry, "name", .{ .NOFOLLOW = true, .CLOEXEC = true }, 0)));
            var text: [128]u8 = undefined;
            const length_raw = linux.read(name_fd, &text, text.len);
            _ = linux.close(name_fd);
            const length = try checked(length_raw);
            if (!framebufferName(text[0..length])) continue;
            const fd: linux.fd_t = @intCast(try checked(linux.openat(entry, "bind", .{ .ACCMODE = .RDWR, .NOFOLLOW = true, .CLOEXEC = true }, 0)));
            self.fds[self.count] = fd;
            self.count += 1;
        }
    }
    fn set(self: *Consoles, bound: bool) Failure!void {
        var failed = false;
        for (self.fds[0..self.count]) |fd| {
            const value: []const u8 = if (bound) "1" else "0";
            // sysfs attributes require offset zero for each write.
            const result = linux.pwrite(fd, value.ptr, 1, 0);
            if (linux.errno(result) != .SUCCESS or result != 1) failed = true;
        }
        if (failed) return error.System;
    }
    fn close(self: *Consoles) void {
        for (self.fds[0..self.count]) |fd| {
            _ = linux.close(fd);
        }
    }
};
fn signals() Failure!linux.fd_t {
    var mask = linux.sigemptyset();
    for ([_]linux.SIG{ .TERM, .INT, .HUP, .QUIT, .PIPE }) |sig| linux.sigaddset(&mask, sig);
    _ = try checked(linux.sigprocmask(linux.SIG.BLOCK, &mask, null));
    return @intCast(try checked(linux.signalfd(-1, &mask, 0x80000 | 0x800)));
}
fn permitted(fd: linux.fd_t) bool {
    var credentials: Credentials = undefined;
    var length: linux.socklen_t = @sizeOf(Credentials);
    return linux.errno(linux.getsockopt(fd, linux.SOL.SOCKET, linux.SO.PEERCRED, @ptrCast(&credentials), &length)) == .SUCCESS and
        length == @sizeOf(Credentials) and credentials.uid == 1000;
}
fn serve(listener: linux.fd_t, signal_fd: linux.fd_t, consoles: *Consoles) Failure!void {
    var client: linux.fd_t = -1;
    defer {
        if (client >= 0) _ = linux.close(client);
    }
    while (true) {
        var polls = [_]linux.pollfd{ .{ .fd = signal_fd, .events = linux.POLL.IN }, .{ .fd = listener, .events = linux.POLL.IN }, .{ .fd = client, .events = linux.POLL.IN } };
        const result = linux.poll(&polls, polls.len, -1);
        if (linux.errno(result) == .INTR) continue;
        _ = try checked(result);
        if (polls[0].revents != 0) return;
        if (client >= 0 and polls[2].revents != 0) {
            // A lease has no commands. EOF, data, or any error releases it.
            // Rebind before accepting another lease, including queued peers.
            var closing: [1]u8 = undefined;
            const received = linux.read(client, &closing, 1);
            try consoles.set(true);
            if (linux.errno(received) == .SUCCESS and received > 0) {
                const released = "C";
                _ = try checked(linux.write(client, released.ptr, released.len));
            }
            _ = linux.close(client);
            client = -1;
        }
        if (polls[1].revents & bad_events != 0) return error.System;
        if (polls[1].revents & linux.POLL.IN == 0) continue;
        const raw = linux.accept4(listener, null, null, 0x80000 | 0x800);
        if (linux.errno(raw) == .AGAIN or linux.errno(raw) == .INTR) continue;
        const accepted: linux.fd_t = @intCast(try checked(raw));
        if (client >= 0 or !permitted(accepted)) {
            _ = linux.close(accepted);
            continue;
        }
        client = accepted;
        try grantDevices();
        try consoles.set(false);
        const ready = "R";
        if (linux.errno(linux.write(client, ready.ptr, 1)) != .SUCCESS) {
            _ = linux.close(client);
            client = -1;
            try consoles.set(true);
        }
    }
}
fn run() Failure!void {
    if (linux.getuid() != 0) return error.Unsafe;
    const signal_fd = try signals();
    defer _ = linux.close(signal_fd);
    const run_dir = try directory(linux.AT.FDCWD, "/run");
    defer _ = linux.close(run_dir);
    const lock: linux.fd_t = @intCast(try checked(linux.openat(run_dir, "elixos-console.lock", .{ .ACCMODE = .RDWR, .CREAT = true, .NOFOLLOW = true, .CLOEXEC = true, .NONBLOCK = true }, 0o600)));
    defer _ = linux.close(lock);
    const info = try metadata(lock);
    if (info.uid != 0 or !linux.S.ISREG(info.mode) or info.mode & 0o077 != 0) return error.Unsafe;
    // The helper ensures a broker exists; a GUI restart reuses the live one.
    switch (linux.errno(linux.flock(lock, 2 | 4))) { // LOCK_EX | LOCK_NB
        .SUCCESS => {},
        .AGAIN => return,
        else => return error.System,
    }
    var consoles: Consoles = .{};
    defer consoles.close();
    try consoles.discover();
    // A SIGKILL/power loss of the previous broker may leave these unbound.
    try consoles.set(true);
    defer {
        consoles.set(true) catch {};
    }
    try grantDevices();
    var stale: linux.Statx = undefined;
    const inspected = linux.statx(run_dir, "elixos-console.sock", linux.AT.SYMLINK_NOFOLLOW, .{ .TYPE = true, .UID = true }, &stale);
    switch (linux.errno(inspected)) {
        .SUCCESS => {
            if (!stale.mask.TYPE or !stale.mask.UID or stale.uid != 0 or !linux.S.ISSOCK(stale.mode)) return error.Unsafe;
            _ = try checked(linux.unlinkat(run_dir, "elixos-console.sock", 0));
        },
        .NOENT => {},
        else => return error.System,
    }
    const listener: linux.fd_t = @intCast(try checked(linux.socket(1, 1 | 0x80000 | 0x800, 0)));
    defer _ = linux.close(listener);
    var address: Unix = .{};
    const path = "/run/elixos-console.sock";
    @memcpy(address.path[0..path.len], path);
    _ = try checked(linux.bind(listener, @ptrCast(&address), @sizeOf(Unix)));
    defer _ = linux.unlinkat(run_dir, "elixos-console.sock", 0);
    _ = try checked(linux.listen(listener, 8));
    _ = try checked(linux.fchownat(run_dir, "elixos-console.sock", 0, 1000, linux.AT.SYMLINK_NOFOLLOW));
    // Publishing mode 0660 is the client's readiness barrier: listen first.
    _ = try checked(linux.fchmodat(run_dir, "elixos-console.sock", 0o660));
    try serve(listener, signal_fd, &consoles);
}
pub fn main(_: std.process.Init.Minimal) noreturn {
    run() catch {
        const message = "elixos-console-handover: console lease failed\n";
        _ = linux.write(2, message.ptr, message.len);
        linux.exit_group(1);
    };
    linux.exit_group(0);
}
test "M27 only framebuffer vtconsole names qualify for handover" {
    try milestone.require(27);
    try std.testing.expect(framebufferName("(M) frame buffer device\n"));
    try std.testing.expect(!framebufferName("(S) dummy device\n"));
    try std.testing.expect(!framebufferName("serial console\n"));
}
