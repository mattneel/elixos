defmodule Elixos.SSHTest do
  @moduledoc "M12: the SSH daemon is key-only, and its shell is this VM's REPL."
  use ExUnit.Case, async: false

  @moduletag milestone: 12

  alias Elixos.SSH

  setup do
    dir = Path.join(System.tmp_dir!(), "elixos-ssh-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  # One key pair per directory: a client given a directory finds exactly the
  # one id_ed25519 in it, nothing else.
  defp keypair!(dir, name) do
    key_dir = Path.join(dir, name)
    File.mkdir_p!(key_dir)
    path = Path.join(key_dir, "id_ed25519")
    {_, 0} = System.cmd("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", path])
    {key_dir, File.read!(path <> ".pub")}
  end

  test "the host key is generated once, and it is the key ssh_file reads", ctx do
    system = Path.join(ctx.dir, "system")

    assert {:ok, path} = SSH.host_key(system)
    assert {:ok, key} = :ssh_file.host_key(:"ssh-ed25519", system_dir: to_charlist(system))
    assert {:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 112}}, _pub, _} = key

    # The .pub line is the same key, spelled the way authorized_keys is.
    ["ssh-ed25519", blob | _] = path |> then(&(&1 <> ".pub")) |> File.read!() |> String.split()
    # Derived from the *private* key file, so a wrong .pub would not pass.
    assert {{:ECPoint, point}, {:namedCurve, {1, 3, 101, 112}}} =
             :ssh_file.extract_public_key(key)

    # RFC 4253: both parts are length-prefixed strings.
    assert Base.decode64!(blob) ==
             <<11::32, "ssh-ed25519", byte_size(point)::32, point::binary>>

    # Second call keeps the machine's identity.
    written = File.read!(path)
    assert {:ok, ^path} = SSH.host_key(system)
    assert File.read!(path) == written
  end

  test "a key in authorized_keys logs in, and the shell fun runs on this VM", ctx do
    system = Path.join(ctx.dir, "system")
    user_dir = Path.join(ctx.dir, "home/.ssh")
    File.mkdir_p!(user_dir)
    {client_dir, pub} = keypair!(ctx.dir, "id_ed25519")
    File.write!(Path.join(user_dir, "authorized_keys"), pub)

    me = self()
    port = 20_000 + :rand.uniform(20_000)

    shell = fn _user, _peer ->
      spawn(fn ->
        send(me, {:shell, self()})
        IO.puts("elixos ssh shell")
        Process.sleep(:infinity)
      end)
    end

    assert {:ok, daemon} =
             SSH.start(port: port, system_dir: system, user_dir: user_dir, shell: shell)

    on_exit(fn -> :ssh.stop_daemon(daemon) end)

    assert {:ok, conn} = connect(port, client_dir, ~c"publickey")
    {:ok, channel} = :ssh_connection.session_channel(conn, 30_000)
    :ok = :ssh_connection.shell(conn, channel)

    assert_receive {:shell, _pid}, 30_000

    assert_receive {:ssh_cm, ^conn, {:data, ^channel, _, data}}, 30_000
    assert data =~ "elixos ssh shell"
    :ssh.close(conn)
  end

  test "a pristine disk still gets a daemon: the user's .ssh need not exist yet", ctx do
    # The machine owner may drop the key in later (the demo does exactly
    # that); ssh_file reads authorized_keys at authentication time, so the
    # directory only has to exist when the daemon starts.
    system = Path.join(ctx.dir, "system")
    user_dir = Path.join(ctx.dir, "home/.ssh")
    port = 20_000 + :rand.uniform(20_000)

    assert {:ok, daemon} = SSH.start(port: port, system_dir: system, user_dir: user_dir)
    on_exit(fn -> :ssh.stop_daemon(daemon) end)

    {key_dir, pub} = keypair!(ctx.dir, "id_ed25519")
    File.mkdir_p!(user_dir)
    File.write!(Path.join(user_dir, "authorized_keys"), pub)

    # The key written after the daemon started logs in.
    assert {:ok, conn} = connect(port, key_dir, ~c"publickey")
    :ssh.close(conn)
  end

  test "a key that is not in authorized_keys is refused", ctx do
    system = Path.join(ctx.dir, "system")
    user_dir = Path.join(ctx.dir, "home/.ssh")
    File.mkdir_p!(user_dir)
    {_, pub} = keypair!(ctx.dir, "id_ed25519")
    File.write!(Path.join(user_dir, "authorized_keys"), pub)

    {other_dir, _} = keypair!(ctx.dir, "other")
    port = 20_000 + :rand.uniform(20_000)

    assert {:ok, daemon} = SSH.start(port: port, system_dir: system, user_dir: user_dir)
    on_exit(fn -> :ssh.stop_daemon(daemon) end)

    assert {:error, _reason} = connect(port, other_dir, ~c"publickey")
  end

  defp connect(port, key_dir, methods) do
    :ssh.connect(
      ~c"127.0.0.1",
      port,
      [
        silently_accept_hosts: true,
        user_interaction: false,
        save_accepted_host: false,
        user: ~c"elixos",
        user_dir: to_charlist(key_dir),
        auth_methods: methods
      ],
      30_000
    )
  end
end
