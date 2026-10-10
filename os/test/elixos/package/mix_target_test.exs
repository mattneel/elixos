defmodule Elixos.Package.MixTargetTest do
  # ADR-010: Elixos is a Mix *target*, not an environment. The same app keeps
  # its dev/test/prod envs; MIX_TARGET=elixos layers config/elixos.exs on top,
  # adds `targets: :elixos` deps, and builds into _build/elixos_<env>.
  use ExUnit.Case, async: false

  @moduletag milestone: 10
  @moduletag timeout: 300_000

  @fixture Elixos.Test.Paths.fixture("sample_app")

  setup do
    on_exit(fn -> File.rm_rf!(Path.join(@fixture, "_build")) end)
  end

  defp where(target_env) do
    env = [{"MIX_ENV", "dev"}, {"MIX_TARGET", target_env}]
    eval = "IO.write(Application.fetch_env!(:sample_app, :where))"

    {output, status} =
      System.cmd("mix", ["run", "--no-start", "-e", eval],
        cd: @fixture,
        env: env,
        stderr_to_stdout: true
      )

    assert status == 0, output
    output |> String.split("\n") |> List.last()
  end

  test "host builds use config/config.exs only" do
    assert where(nil) == "host"
    assert File.dir?(Path.join(@fixture, "_build/dev"))
  end

  test "elixos builds layer config/elixos.exs and get their own build dir" do
    assert where("elixos") == "elixos"
    assert File.dir?(Path.join(@fixture, "_build/elixos_dev"))
  end

  test "the elixos API dependency only exists for the elixos target" do
    where("elixos")
    assert File.dir?(Path.join(@fixture, "_build/elixos_dev/lib/elixos"))

    where(nil)
    refute File.dir?(Path.join(@fixture, "_build/dev/lib/elixos"))
  end
end
