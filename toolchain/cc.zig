//! cc: the toolchain's C compiler, next to zig on the disk (ADR-009, M11).
//!
//! zig only acts as a C compiler when it is given the `cc` subcommand - being
//! invoked under the name `cc` is not enough - so this bridge sits beside it
//! as `cc`/`c++` and execs `zig cc` (or `zig c++`) with the arguments it was
//! given. ADR-012: exec'd directly, never through a shell.

const std = @import("std");
const linux = std.os.linux;

pub fn main(init: std.process.Init.Minimal) noreturn {
    var arg_buf: [64][]const u8 = undefined;
    var count: usize = 0;
    var it = std.process.Args.Iterator.init(init.args);
    while (it.next()) |arg| {
        if (count == arg_buf.len) break;
        arg_buf[count] = arg;
        count += 1;
    }
    const args = arg_buf[0..count];
    if (args.len == 0) exit(127);

    const self_path = args[0];
    const dir = std.fs.path.dirname(self_path) orelse ".";

    var zig_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (dir.len + 4 > zig_buf.len) exit(127);
    @memcpy(zig_buf[0..dir.len], dir);
    zig_buf[dir.len] = '/';
    @memcpy(zig_buf[dir.len + 1 ..][0..3], "zig");
    zig_buf[dir.len + 4] = 0;
    const zig_path: [:0]const u8 = zig_buf[0 .. dir.len + 4 :0];

    const subcommand: [:0]const u8 = if (std.mem.endsWith(u8, self_path, "++")) "c++" else "cc";

    var argv: [66:null]?[*:0]const u8 = undefined;
    argv[0] = zig_path.ptr;
    argv[1] = subcommand.ptr;
    const n = @min(args.len - 1, arg_buf.len - 1);
    for (0..n) |i| argv[2 + i] = @ptrCast(args[1 + i].ptr);
    argv[2 + n] = null;

    _ = linux.execve(zig_path.ptr, @ptrCast(&argv), envp(init));
    exit(127);
}

fn envp(init: std.process.Init.Minimal) [*:null]const ?[*:0]const u8 {
    return @ptrCast(init.environ.block.slice.ptr);
}

fn exit(code: u8) noreturn {
    std.process.exit(code);
}
