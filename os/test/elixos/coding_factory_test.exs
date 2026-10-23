defmodule Elixos.CodingFactoryTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :host_orchestration
  @moduletag :tmp_dir
  @moduletag timeout: 120_000

  @repo Elixos.Test.Paths.repo_root()
  @script Path.join(@repo, "scripts/stage-coding.exs")

  defp source do
    Path.expand(System.get_env("ELIXOS_OH_MY_JIDO_SOURCE") || "../oh_my_jido", @repo)
  end

  defp command(arguments) do
    System.cmd("elixir", [@script | arguments],
      env: [{"ELIXIR_ERL_OPTIONS", "+S 2:2 +A 2"}],
      stderr_to_stdout: true
    )
  end

  test "canonical licensed sources stage only under their exact explicit content pin", %{
    tmp_dir: tmp
  } do
    assert {pin, 0} = command(["pin", source()])
    pin = String.trim(pin)
    assert pin =~ ~r/\A[0-9a-f]{64}\z/
    destination = Path.join(tmp, "coding")
    assert {_output, 0} = command(["stage", source(), destination, pin])
    root = Path.join(destination, "oh_my_jido")
    receipt = Path.join(destination, "source.json") |> File.read!() |> :json.decode()
    assert receipt["source_sha256"] == pin
    assert receipt["excluded_backends"] == ["quickbeam", "snakepit", "snakebridge", "python"]

    for entry <- receipt["files"] do
      bytes = File.read!(Path.join(root, entry["path"]))
      assert byte_size(bytes) == entry["bytes"]
      assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == entry["sha256"]
    end

    for relative <- [
          "vendor/jido/LICENSE",
          "vendor/jido/UPSTREAM.json",
          "vendor/jido/lib/jido/agent_server/private_diagnostics.ex",
          "vendor/req_llm/LICENSE",
          "vendor/req_llm/UPSTREAM.json",
          "vendor/req_llm/lib/req_llm/streaming/failure.ex",
          "examples/elixos/guest/healthy.exs",
          "examples/elixos/guest/fallback.exs",
          "examples/elixos/guest/verify_healthy.exs",
          "examples/elixos/guest/verify_fallback.exs",
          "examples/elixos/priv/t10/project/lib/workload.ex"
        ] do
      assert File.read!(Path.join(root, relative)) == File.read!(Path.join(source(), relative))
    end

    refute File.exists?(Path.join(root, "_build"))
    refute File.exists?(Path.join(root, "deps"))
    refute File.exists?(Path.join(root, "examples/elixos/_build"))
    assert Path.wildcard(Path.join(root, "**/*.beam")) == []

    # These are disposable staged sources, never the canonical checkout.
    File.write!(Path.join(root, "lib/pin_change.ex"), "defmodule UnapprovedSourceChange do end\n")
    refused = Path.join(tmp, "refused")
    assert {output, status} = command(["stage", root, refused, pin])
    assert status != 0
    assert output =~ "coding source pin differs"
    refute File.exists?(refused)
  end

  test "new pure-BEAM production closure preserves exact canonical and existing OS lock identities" do
    # A mix.lock is a map literal with quoted-atom keys (`"jason": {...}`).
    os = lock(Path.join(@repo, "os/mix.lock"))
    canonical = lock(Path.join(source(), "mix.lock"))

    for app <-
          ~w(abnf_parsec boundary dotenvy ex_ast finch fsmx glob_ex idna jido_ai jsv llm_db mime nimble_pool req server_sent_events sourceror texture toml websockex yamerl yaml_elixir) do
      assert Map.fetch!(os, app) == Map.fetch!(canonical, app), app
    end

    for app <- ~w(quickbeam snakepit snakebridge), do: refute(Map.has_key?(os, app))
    assert {:hex, :emerge, "0.4.2", _, _, _, _, _} = os["emerge"]
    assert {:hex, :rustler_precompiled, "0.8.4", _, _, _, _, _} = os["rustler_precompiled"]
  end

  defp lock(path) do
    {entries, _} = Code.eval_file(path)
    Map.new(entries, fn {app, entry} -> {Atom.to_string(app), entry} end)
  end
end
