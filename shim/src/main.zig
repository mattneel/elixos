//! Elixos PID 1 shim (ADR-002..004, docs/ARCHITECTURE.md §3).
//!
//! The kernel execs this binary as /init from the initramfs. It must never
//! exit: PID 1 exiting panics the kernel, which is why `main` is `noreturn`.
//!
//! Its jobs, built up over milestones M3..M8 (docs/ROADMAP.md):
//!
//!   1. Mount /proc, /sys, /dev (devtmpfs), /run and /tmp (tmpfs).
//!   2. Read /proc/cmdline -> cmdline.parse. Log the banner and invalid tokens.
//!   3. Mount the data device (elixos.data, ext4) on /data. Missing: rescue.
//!   4. Read /data/boot.state -> statefile.parse. Missing file: defaults.
//!      Corrupt file: rescue override, and never overwrite the evidence.
//!   5. recovery.planLaunch, persist next_state atomically, log the plan.
//!   6. Create the control pipe and exec ERTS (erlexec) for the planned
//!      generation with the environment contract in PROTOCOL.md §3.
//!   7. Event loop (epoll): signalfd for SIGCHLD/SIGTERM/SIGINT/SIGPWR;
//!      control lines -> protocol.parse -> recovery.applyMessage (persist on
//!      change); timerfd heartbeat deadline (boot_grace, then hb_timeout).
//!   8. Reap every child; PID 1 inherits orphans. On BEAM exit ->
//!      recovery.onBeamExit -> relaunch after a short backoff, or shut down.
//!   9. Shutdown: SIGTERM then SIGKILL stragglers, sync, unmount /data,
//!      reboot(2) with RESTART / POWER_OFF / HALT.
//!
//! Every console line it prints follows the log contract in PROTOCOL.md §6;
//! the QEMU tests match on those lines, so treat them as API.
//!
//! Prefer raw std.os.linux syscalls here. Allocate nothing after startup.
const std = @import("std");
const build_options = @import("build_options");

pub const milestone = @import("milestone.zig");
pub const decimal = @import("decimal.zig");
pub const protocol = @import("protocol.zig");
pub const statefile = @import("statefile.zig");
pub const cmdline = @import("cmdline.zig");
pub const recovery = @import("recovery.zig");

/// Printed in the banner: "elixos-shim: pid 1, version <version>".
pub const version = "0.0.0";

/// elixos.test.* hooks are compiled in only for QEMU test images (`-Dtest-hooks=true`).
pub const test_hooks = build_options.test_hooks;

// ADR-004 (M8): replace the default panic handler with one that re-execs
// /init in rescue mode instead of letting PID 1 die, e.g.
//
//   pub const panic = std.debug.FullPanic(rescuePanic);
//   fn rescuePanic(msg: []const u8, first_trace_addr: ?usize) noreturn { ... execve ... }
//
// Build its argv/envp at startup (BEAM pid, control fd) so the handler never
// allocates. execve keeps PID 1, and the BEAM stays our child across it.

pub fn main(init: std.process.Init.Minimal) noreturn {
    _ = init;
    @panic("TODO(M3): PID 1 duties, see the list at the top of shim/src/main.zig");
}

test {
    // Zig only analyzes what is referenced, so broken code can compile "clean"
    // (AGENTS.md §Zig). This pulls every shim file through semantic analysis
    // and collects their tests.
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(decimal);
    std.testing.refAllDecls(protocol);
    std.testing.refAllDecls(statefile);
    std.testing.refAllDecls(cmdline);
    std.testing.refAllDecls(recovery);
}
