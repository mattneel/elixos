//! Idempotent initdb guard, executed only by PID 1's postgres-init helper as
//! uid/gid 70. A binary, not a shell script; no allocation or libc.
const std = @import("std");
const linux = std.os.linux;
const system_image = @import("system_image.zig");

pub fn main(_: std.process.Init.Minimal) noreturn {
    const version = linux.openat(linux.AT.FDCWD, "/priv/postgres/data/PG_VERSION", .{
        .NOFOLLOW = true,
        .NONBLOCK = true,
        .CLOEXEC = true,
    }, 0);
    switch (linux.errno(version)) {
        .SUCCESS => {
            const fd: linux.fd_t = @intCast(version);
            var metadata: linux.Statx = undefined;
            const result = linux.statx(fd, "", linux.AT.EMPTY_PATH | linux.AT.SYMLINK_NOFOLLOW, .{ .TYPE = true }, &metadata);
            _ = linux.close(fd);
            if (linux.errno(result) != .SUCCESS or !metadata.mask.TYPE or !linux.S.ISREG(metadata.mode))
                fail("elixos-postgres-init: PG_VERSION is not a regular file\n");
            linux.exit_group(0);
        },
        .NOENT => {},
        else => fail("elixos-postgres-init: cannot inspect existing cluster\n"),
    }

    const executable = "/system/usr/libexec/postgresql17/initdb";
    const argv = [_:null]?[*:0]const u8{
        executable,
        "-D",
        "/priv/postgres/data",
        "-U",
        "postgres",
        "-A",
        "trust",
        "--locale=C.UTF-8",
        "-E",
        "UTF8",
    };
    const envp = [_:null]?[*:0]const u8{
        system_image.path_environment,
        system_image.library_environment,
        "LANG=C.UTF-8",
        "HOME=/priv/postgres",
    };
    _ = linux.execve(executable, &argv, &envp);
    fail("elixos-postgres-init: cannot exec initdb\n");
}

fn fail(message: []const u8) noreturn {
    _ = linux.write(2, message.ptr, message.len);
    linux.exit_group(1);
}
