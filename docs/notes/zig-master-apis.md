# Zig master APIs hit while writing the shim

Pinned: 0.18.0-dev.131+41f885830. The std source next to the compiler is the
authority; this file just saves the next search.

- `std.fmt.bufPrintZ` is gone. NUL-terminated printing is
  `std.mem.printSentinel(buf, fmt, args, 0)`, which returns `[:0]u8`
  (`PrintError![:sentinel]u8`); use `.ptr` where a `[*:0]const u8` is wanted.
- Syscall wrappers return the raw `usize`; the errno enum is
  `std.os.linux.errno(rc)` (`E`, `.SUCCESS` when non-negative). `E`'s field
  names drop the C `E` prefix (`NOENT`), so print `"E{t}"` for `ENOENT`.
- `std.os.linux.O` is a packed struct: `.{ .ACCMODE = .WRONLY, .CREAT = true }`.
  `MS` mount flags are plain constants.
- `std.os.linux.reboot(magic1: LINUX_REBOOT.MAGIC1, magic2: MAGIC2, cmd: CMD, arg)`
  with `.RESTART`, `.POWER_OFF` and `.HALT`.
- `{t}` prints an enum's tag name, `{q}` quotes a string, `{d}` a number.
- `std.mem.splitScalar("")` yields one empty item, not zero: strip the trailing
  newline and special-case the empty text (`statefile.parse` rule 1).
- `std.process.Init.Minimal` is the allocation-free `main` parameter: `.args`
  and `.environ` only. A `noreturn` `main` is fine.
- `std.testing.refAllDecls(@This())` is what keeps lazily-analyzed files
  honest; every new shim file must be listed in `main.zig`'s test block.
