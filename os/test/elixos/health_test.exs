defmodule Elixos.HealthTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :tmp_dir

  alias Elixos.{Candidate, Health}
  alias Elixos.Boot.{AutoCommit, Env}

  setup %{tmp_dir: tmp} do
    previous = for key <- [:priv_dir, :health_checks], into: %{}, do: {key, Application.fetch_env(:elixos, key)}
    Application.put_env(:elixos, :priv_dir, Path.join(tmp, "priv"))
    Application.delete_env(:elixos, :health_checks)
    on_exit(fn -> Enum.each(previous, fn {key, value} -> restore_env(key, value) end) end)
    :ok
  end

  test "health runs every check, including those after errors and exceptions" do
    caller = self()
    checks = [
      system_suite: fn -> send(caller, :system); {:error, :invalid_code} end,
      raising: fn -> raise "failed health" end,
      throwing: fn -> throw(:bad_health) end,
      invalid: fn -> true end,
      toolset_smoke: fn -> send(caller, :tools); {:error, :invalid_tool} end,
      last_check: fn -> send(caller, :last); :ok end
    ]
    assert {:error, failures} = Health.run(checks)
    assert failures[:system_suite] == :invalid_code
    assert {:exception, "failed health"} = failures[:raising]
    assert {:throw, :bad_health} = failures[:throwing]
    assert {:invalid_result, true} = failures[:invalid]
    assert failures[:toolset_smoke] == :invalid_tool
    assert_received :system
    assert_received :tools
    assert_received :last
    assert File.regular?(Path.join(Candidate.evidence_dir(0), "health.term"))
  end

  test "empty health checks fail closed and successful checks persist a result" do
    assert Health.run([]) == {:error, [checks: :empty]}
    assert :ok = Health.run(system_suite: fn -> :ok end, toolset_smoke: fn -> :ok end)
    assert %{result: :ok} =
             Candidate.evidence_dir(0) |> Path.join("health.term") |> File.read!() |> :erlang.binary_to_term()
  end

  test "later successful health does not erase earlier failure evidence" do
    assert {:error, [system_suite: :failed]} = Health.run(system_suite: fn -> {:error, :failed} end)
    assert :ok = Health.run(system_suite: fn -> :ok end)
    directory = Candidate.evidence_dir(0)
    receipts =
      directory
      |> File.ls!()
      |> Enum.filter(&(String.starts_with?(&1, "health-") and String.ends_with?(&1, ".term")))
      |> Enum.map(&(Path.join(directory, &1) |> File.read!() |> :erlang.binary_to_term()))
    assert Enum.any?(receipts, &match?(%{result: {:error, [system_suite: :failed]}}, &1))
    assert Enum.any?(receipts, &match?(%{result: :ok}, &1))
  end


  test "AutoCommit uses Health by default and does not COMMIT named failures" do
    test = self()
    Application.put_env(:elixos, :health_checks,
      system_suite: fn -> send(test, :checked); {:error, :suite_failed} end,
      toolset_smoke: fn -> :ok end
    )
    pid = start_supervised!({AutoCommit,
      env: env(), after_ms: 60_000,
      commit: fn generation -> send(test, {:commit, generation}); :ok end})
    send(pid, :check)
    assert_receive :checked
    assert Process.alive?(pid)
    refute_receive {:commit, _}, 20
    # AutoCommit records after the check returns; the 20 ms refute window is
    # not a write deadline, so wait for the durable receipt itself.
    path = Candidate.evidence_dir(0) |> Path.join("health.term")
    assert Enum.any?(1..100, fn _ -> File.regular?(path) or (Process.sleep(20) && false) end)
    assert %{result: {:error, [system_suite: :suite_failed]}} =
             path |> File.read!() |> :erlang.binary_to_term()
  end

  test "health error tuples are not truthy promotion permission" do
    test = self()
    pid = start_supervised!({AutoCommit,
      env: env(), after_ms: 60_000,
      healthy?: fn -> send(test, :checked); {:error, [system_suite: :failed]} end,
      commit: fn generation -> send(test, {:commit, generation}); :ok end})
    send(pid, :check)
    assert_receive :checked
    assert Process.alive?(pid)
    refute_receive {:commit, _}, 20
  end

  test "successful health makes one control-write attempt and retains any failure" do
    test = self()
    pid = start_supervised!({AutoCommit,
      env: env(), after_ms: 60_000, healthy?: fn -> :ok end,
      commit: fn generation -> send(test, {:attempt, generation}); {:error, :epipe} end})
    monitor = Process.monitor(pid)
    send(pid, :check)
    assert_receive {:attempt, 7}
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
    refute_receive {:attempt, _}, 20
    assert %{result: {:error, :epipe}} =
             Candidate.evidence_dir(7) |> Path.join("auto_commit.term") |> File.read!() |> :erlang.binary_to_term()
  end

  defp env, do: %Env{generation: 7, mode: :normal, attempt: 1, ctl_fd: 3}
  defp restore_env(key, {:ok, value}), do: Application.put_env(:elixos, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:elixos, key)
end
