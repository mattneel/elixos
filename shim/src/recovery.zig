//! Recovery policy (ADR-007, docs/ARCHITECTURE.md §3.3). Pure decisions only;
//! main.zig carries them out with syscalls. Every rule below has a test.
//!
//! The chain is: provisional generation -> last_good -> factory in rescue mode.
//! Attempts are counted *before* a launch is made, so a crash, a hang or a
//! power cut half way through boot still counts against that generation.
const std = @import("std");
const testing = std.testing;
const milestone = @import("milestone.zig");
const protocol = @import("protocol.zig");

/// Persisted in boot.state (statefile.zig). Generation 0 is the factory image.
pub const BootState = struct {
    /// Generation to boot next.
    current: u32 = 0,
    /// Newest generation that booted and was committed healthy.
    last_good: u32 = 0,
    /// Launches of `current` since it was selected or last committed.
    attempts: u32 = 0,
};

pub const Mode = enum { normal, rescue };

pub const Launch = struct { generation: u32, mode: Mode };

/// Persist `next_state` (written and fsync'd) first, then perform `launch`.
pub const Plan = struct { launch: Launch, next_state: BootState };

pub const Overrides = struct {
    /// elixos.safe, an unreadable boot.state, or a shim recovering from its own panic.
    safe: bool = false,
    /// elixos.generation=N: boot N once, outside the attempt accounting.
    generation: ?u32 = null,
};

pub const Policy = struct {
    /// Launches allowed before falling back (elixos.max_attempts).
    max_attempts: u32 = 3,
};

pub const Shutdown = enum { reboot, poweroff, halt };

pub const Outcome = struct { state: BootState, shutdown: ?Shutdown = null };

pub const ExitDecision = union(enum) { shutdown: Shutdown, relaunch: Plan };

/// What to launch when the shim starts, and after any exit nobody asked for.
pub fn planLaunch(state: BootState, policy: Policy, overrides: Overrides) Plan {
    // A safe override boots the factory in rescue mode and leaves the state
    // alone: it is what an unreadable boot.state or elixos.safe asks for.
    if (overrides.safe) return .{ .launch = .{ .generation = 0, .mode = .rescue }, .next_state = state };
    // A generation override boots that generation once, outside accounting.
    if (overrides.generation) |generation| {
        return .{ .launch = .{ .generation = generation, .mode = .normal }, .next_state = state };
    }
    // Attempts are counted *before* the launch, so a crash or a power cut still
    // counts against this generation (ADR-007).
    if (state.attempts < policy.max_attempts) {
        return .{
            .launch = .{ .generation = state.current, .mode = .normal },
            .next_state = .{
                .current = state.current,
                .last_good = state.last_good,
                .attempts = state.attempts +| 1,
            },
        };
    }
    // Exhausted and not the same as last_good: fall back to it.
    if (state.current != state.last_good) {
        return .{
            .launch = .{ .generation = state.last_good, .mode = .normal },
            .next_state = .{ .current = state.last_good, .last_good = state.last_good, .attempts = 1 },
        };
    }
    // Even last_good is exhausted: the factory, in rescue mode, state untouched.
    return .{ .launch = .{ .generation = 0, .mode = .rescue }, .next_state = state };
}

/// Applies one control message from the BEAM.
pub fn applyMessage(state: BootState, msg: protocol.Message) Outcome {
    return switch (msg) {
        // Heartbeats are the shim's liveness signal; they change no state.
        .heartbeat => .{ .state = state },
        // Helper launches belong to the runtime, never the recovery policy.
        .helper => .{ .state = state },
        // Only the running generation can be committed (PROTOCOL.md §2).
        .commit => |generation| if (generation == state.current)
            .{ .state = .{ .current = state.current, .last_good = generation, .attempts = 0 } }
        else
            .{ .state = state },
        // A provisional generation: attempts start over for it.
        .next => |generation| .{ .state = .{
            .current = generation,
            .last_good = state.last_good,
            .attempts = 0,
        } },
        .reboot => .{ .state = state, .shutdown = .reboot },
        .poweroff => .{ .state = state, .shutdown = .poweroff },
        .halt => .{ .state = state, .shutdown = .halt },
    };
}

/// The BEAM exited: it crashed, was killed after a heartbeat timeout, or was
/// asked to shut down (`requested` is then the last shutdown message received).
pub fn onBeamExit(state: BootState, policy: Policy, overrides: Overrides, requested: ?Shutdown) ExitDecision {
    if (requested) |shutdown| return .{ .shutdown = shutdown };
    // A generation override is good for exactly one launch: drop it, keep safe.
    return .{ .relaunch = planLaunch(state, policy, .{ .safe = overrides.safe }) };
}

// ---------------------------------------------------------------------------
// Tests: the recovery spec, one rule per test.

const default_policy: Policy = .{};

fn plan(state: BootState) Plan {
    return planLaunch(state, default_policy, .{});
}

fn launchOf(generation: u32, mode: Mode, next_state: BootState) Plan {
    return .{ .launch = .{ .generation = generation, .mode = mode }, .next_state = next_state };
}

test "recovery: a blank disk boots the factory and counts the attempt" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        launchOf(0, .normal, .{ .current = 0, .last_good = 0, .attempts = 1 }),
        plan(.{}),
    );
}

test "recovery: a provisional generation is launched and counted before launch" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        launchOf(5, .normal, .{ .current = 5, .last_good = 4, .attempts = 1 }),
        plan(.{ .current = 5, .last_good = 4, .attempts = 0 }),
    );
    try testing.expectEqualDeep(
        launchOf(5, .normal, .{ .current = 5, .last_good = 4, .attempts = 3 }),
        plan(.{ .current = 5, .last_good = 4, .attempts = 2 }),
    );
}

test "recovery: an exhausted provisional generation falls back to last_good" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        launchOf(4, .normal, .{ .current = 4, .last_good = 4, .attempts = 1 }),
        plan(.{ .current = 5, .last_good = 4, .attempts = 3 }),
    );
}

test "recovery: an exhausted last_good boots the factory in rescue mode and leaves state alone" {
    try milestone.require(1);
    const stuck: BootState = .{ .current = 4, .last_good = 4, .attempts = 3 };
    try testing.expectEqualDeep(launchOf(0, .rescue, stuck), plan(stuck));
    const factory_stuck: BootState = .{ .current = 0, .last_good = 0, .attempts = 3 };
    try testing.expectEqualDeep(launchOf(0, .rescue, factory_stuck), plan(factory_stuck));
}

test "recovery: elixos.safe boots the factory in rescue mode without touching state" {
    try milestone.require(1);
    const state: BootState = .{ .current = 5, .last_good = 4, .attempts = 0 };
    try testing.expectEqualDeep(
        launchOf(0, .rescue, state),
        planLaunch(state, default_policy, .{ .safe = true }),
    );
}

test "recovery: elixos.generation boots that generation once, outside the accounting" {
    try milestone.require(1);
    const state: BootState = .{ .current = 5, .last_good = 4, .attempts = 1 };
    try testing.expectEqualDeep(
        launchOf(9, .normal, state),
        planLaunch(state, default_policy, .{ .generation = 9 }),
    );
}

test "recovery: safe wins over a generation override" {
    try milestone.require(1);
    const state: BootState = .{ .current = 5, .last_good = 4, .attempts = 1 };
    try testing.expectEqualDeep(
        launchOf(0, .rescue, state),
        planLaunch(state, default_policy, .{ .safe = true, .generation = 9 }),
    );
}

test "recovery: max_attempts is configurable" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        launchOf(4, .normal, .{ .current = 4, .last_good = 4, .attempts = 1 }),
        planLaunch(.{ .current = 5, .last_good = 4, .attempts = 1 }, .{ .max_attempts = 1 }, .{}),
    );
}

test "recovery: attempts saturate instead of overflowing" {
    try milestone.require(1);
    const max = std.math.maxInt(u32);
    const p = planLaunch(.{ .current = 5, .last_good = 4, .attempts = max - 1 }, .{ .max_attempts = max }, .{});
    try testing.expectEqual(@as(u32, max), p.next_state.attempts);
    try testing.expectEqual(@as(u32, 5), p.launch.generation);
}

test "recovery: COMMIT of the running generation marks it good and resets attempts" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        Outcome{ .state = .{ .current = 5, .last_good = 5, .attempts = 0 } },
        applyMessage(.{ .current = 5, .last_good = 4, .attempts = 2 }, .{ .commit = 5 }),
    );
}

test "recovery: a stale COMMIT is ignored" {
    try milestone.require(1);
    const state: BootState = .{ .current = 5, .last_good = 4, .attempts = 2 };
    try testing.expectEqualDeep(Outcome{ .state = state }, applyMessage(state, .{ .commit = 3 }));
}

test "recovery: NEXT selects a provisional generation for the next boot" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        Outcome{ .state = .{ .current = 6, .last_good = 5, .attempts = 0 } },
        applyMessage(.{ .current = 5, .last_good = 5, .attempts = 1 }, .{ .next = 6 }),
    );
}

test "recovery: heartbeats change nothing" {
    try milestone.require(1);
    const state: BootState = .{ .current = 5, .last_good = 4, .attempts = 2 };
    try testing.expectEqualDeep(Outcome{ .state = state }, applyMessage(state, .heartbeat));
}

test "recovery: shutdown requests are recorded and leave state alone" {
    try milestone.require(1);
    const state: BootState = .{ .current = 5, .last_good = 5, .attempts = 0 };
    try testing.expectEqualDeep(Outcome{ .state = state, .shutdown = .reboot }, applyMessage(state, .reboot));
    try testing.expectEqualDeep(Outcome{ .state = state, .shutdown = .poweroff }, applyMessage(state, .poweroff));
    try testing.expectEqualDeep(Outcome{ .state = state, .shutdown = .halt }, applyMessage(state, .halt));
}

test "recovery: a requested shutdown is carried out when the BEAM exits" {
    try milestone.require(1);
    const state: BootState = .{ .current = 5, .last_good = 5, .attempts = 0 };
    try testing.expectEqualDeep(
        ExitDecision{ .shutdown = .poweroff },
        onBeamExit(state, default_policy, .{}, .poweroff),
    );
}

test "recovery: an unrequested exit relaunches through planLaunch" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        ExitDecision{ .relaunch = launchOf(5, .normal, .{ .current = 5, .last_good = 4, .attempts = 2 }) },
        onBeamExit(.{ .current = 5, .last_good = 4, .attempts = 1 }, default_policy, .{}, null),
    );
}

test "recovery: a generation override is not retried after a crash" {
    try milestone.require(1);
    try testing.expectEqualDeep(
        ExitDecision{ .relaunch = launchOf(5, .normal, .{ .current = 5, .last_good = 4, .attempts = 2 }) },
        onBeamExit(.{ .current = 5, .last_good = 4, .attempts = 1 }, default_policy, .{ .generation = 9 }, null),
    );
}

test "recovery: safe mode survives crashes" {
    try milestone.require(1);
    const state: BootState = .{ .current = 5, .last_good = 4, .attempts = 1 };
    try testing.expectEqualDeep(
        ExitDecision{ .relaunch = launchOf(0, .rescue, state) },
        onBeamExit(state, default_policy, .{ .safe = true }, null),
    );
}

test "recovery: a crash loop walks provisional -> last_good -> rescue" {
    try milestone.require(1);
    const policy: Policy = .{ .max_attempts = 2 };
    var state: BootState = .{ .current = 7, .last_good = 6, .attempts = 0 };
    const expected = [_]Launch{
        .{ .generation = 7, .mode = .normal },
        .{ .generation = 7, .mode = .normal },
        .{ .generation = 6, .mode = .normal },
        .{ .generation = 6, .mode = .normal },
        .{ .generation = 0, .mode = .rescue },
        .{ .generation = 0, .mode = .rescue },
    };
    var p = planLaunch(state, policy, .{});
    for (expected, 0..) |want, i| {
        if (!std.meta.eql(want, p.launch)) {
            std.debug.print("crash loop step {d}: expected {any}, got {any}\n", .{ i, want, p.launch });
            return error.TestExpectedEqual;
        }
        state = p.next_state;
        p = switch (onBeamExit(state, policy, .{}, null)) {
            .relaunch => |next| next,
            .shutdown => return error.TestUnexpectedResult,
        };
    }
    try testing.expectEqualDeep(BootState{ .current = 6, .last_good = 6, .attempts = 2 }, state);
}

test "recovery: helper requests change neither boot state nor shutdown" {
    try milestone.require(17);
    const state: BootState = .{ .current = 5, .last_good = 4, .attempts = 2 };
    try testing.expectEqualDeep(Outcome{ .state = state }, applyMessage(state, try protocol.parse("HELPER initdb")));
}
