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

future = for m <- (milestone + 1)..20//1, do: {:milestone, m}

# QEMU tests boot real images and are slow; `make test-qemu` sets ELIXOS_QEMU=1
# and runs only test/integration. Never use `--include qemu`: an include filter
# would also re-include future milestones.
exclude = if System.get_env("ELIXOS_QEMU") == "1", do: future, else: [:qemu | future]

ExUnit.configure(exclude: exclude)
ExUnit.start()
