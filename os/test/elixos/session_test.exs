defmodule Elixos.SessionTest do
  @moduledoc """
  Session working directories (ADR-020, M9). A "session" here is what it is on
  the box: a process with its own group leader, which everything spawned from
  it inherits.
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 9

  alias Elixos.Session

  defp leader, do: spawn_link(fn -> Process.sleep(:infinity) end)

  # Runs `fun` in a process whose group leader is `leader` (the session) and
  # returns what it answered.
  defp in_session(leader, fun) do
    parent = self()
    ref = make_ref()

    spawn_link(fn ->
      Process.group_leader(self(), leader)
      send(parent, {ref, fun.()})
    end)

    receive do
      {^ref, result} -> result
    after
      5_000 -> flunk("the session did not answer")
    end
  end

  test "a session starts in /priv/home and the VM's directory never moves" do
    vm_dir = File.cwd!()
    one = leader()

    assert in_session(one, fn -> Session.cwd() end) == "/priv/home"
    assert in_session(one, fn -> Session.cd("/tmp") end) == {:ok, "/tmp"}
    assert in_session(one, fn -> Session.cwd() end) == "/tmp"

    # The whole point (ADR-016): the VM's working directory is untouched.
    assert File.cwd!() == vm_dir
  end

  test "two sessions keep different directories" do
    a = leader()
    b = leader()

    assert in_session(a, fn -> Session.cd("/tmp") end) == {:ok, "/tmp"}

    assert in_session(a, fn -> Session.cwd() end) == "/tmp"
    assert in_session(b, fn -> Session.cwd() end) == "/priv/home"
    assert in_session(a, fn -> Session.cwd() end) == "/tmp"
  end

  test "a process spawned from a session inherits its directory" do
    parent_session = leader()

    assert in_session(parent_session, fn -> Session.cd("/tmp") end) == {:ok, "/tmp"}

    inherited =
      in_session(parent_session, fn ->
        # A task is a process; it inherits the group leader, so it inherits the
        # session's directory (which is what makes System.cmd(cd: ...) work).
        Task.async(fn -> Session.cwd() end) |> Task.await()
      end)

    assert inherited == "/tmp"
  end

  test "relative paths expand against the session's directory" do
    one = leader()

    assert in_session(one, fn -> Session.cd("/tmp") end) == {:ok, "/tmp"}
    assert in_session(one, fn -> Session.expand("x/y") end) == "/tmp/x/y"
    assert in_session(one, fn -> Session.expand("../z") end) == "/z"
    assert in_session(one, fn -> Session.expand("/absolute") end) == "/absolute"
    assert in_session(one, fn -> Session.expand("~") end) == "/priv/home"
  end

  test "cd to something that is not a directory changes nothing" do
    one = leader()

    assert in_session(one, fn -> Session.cd("/tmp") end) == {:ok, "/tmp"}
    assert in_session(one, fn -> Session.cd("/no/such/place") end) == {:error, :enoent}
    assert in_session(one, fn -> Session.cd("/etc/hostname") end) == {:error, :enotdir}
    assert in_session(one, fn -> Session.cwd() end) == "/tmp"
  end

  test "cwd_for/1 reports another session's directory" do
    one = leader()

    assert in_session(one, fn -> Session.cd("/tmp") end) == {:ok, "/tmp"}
    assert Session.cwd_for(one) == "/tmp"
    assert Session.cwd_for(leader()) == Session.default()
  end
end
