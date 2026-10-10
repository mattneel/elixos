defmodule Elixos.SSH do
  @moduledoc """
  Remote login straight into the user's REPL (M12).

  OTP's `ssh` daemon takes a shell fun receiving the authenticated user and
  peer address and returning the shell's pid, so a per-user REPL is a lookup
  in `Elixos.User` followed by `Elixos.REPL.mfa/1`. Single user (ADR-013):
  public-key auth against `/priv/home/.ssh/authorized_keys`, no passwords
  (the daemon is left without a password checker, so password attempts are
  refused). The same keys ADR-012 asks of every login: no shell, just a REPL.

  Host keys are generated on first boot and kept in `/priv/ssh/`: one
  ed25519 key in the PEM form `:ssh_file` reads, so the machine's identity
  survives power cycles (PROTOCOL.md §7).

  Options (mainly for tests): `:port` (default 22), `:system_dir` (default
  `<priv>/ssh`), `:user_dir` (default `<priv>/home/.ssh`), `:shell`
  (default `&shell/2`).
  """

  require Logger

  # id-Ed25519: the named curve public_key and ssh_file both know.
  @id_ed25519 {1, 3, 101, 112}

  @doc "Supervisor-shaped start: boots the daemon, or steps aside."
  def start_link(opts) do
    case start(opts) do
      {:ok, daemon} ->
        {:ok, daemon}

      {:error, reason} ->
        # SSH is not boot-critical: a box with no network, or a rescue boot,
        # still must reach a prompt. The failure is on the console.
        Logger.error("ssh: daemon not started: #{inspect(reason)}")
        :ignore
    end
  end

  @doc "A child that does not come back from the dead: the daemon is its own."
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts \\ []) do
    # ssh refuses to start when user_dir is missing, but authorized_keys is
    # read when a client authenticates, so the machine owner may drop a key
    # in long after boot: only the directory has to be there.
    with {:ok, _apps} <- Application.ensure_all_started(:ssh),
         :ok <- File.mkdir_p(user_dir(opts)),
         {:ok, _path} <- host_key(system_dir(opts)),
         {:ok, daemon} <- :ssh.daemon(port(opts), daemon_options(opts)) do
      {:ok, daemon}
    end
  end

  @doc """
  The shell fun the daemon calls once a key has authenticated (OTP's
  contract: return the pid of the shell). Single user: the key *is* the
  identity, so this is the same REPL the console gets.
  """
  @spec shell(String.t(), :inet.ip_address()) :: pid()
  def shell(user, peer) do
    Logger.info("ssh: #{user} from #{peer_address(peer)}")

    with {:ok, _apps} <- Application.ensure_all_started(:iex),
         {:ok, {module, function, arguments}} <- Elixos.Boot.Login.login_repl() do
      apply(module, function, arguments)
    else
      error -> exit({:login_failed, error})
    end
  end

  @doc """
  The host key, generated on first use and kept: identity across boots.
  """
  @spec host_key(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def host_key(dir) do
    path = Path.join(dir, "ssh_host_ed25519_key")

    if File.regular?(path) do
      {:ok, path}
    else
      generate_host_key(path)
    end
  end

  defp generate_host_key(path) do
    key = new_host_key()
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, key)])

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path <> ".tmp", pem),
         :ok <- File.rename(path <> ".tmp", path) do
      # The public half, spelled the way a known_hosts or authorized_keys
      # line spells it, so a human can read the machine's fingerprint.
      File.write(path <> ".pub", public_line(key))
      {:ok, path}
    end
  end

  defp new_host_key do
    # generate_key returns {public, private}, and for EdDSA the private key is
    # the 32-byte seed: the form ssh_file hands back and ssh signs with.
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    {:ECPrivateKey, 1, private, {:namedCurve, @id_ed25519}, public, :asn1_NOVALUE}
  end

  defp public_line(key) do
    "ssh-ed25519 #{Base.encode64(:ssh_message.ssh2_pubkey_encode(key))} elixos\n"
  end

  # ssh_cli hands the shell fun {Address, Port} (ssh_connection_handler's
  # peer), not a bare address.
  defp peer_address({address, port}) when is_tuple(address) or is_list(address) do
    "#{:inet.ntoa(address)}:#{port}"
  end

  defp peer_address(other), do: inspect(other)

  defp daemon_options(opts) do
    [
      system_dir: to_charlist(system_dir(opts)),
      user_dir: to_charlist(user_dir(opts)),
      # No password checker is configured, so only keys authenticate; saying
      # so here keeps a future option from opening the door quietly.
      auth_methods: ~c"publickey",
      shell: Keyword.get(opts, :shell, &__MODULE__.shell/2)
    ]
  end

  defp port(opts), do: Keyword.get(opts, :port, 22)

  defp system_dir(opts) do
    Keyword.get(opts, :system_dir, Path.join(priv(), "ssh"))
  end

  defp user_dir(opts) do
    Keyword.get(opts, :user_dir, Path.join(priv(), "home/.ssh"))
  end

  defp priv, do: Application.get_env(:elixos, :priv_dir, "/priv")
end
