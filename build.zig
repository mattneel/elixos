//! Builds the Elixos PID 1 shim (`zig-out/bin/init`) and runs its unit tests.
//!
//!   zig build -Doptimize=ReleaseSafe          the static /init for the initramfs
//!   zig build test -Dmilestone=$(cat MILESTONE)   host unit tests, gated by milestone
//!
//! The Makefile passes -Dmilestone for you; see docs/TESTING.md.
const std = @import("std");

pub fn build(b: *std.Build) void {
    // ADR-041: x86_64 and aarch64 both. The shim is static and libc-free
    // (ADR-003), so the target changes only the instruction set. The default
    // follows the compiler's host, not the package root's architecture.
    // melange uses a pinned host-native compiler and always overrides this
    // with `-Dtarget=<arch>-linux-none`, including for ARM64 packages.
    const host = b.graph.host.result;
    const target = b.standardTargetOptions(.{
        .default_target = .{ .cpu_arch = host.cpu.arch, .os_tag = .linux, .abi = .none },
    });
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const milestone = b.option(
        u32,
        "milestone",
        "Current Elixos milestone (the MILESTONE file). Tests for later milestones are skipped.",
    ) orelse 0;
    const test_hooks = b.option(
        bool,
        "test-hooks",
        "Honor elixos.test.* kernel command line hooks. QEMU test images only, never releases.",
    ) orelse false;

    const options = b.addOptions();
    options.addOption(u32, "milestone", milestone);
    options.addOption(bool, "test_hooks", test_hooks);

    const shim = b.addExecutable(.{
        .name = "init",
        .root_module = shimModule(b, target, optimize, options),
    });
    b.installArtifact(shim);

    const postgres_init = b.addExecutable(.{
        .name = "elixos-postgres-init",
        .root_module = b.createModule(.{
            .root_source_file = b.path("shim/src/postgres_init.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
        }),
    });
    postgres_init.root_module.addOptions("build_options", options);
    b.installArtifact(postgres_init);

    for ([_]struct { name: []const u8, source: []const u8 }{
        .{ .name = "elixos-gui-io", .source = "shim/src/gui_io.zig" },
        .{ .name = "elixos-console-handover", .source = "shim/src/console_handover.zig" },
    }) |helper| {
        const executable = b.addExecutable(.{
            .name = helper.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(helper.source),
                .target = target,
                .optimize = optimize,
                .single_threaded = true,
            }),
        });
        executable.root_module.addOptions("build_options", options);
        b.installArtifact(executable);
    }

    // Unit tests run natively on the dev host (WSL2 is x86_64 Linux as well).
    const tests = b.addTest(.{
        .root_module = shimModule(b, b.graph.host, .Debug, options),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run shim unit tests (gated by -Dmilestone)");
    test_step.dependOn(&run_tests.step);
}

fn shimModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    options: *std.Build.Step.Options,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("shim/src/main.zig"),
        .target = target,
        .optimize = optimize,
        // PID 1 never needs threads; keeping it single-threaded keeps it simple.
        .single_threaded = true,
    });
    mod.addOptions("build_options", options);
    // Golden vectors shared with the Elixir suite (docs/TESTING.md §Shared vectors).
    mod.addAnonymousImport("protocol_vectors", .{
        .root_source_file = b.path("spec/protocol.vectors"),
    });
    return mod;
}
