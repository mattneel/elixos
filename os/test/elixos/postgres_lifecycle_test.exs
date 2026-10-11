defmodule Elixos.PostgresLifecycleTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 18

  alias Elixos.{Postgres, Privileges}
  alias Elixos.Shim.Control

  defmodule ReplySource do
    def open(owner) do
      send(owner, {:reply_reader, self()})
      {:ok, owner}
    end

    def read(_owner) do
      receive do
        {:line, line} -> {:ok, line}
      end
    end

    def close(_owner), do: :ok
  end

  setup do
    control =
      start_supervised!(
        {Control, name: nil, sink: {Elixos.Test.ProcessSink, self()}, heartbeat_ms: 20}
      )

    assert_receive {:shim_write, "HB\n"}

    privileges =
      start_supervised!({Privileges, name: nil, control: control, source: {ReplySource, self()}})

    assert_receive {:reply_reader, reader}
    {:ok, control: control, privileges: privileges, reader: reader}
  end

  # Synchronize with query admission, rather than depending on task scheduling
  # or sleeping. The production timeout message is then delivered deterministically.
  defp admitted(server, attempts \\ 1_000)
  defp admitted(_server, 0), do: flunk("query did not wait for startup")

  defp admitted(server, attempts) do
    case :sys.get_state(server) do
      %{waiters: [_ | _]} = state -> state
      _ -> admitted(server, attempts - 1)
    end
  end

  test "rescue neither starts helpers nor waits for SQL", ctx do
    start_supervised!({Postgres, mode: :rescue, privileges: ctx.privileges})

    assert Postgres.status() == {:error, :not_running}
    assert Postgres.query("select 42") == {:error, :not_running}
    refute_received {:shim_write, "HELPER postgres-init\n"}
    refute_received {:shim_write, "HELPER postgres\n"}
    assert :ok = Control.commit(ctx.control, 18)
    assert_receive {:shim_write, "COMMIT 18\n"}
  end

  test "a live initialization process cannot become a ready postmaster and startup expiry releases queries",
       ctx do
    server = start_supervised!({Postgres, mode: :normal, privileges: ctx.privileges})
    assert_receive {:shim_write, "HELPER postgres-init\n"}

    # A real, still-live UNIX process keeps initialization pending. The helper
    # reply only acknowledges a fork; it must not be mistaken for SQL readiness.
    send(ctx.reader, {:line, "HELPER postgres-init OK #{System.pid()}\n"})
    query = Task.async(fn -> Postgres.query("create table never_replayed (id integer)") end)
    %{worker: {worker, _monitor}} = admitted(server)
    worker_monitor = Process.monitor(worker)

    assert Postgres.status() == {:error, :not_running}
    assert :ok = Control.commit(ctx.control, 18)
    assert_receive {:shim_write, "COMMIT 18\n"}
    assert_receive {:shim_write, "HB\n"}, 200
    refute_received {:shim_write, "HELPER postgres\n"}

    send(server, {:startup_timeout, worker})
    assert Task.await(query) == {:error, {:startup_failed, :timeout}}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}
    assert Postgres.status() == {:error, :not_running}
    assert Postgres.query("select 1") == {:error, {:startup_failed, :timeout}}
    refute_received {:shim_write, "HELPER postgres\n"}

    # A stale completion cannot undo a failure or replay initialization.
    send(server, {:startup_result, worker, {:error, :late}})
    assert Postgres.query("select 2") == {:error, {:startup_failed, :timeout}}
    refute_received {:shim_write, "HELPER postgres-init\n"}
    assert :ok = Control.commit(ctx.control, 19)
    assert_receive {:shim_write, "COMMIT 19\n"}
  end

  test "a refused initialization is a stable service error, not a supervisor failure or retry",
       ctx do
    server = start_supervised!({Postgres, mode: :normal, privileges: ctx.privileges})
    assert_receive {:shim_write, "HELPER postgres-init\n"}
    query = Task.async(fn -> Postgres.query("insert into must_not_run values (1)") end)
    admitted(server)

    send(ctx.reader, {:line, "HELPER postgres-init REFUSED\n"})
    error = {:error, {:startup_failed, {:helper, "postgres-init", :refused}}}
    assert Task.await(query) == error
    assert Postgres.query("select 1") == error
    assert Postgres.status() == {:error, :not_running}
    refute_received {:shim_write, "HELPER postgres\n"}
    refute_received {:shim_write, "HELPER postgres-init\n"}
    assert :ok = Control.commit(ctx.control, 18)
    assert_receive {:shim_write, "COMMIT 18\n"}
  end
end
