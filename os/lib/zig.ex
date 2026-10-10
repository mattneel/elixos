defmodule Zig do
  @moduledoc """
  The toolchain package's API: `zig cc` as the system compiler (ADR-009, M11).

  Programs are packages and commands are functions (ADR-019): the toolchain is
  not a CLI to shell out to, it is this module. A session calls `init/1` once
  to install and unpack it, then builds with it — always exec'ing `zig`
  directly, with `cd:` set to the caller's *session* directory (ADR-020) and
  never through a shell (ADR-012), which also leaves the VM's working directory
  alone (ADR-016).

      iex> Zig.init()
      :ok
      iex> Zig.build(["run"])
      {:ok, %{status: 0, output: "..."}}

  `build/2` runs `zig build` with the given arguments; `cc/2` runs `zig cc`
  with the given arguments, which is how NIFs compile (ADR-009).
  """

  @doc """
  Installs the toolchain if needed (`ZIG_GLOBAL_CACHE_DIR=/priv/cache/zig`) and
  makes `zig` available to this session.

  Options:

    * `:path` - use the toolchain already unpacked at this directory instead of
      fetching the package (an offline mirror, or a test).

  Installing once is enough for every session: the toolchain lives in
  `/priv/toolchain/`, not in a session.
  """
  @spec init(keyword()) :: :ok | {:error, term()}
  def init(opts \\ []) do
    path = Keyword.get(opts, :path, root())

    # An explicit path is the machine's toolchain from now on: an offline
    # mirror, or a test pointing at one it unpacked itself.
    if Keyword.has_key?(opts, :path), do: Application.put_env(:elixos, :toolchain_dir, path)

    cond do
      File.regular?(zig(path)) ->
        # One cache for the whole machine, like the toolchain itself: a build
        # in any session reuses what another already compiled.
        File.mkdir_p(cache())
        :ok

      Keyword.has_key?(opts, :path) ->
        {:error, {:no_toolchain, path}}

      true ->
        # Without a fetched package the disk's copy is the one there is; a
        # package would un-pack here (M14).
        {:error, {:not_installed, path}}
    end
  end

  @doc "Runs `zig build` with `args`, in the calling session's directory."
  @spec build([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def build(args, opts \\ []), do: run(["build" | args], opts)

  @doc "Runs `zig cc` with `args`, in the calling session's directory."
  @spec cc([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def cc(args, opts \\ []), do: run(["cc" | args], opts)

  @doc "The installed Zig version, or `{:error, :not_installed}`,"
  @spec version() :: {:ok, String.t()} | {:error, :not_installed}
  def version do
    case run(["version"], []) do
      {:ok, %{status: 0, output: output}} -> {:ok, String.trim(output)}
      _other -> {:error, :not_installed}
    end
  end

  # Exec'd directly - never through a shell (ADR-012) - with the working
  # directory of the *session* that asked (ADR-020), so a build lands where the
  # prompt is and the VM's own directory never moves (ADR-016).
  defp run(args, _opts) do
    path = zig(root())

    unless File.regular?(path) do
      throw({:error, {:not_installed, root()}})
    end

    cache = cache()
    File.mkdir_p(cache)

    {output, status} =
      System.cmd(path, args,
        cd: session_dir(),
        env: [{"ZIG_GLOBAL_CACHE_DIR", cache}],
        stderr_to_stdout: true
      )

    {:ok, %{status: status, output: output}}
  catch
    {:error, reason} -> {:error, reason}
  end

  # The session's directory, which is where a build lands (ADR-020). On a host
  # that directory does not exist - there is no /priv there - so the VM's own
  # is the honest stand-in; nothing here ever *changes* it (ADR-016).
  defp session_dir do
    dir = Elixos.Session.cwd()
    if File.dir?(dir), do: dir, else: File.cwd!()
  end

  defp root, do: Application.get_env(:elixos, :toolchain_dir, "/priv/toolchain")
  # PROTOCOL.md §7: the cache lives with the rest of the machine's state, so a
  # build in any session reuses what another already compiled.
  defp cache, do: Application.get_env(:elixos, :zig_cache_dir, "/priv/cache/zig")

  defp zig(path), do: Path.join(path, "zig")
end
