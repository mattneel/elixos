defmodule Elixos.Integration.M12SSHTest do
  @moduledoc "M12: SSH logs the single user straight into their REPL, key auth only."
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 12
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  setup %{tmp_dir: tmp_dir} do
    {:ok, _} = Application.ensure_all_started(:ssh)

    keys = Path.join(tmp_dir, "client")
    File.mkdir_p!(keys)

    {_, 0} =
      System.cmd("ssh-keygen", [
        "-q",
        "-t",
        "ed25519",
        "-N",
        "",
        "-f",
        Path.join(keys, "id_ed25519")
      ])

    home = Path.join(tmp_dir, "home")
    File.mkdir_p!(Path.join(home, ".ssh"))
    File.cp!(Path.join(keys, "id_ed25519.pub"), Path.join(home, ".ssh/authorized_keys"))

    disk = Disk.fresh!(tmp_dir)
    Disk.put_tree!(disk, home, "/home")

    %{disk: disk, keys: keys, port: 20_000 + :rand.uniform(20_000)}
  end

  defp connect(port, opts) do
    base = [silently_accept_hosts: true, user_interaction: false, save_accepted_host: false]
    :ssh.connect(~c"127.0.0.1", port, base ++ opts, 30_000)
  end

  defp read_until(conn, channel, pattern, acc \\ "") do
    if acc =~ pattern do
      acc
    else
      receive do
        {:ssh_cm, ^conn, {:data, ^channel, _, data}} ->
          read_until(conn, channel, pattern, acc <> data)
      after
        30_000 -> flunk("ssh: timed out waiting for #{inspect(pattern)}, got: #{inspect(acc)}")
      end
    end
  end

  test "public-key login lands in the user's IEx, on the same VM", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: ctx.disk, ssh_port: ctx.port, append: ["ip=dhcp"])
    {_, vm} = QEMU.iex(vm, "Agent.start(fn -> :from_console end, name: :shared)")

    {:ok, conn} =
      connect(ctx.port,
        user: ~c"elixos",
        user_dir: String.to_charlist(ctx.keys),
        auth_methods: ~c"publickey"
      )

    {:ok, channel} = :ssh_connection.session_channel(conn, 30_000)
    :ok = :ssh_connection.shell(conn, channel)
    read_until(conn, channel, ~r/iex\(\d+\)> /)

    :ok = :ssh_connection.send(conn, channel, "Agent.get(:shared, & &1)\n")
    assert read_until(conn, channel, ~r/:from_console/) =~ ":from_console"

    :ssh.close(conn)
    QEMU.stop(vm)
  end

  test "password logins are refused", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: ctx.disk, ssh_port: ctx.port, append: ["ip=dhcp"])

    assert {:error, _} =
             connect(ctx.port, user: ~c"elixos", password: ~c"elixos", auth_methods: ~c"password")

    QEMU.stop(vm)
  end
end
