defmodule Elixos.Session do
  @moduledoc """
  The working directory of a REPL session (ADR-020, M9).

  Every process on Elixos shares one VM, so the VM's working directory cannot
  be a shell's working directory (ADR-016). A session's directory is therefore
  kept here, keyed by the session's **process-group leader**: everything
  spawned from a REPL inherits its group leader, so a console job, an SSH
  channel and any task they start all resolve relative paths the same way.

      iex(1)> pwd()
      "/data/home"
      iex(2)> cd("src")
      iex(3)> Elixos.Session.cwd()
      "/data/home/src"

  The login REPLs carry session-aware `cd/1`, `pwd/0` and `ls/0,1`
  (`Elixos.REPL.Helpers` for IEx, `:user_default` for erl). Nothing here ever
  calls `File.cd/1` or `file:set_cwd/1`: the VM's directory stays `/`.
  """

  @default_dir "/data/home"

  @doc "The calling session's working directory."
  @spec cwd() :: Path.t()
  def cwd, do: Elixos.NotImplemented.raise!(9, "Elixos.Session.cwd/0")

  @doc """
  Changes the calling session's directory to `path`, expanded against the
  session's current directory. `{:error, :enoent}` when it does not exist.
  """
  @spec cd(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def cd(path), do: Elixos.NotImplemented.raise!(9, "Elixos.Session.cd/1 #{inspect(path)}")

  @doc "Expands `path` against the calling session's directory."
  @spec expand(Path.t()) :: Path.t()
  def expand(path), do: Elixos.NotImplemented.raise!(9, "Elixos.Session.expand/1 #{inspect(path)}")

  @doc "Where a session starts before anything changes it."
  @spec default() :: Path.t()
  def default, do: @default_dir

  @doc "The directory of the session whose group leader is `pid` (tests, tooling)."
  @spec cwd_for(pid()) :: Path.t()
  def cwd_for(leader), do: Elixos.NotImplemented.raise!(9, "Elixos.Session.cwd_for/1 #{inspect(leader)}")
end
