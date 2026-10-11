defmodule Elixos.PrivilegesClientTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 17

  alias Elixos.Privileges
  alias Elixos.Shim.Control

  defmodule ReplySource do
    def open(owner) do
      send(owner, {:reply_reader, self()})
      {:ok, owner}
    end

    def read(_owner) do
      receive do
        {:line, line} -> {:ok, line}
        :eof -> :eof
      end
    end

    def close(_owner), do: :ok
  end

  defmodule PipeReplySource do
    def open(path), do: File.open(path, [:read, :raw, :binary])
    defdelegate read(source), to: Elixos.Privileges.ReplyFd
    defdelegate close(source), to: Elixos.Privileges.ReplyFd
  end

  @tag :tmp_dir
  test "a short reply on a real live pipe completes without waiting for EOF", %{tmp_dir: dir} do
    path = Path.join(dir, "reply.pipe")
    assert {_, 0} = System.cmd("mkfifo", [path])
    owner = self()

    writer =
      Task.async(fn ->
        {:ok, fd} = File.open(path, [:write, :raw, :binary])
        send(owner, {:pipe_writer, self()})

        receive do
          {:reply, bytes} -> :ok = IO.binwrite(fd, bytes)
        end

        receive do
          :close -> File.close(fd)
        end
      end)

    on_exit(fn -> send(writer.pid, :close) end)

    control =
      start_supervised!(
        {Control, name: nil, sink: {Elixos.Test.ProcessSink, self()}, heartbeat_ms: 60_000}
      )

    client =
      start_supervised!(
        {Privileges, name: nil, control: control, source: {PipeReplySource, path}}
      )

    assert_receive {:pipe_writer, pid}
    request = Task.async(fn -> Privileges.request(client, "short") end)
    assert_receive {:shim_write, "HELPER short\n"}
    send(pid, {:reply, "HELPER short REFUSED\n"})
    assert Task.await(request) == {:error, :refused}
    assert Process.alive?(writer.pid)
    send(writer.pid, :close)
    Task.await(writer)
  end

  defp start_client do
    control =
      start_supervised!(
        {Control, name: nil, sink: {Elixos.Test.ProcessSink, self()}, heartbeat_ms: 20}
      )

    assert_receive {:shim_write, "HB\n"}

    client =
      start_supervised!(
        {Privileges,
         name: nil, control: control, source: {ReplySource, self()}, timeout_ms: 60_000}
      )

    assert_receive {:reply_reader, reader}
    {client, control, reader}
  end

  # Synchronize with the call's actual arrival, without sleeps or relying on
  # task scheduling. The internal timer is injected only after admission.
  defp pending(client, count, attempts \\ 1_000)
  defp pending(_client, _count, 0), do: flunk("helper calls were not admitted")

  defp pending(client, count, attempts) do
    state = :sys.get_state(client)

    if map_size(state.pending) == count do
      state
    else
      pending(client, count, attempts - 1)
    end
  end

  test "waiting for a helper leaves heartbeats responsive and preserves request order" do
    {client, control, reader} = start_client()
    first = Task.async(fn -> Privileges.request(client, "initdb") end)
    assert_receive {:shim_write, "HELPER initdb\n"}
    second = Task.async(fn -> Privileges.request(client, "postgres") end)
    pending(client, 2)

    assert_receive {:shim_write, "HB\n"}, 200
    assert :ok = Control.commit(control, 7)
    assert_receive {:shim_write, "COMMIT 7\n"}
    refute_received {:shim_write, "HELPER postgres\n"}

    send(reader, {:line, "HELPER initdb OK 42\n"})
    assert Task.await(first) == {:ok, 42}
    assert_receive {:shim_write, "HELPER postgres\n"}
    send(reader, {:line, "HELPER postgres REFUSED\n"})
    assert Task.await(second) == {:error, :refused}
  end

  test "a late same-name reply is drained before the next request is written" do
    {client, _control, reader} = start_client()
    first = Task.async(fn -> Privileges.request(client, "initdb") end)
    assert_receive {:shim_write, "HELPER initdb\n"}
    first_ref = :sys.get_state(client).active
    second = Task.async(fn -> Privileges.request(client, "initdb") end)
    pending(client, 2)

    send(client, {:expire, first_ref})
    assert Task.await(first) == {:error, :timeout}
    assert :sys.get_state(client).pending[first_ref].from == nil
    refute_received {:shim_write, "HELPER initdb\n"}

    send(reader, {:line, "HELPER initdb OK 11\n"})
    assert_receive {:shim_write, "HELPER initdb\n"}
    # A stale timer cannot expire the new same-name request.
    send(client, {:expire, first_ref})
    send(reader, {:line, "HELPER initdb OK 22\n"})
    assert Task.await(second) == {:ok, 22}
    assert :sys.get_state(client).pending == %{}
    refute_received {:shim_write, "HELPER initdb\n"}
  end

  test "a queued timeout never executes and does not steal another helper's reply" do
    {client, _control, reader} = start_client()
    first = Task.async(fn -> Privileges.request(client, "initdb") end)
    assert_receive {:shim_write, "HELPER initdb\n"}
    second = Task.async(fn -> Privileges.request(client, "expired") end)
    state = pending(client, 2)
    queued_ref = Enum.find(Map.keys(state.pending), &(&1 != state.active))

    send(client, {:expire, queued_ref})
    assert Task.await(second) == {:error, :timeout}
    send(reader, {:line, "HELPER initdb OK 33\n"})
    assert Task.await(first) == {:ok, 33}
    assert :sys.get_state(client).pending == %{}
    refute_received {:shim_write, "HELPER expired\n"}

    third = Task.async(fn -> Privileges.request(client, "postgres") end)
    assert_receive {:shim_write, "HELPER postgres\n"}
    send(reader, {:line, "HELPER postgres OK 44\n"})
    assert Task.await(third) == {:ok, 44}
  end

  test "fragmented pipe reads preserve exact reply bytes rather than normalizing CRLF" do
    {client, _control, reader} = start_client()
    first = Task.async(fn -> Privileges.request(client, "initdb") end)
    assert_receive {:shim_write, "HELPER initdb\n"}
    send(reader, {:line, "HELPER ini"})
    send(reader, {:line, "tdb OK 66"})
    send(reader, {:line, "\n"})
    assert Task.await(first) == {:ok, 66}

    second = Task.async(fn -> Privileges.request(client, "postgres") end)
    assert_receive {:shim_write, "HELPER postgres\n"}
    send(reader, {:line, "HELPER postgres OK 77\r\n"})
    assert Task.await(second) == {:error, {:reply_pipe, :invalid_reply}}
    refute_received {:shim_write, "HELPER postgres\n"}
  end

  test "a mismatched reply fails pending requests without replaying or reopening the pipe" do
    {client, _control, reader} = start_client()
    first = Task.async(fn -> Privileges.request(client, "initdb") end)
    assert_receive {:shim_write, "HELPER initdb\n"}
    second = Task.async(fn -> Privileges.request(client, "postgres") end)
    pending(client, 2)

    send(reader, {:line, "HELPER other OK 55\n"})
    assert Task.await(first) == {:error, {:reply_pipe, :unexpected_helper}}
    assert Task.await(second) == {:error, {:reply_pipe, :unexpected_helper}}
    assert Privileges.request(client, "initdb") == {:error, {:reply_pipe, :unexpected_helper}}
    assert Privileges.request(client, "BAD") == {:error, :invalid_name}
    refute_received {:shim_write, "HELPER postgres\n"}
    refute_received {:shim_write, "HELPER initdb\n"}
    refute_received {:reply_reader, _}
  end
end
