# Milestone gating (docs/TESTING.md §Milestones).
#
# Every test module declares `@moduletag milestone: N` (test/meta_test.exs
# enforces it). Tests above the current milestone are excluded, so `make test`
# stays green while the whole roadmap already exists as tests. To start a
# milestone, bump the MILESTONE file at the repo root and watch its tests go red.
milestone =
  case System.get_env("ELIXOS_MILESTONE") do
    nil ->
      Elixos.Test.Paths.repo_root()
      |> Path.join("MILESTONE")
      |> File.read!()
      |> String.trim()
      |> String.to_integer()

    value ->
      String.to_integer(value)
  end

# Every milestone above the current one, with room to spare: the roadmap runs
# to M27 today, and a bound that tracks it has had to be raised twice already.
future = for m <- (milestone + 1)..99//1, do: {:milestone, m}

# QEMU tests boot real images and are slow; `make test-qemu` sets ELIXOS_QEMU=1
# and runs only test/integration. Never use `--include qemu`: an include filter
# would also re-include future milestones.
#
# The aarch64 smoke set runs under TCG emulation (slow) and needs the aarch64
# image built, so `make test-qemu-aarch64` sets ELIXOS_QEMU_AARCH64=1 for it -
# and a normal x86_64 run never picks it up.
arch_excludes = if System.get_env("ELIXOS_QEMU_AARCH64") == "1", do: [], else: [:aarch64]

# M21-M24 (the agent arc: the OMP toolset, the coding agent, self-modification
# and the native hot paths) are deferred until the human's own agent work
# lands. Their tests stay in the suite as that arc's specification, tagged
# `:deferred`; ADR-063 records the decision.
deferred = [:deferred]

exclude =
  if System.get_env("ELIXOS_QEMU") == "1",
    do: deferred ++ future ++ arch_excludes,
    else: [:qemu | deferred ++ future]

ExUnit.configure(exclude: exclude)
ExUnit.start()
