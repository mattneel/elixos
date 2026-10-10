//! Milestone gating for shim tests (docs/TESTING.md §Milestones).
//!
//! Every test starts with `try milestone.require(N);`. Until the MILESTONE file
//! reaches N the test is reported as skipped, so `make test` stays green while
//! the roadmap's future tests already exist in the tree.
const build_options = @import("build_options");

pub const current: u32 = build_options.milestone;

pub fn require(n: u32) error{SkipZigTest}!void {
    if (current < n) return error.SkipZigTest;
}
