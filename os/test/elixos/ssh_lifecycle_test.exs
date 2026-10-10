defmodule Elixos.SSHLifecycleTest do
  @moduledoc "M12: stopping the Elixos owner closes SSH without force-killing OTP's daemon."
  use ExUnit.Case, async: false

  @moduletag milestone: 12

  setup do
    dir =
      Path.join(System.tmp_dir!(), "elixos-ssh-lifecycle-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "supervisor shutdown stops the daemon normally and closes its listener", ctx do
    system = Path.join(ctx.dir, "system")
    opts = [port: 0, system_dir: system, user_dir: Path.join(ctx.dir, "home/.ssh")]

    owner =
      start_supervised!(%{
        id: __MODULE__,
        start: {Supervisor, :start_link, [[{Elixos.SSH, opts}], [strategy: :one_for_one]]},
        type: :supervisor,
        restart: :temporary
      })

    {daemon, port} = daemon_at!(system)

    on_exit(fn ->
      if Process.alive?(daemon), do: :ssh.stop_daemon(daemon)
    end)

    monitor = Process.monitor(daemon)

    assert {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 3_000)
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert {:ok, "SSH-2.0-" <> _banner} = :gen_tcp.recv(socket, 0, 3_000)

    :ok = Supervisor.stop(owner)

    assert_receive {:DOWN, ^monitor, :process, ^daemon, :normal}, 3_000

    assert {:error, :closed} =
             read_until_closed(socket, System.monotonic_time(:millisecond) + 3_000)

    assert {:error, :econnrefused} =
             :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 3_000)
  end

  defp read_until_closed(socket, deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, _data} -> read_until_closed(socket, deadline)
      {:error, reason} -> {:error, reason}
    end
  end

  defp daemon_at!(system) do
    Supervisor.which_children(:sshd_sup)
    |> Enum.find_value(fn {_id, pid, _type, _modules} ->
      case :ssh.daemon_info(pid) do
        {:ok, info} ->
          if get_in(info, [:options, :system_dir]) == to_charlist(system) do
            {pid, Keyword.fetch!(info, :port)}
          end

        {:error, :bad_daemon_ref} ->
          nil
      end
    end)
    |> then(fn
      nil -> flunk("SSH daemon was not listening for #{system}")
      daemon -> daemon
    end)
  end
end
