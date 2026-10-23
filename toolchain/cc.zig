//! cc: the toolchain's C compiler, next to zig on the disk (ADR-009, M11).
//!
//! zig only acts as a C compiler when it is given the `cc` subcommand - being
//! invoked under the name `cc` is not enough - so this bridge sits beside it
//! as `cc`/`c++` and execs `zig cc` (or `zig c++`) with the arguments it was
//! given. ADR-012: exec'd directly, never through a shell.

const std = @import("std");
const linux = std.os.linux;

pub fn main(init: std.process.Init.Minimal) noreturn {
    const args = init.args.vector;
    if (args.len == 0) exit(127);

    const self_path = std.mem.span(args[0]);
    const dir = std.fs.path.dirname(self_path) orelse ".";

    var zig_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (dir.len > zig_buf.len - 4) exit(127);
    @memcpy(zig_buf[0..dir.len], dir);
    zig_buf[dir.len] = '/';
    @memcpy(zig_buf[dir.len + 1 ..][0..3], "zig");
    zig_buf[dir.len + 4] = 0;
    const zig_path: [:0]const u8 = zig_buf[0 .. dir.len + 4 :0];

    const subcommand: [:0]const u8 = if (std.mem.endsWith(u8, self_path, "++")) "c++" else "cc";

    // Cargo link invocations routinely exceed 64 arguments. Borrow their
    // strings and allocate only the extra argv pointer slots, once at startup.
    const argv = std.heap.page_allocator.allocSentinel(?[*:0]const u8, args.len + 1, null) catch exit(127);
    argv[0] = zig_path.ptr;
    argv[1] = subcommand.ptr;
    for (args[1..], argv[2..]) |arg, *destination| destination.* = arg;

    _ = linux.execve(zig_path.ptr, argv.ptr, envp(init));
    exit(127);
}

fn envp(init: std.process.Init.Minimal) [*:null]const ?[*:0]const u8 {
    return @ptrCast(init.environ.block.slice.ptr);
}

fn exit(code: u8) noreturn {
    std.process.exit(code);
}
