defmodule Elixos.Boot.AutoCommitTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 5

  alias Elixos.Boot.{AutoCommit, Env}

  defp env(mode), do: %Env{generation: 5, mode: mode, attempt: 1, ctl_fd: 3}

  defp opts(overrides) do
    test = self()

    Keyword.merge(
      [
        env: env(:normal),
        after_ms: 20,
        healthy?: fn -> true end,
        commit: &send(test, {:commit, &1})
      ],
      overrides
    )
  end

  test "commits the running generation once it has been healthy for after_ms" do
    {:ok, pid} = AutoCommit.start_link(opts([]))
    ref = Process.monitor(pid)
    refute_received {:commit, _}
    assert_receive {:commit, 5}, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    refute_receive {:commit, _}, 100
  end

  test "rescue mode never commits" do
    assert AutoCommit.start_link(opts(env: env(:rescue))) == :ignore
    refute_receive {:commit, _}, 100
  end

  test "an unhealthy system is re-checked every after_ms until it is healthy" do
    {:ok, checks} = Agent.start_link(fn -> 0 end)

    healthy? = fn ->
      Agent.get_and_update(checks, fn n -> {n >= 2, n + 1} end)
    end

    {:ok, _pid} = AutoCommit.start_link(opts(healthy?: healthy?))
    assert_receive {:commit, 5}, 1_000
    assert Agent.get(checks, & &1) == 3
  end

  test "does not commit before after_ms has elapsed" do
    {:ok, _pid} = AutoCommit.start_link(opts(after_ms: 300))
    refute_receive {:commit, _}, 150
    assert_receive {:commit, 5}, 1_000
  end
end
