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

    // initdb narrates every step and every failure. The console belongs to the
    // shim's own lines and the REPL (PROTOCOL.md §6): a boot must not have
    // ~40 lines of initialization interleaved with the first prompt, so the
    // log directory - where the postmaster writes too (ADR-053) - takes them.
    // A failure to open the log is not fatal: the console then keeps them.
    redirectLog();

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

/// Point stdout and stderr at the cluster's log file for the exec'd initdb.
fn redirectLog() void {
    const raw = linux.openat(linux.AT.FDCWD, "/priv/postgres/log/initdb.log", .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .APPEND = true,
    }, 0o644);
    if (linux.errno(raw) != .SUCCESS) return;

    const fd: linux.fd_t = @intCast(raw);
    _ = linux.dup2(fd, 1);
    _ = linux.dup2(fd, 2);
    if (fd > 2) _ = linux.close(fd);
}

fn fail(message: []const u8) noreturn {
    _ = linux.write(2, message.ptr, message.len);
    linux.exit_group(1);
}
