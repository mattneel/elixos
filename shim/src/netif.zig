//! Network interface configuration shared by the shim (loopback and the
//! coprocessor link, M29) and elixos-link (the ring's TUN device, M31).
//! Raw ioctls on an AF_INET datagram socket; nothing here speaks the network.
const std = @import("std");
const linux = std.os.linux;
const cmdline = @import("cmdline.zig");

/// Reads the flags of a network interface, or an error.
pub fn interfaceFlags(fd: i32, name: []const u8) !linux.IFF {
    var request: linux.ifreq = std.mem.zeroes(linux.ifreq);
    if (name.len + 1 > request.ifrn.name.len) return error.NameTooLong;
    @memcpy(request.ifrn.name[0..name.len], name);

    if (linux.errno(linux.ioctl(fd, linux.SIOCGIFFLAGS, @intFromPtr(&request))) != .SUCCESS) {
        return error.IoctlFailed;
    }

    return request.ifru.flags;
}

/// Address, netmask, then up.
pub fn setLink(link: cmdline.Link) !void {
    const fd = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (linux.errno(fd) != .SUCCESS) return error.SocketFailed;
    defer _ = linux.close(@intCast(fd));

    var request: linux.ifreq = std.mem.zeroes(linux.ifreq);
    if (link.interface.len + 1 > request.ifrn.name.len) return error.NameTooLong;
    @memcpy(request.ifrn.name[0..link.interface.len], link.interface);

    const mask: u32 = if (link.prefix == 32) 0xffff_ffff else ~(@as(u32, 0xffff_ffff) >> @intCast(link.prefix));
    const address: linux.sockaddr.in = .{ .port = 0, .addr = @bitCast(link.address) };
    const netmask: linux.sockaddr.in = .{ .port = 0, .addr = std.mem.nativeToBig(u32, mask) };

    request.ifru.addr = @as(*const linux.sockaddr, @ptrCast(&address)).*;
    if (linux.errno(linux.ioctl(@intCast(fd), linux.SIOCSIFADDR, @intFromPtr(&request))) != .SUCCESS)
        return error.AddressFailed;
    request.ifru.netmask = @as(*const linux.sockaddr, @ptrCast(&netmask)).*;
    if (linux.errno(linux.ioctl(@intCast(fd), linux.SIOCSIFNETMASK, @intFromPtr(&request))) != .SUCCESS)
        return error.NetmaskFailed;

    var flags = try interfaceFlags(@intCast(fd), link.interface);
    flags.UP = true;
    flags.RUNNING = true;
    request.ifru.flags = flags;
    if (linux.errno(linux.ioctl(@intCast(fd), linux.SIOCSIFFLAGS, @intFromPtr(&request))) != .SUCCESS)
        return error.FlagsFailed;
}
