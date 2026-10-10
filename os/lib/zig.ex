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
  def init(opts \\ []), do: Elixos.NotImplemented.raise!(11, "Zig.init/1 #{inspect(opts)}")

  @doc "Runs `zig build` with `args`, in the calling session's directory."
  @spec build([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def build(args, opts \\ []), do: Elixos.NotImplemented.raise!(11, "Zig.build/2 #{inspect({args, opts})}")

  @doc "Runs `zig cc` with `args`, in the calling session's directory."
  @spec cc([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def cc(args, opts \\ []), do: Elixos.NotImplemented.raise!(11, "Zig.cc/2 #{inspect({args, opts})}")

  @doc "The installed Zig version, or `{:error, :not_installed}`,"
  @spec version() :: {:ok, String.t()} | {:error, :not_installed}
  def version, do: Elixos.NotImplemented.raise!(11, "Zig.version/0")
end
