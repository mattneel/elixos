defmodule Elixos.REPL.Helpers do
  @moduledoc """
  The session-aware `cd/1`, `pwd/0` and `ls/0,1` a login IEx gets (ADR-020, M9).

  IEx's own helpers are built on `File.cd/1` and `File.cwd/0`, which would move
  the whole VM (ADR-016; verified on Elixir 1.20.4: `IEx.Helpers.cd/1` calls
  `File.cd/1`). The login IEx therefore imports this module instead, so these
  are what a prompt has:

      iex(1)> pwd()
      "/priv/home"
      iex(2)> cd("/tmp")
      "/tmp"
      iex(3)> ls()
      ["boot.state", "home", "journal.log", ...]

  `ls/0` lists the session's directory, `ls/1` a path inside it, and `cd/1`
  accepts anything `Elixos.Session.expand/1` understands.
  """

  @doc "The session's working directory."
  @spec pwd() :: Path.t()
  def pwd, do: Elixos.Session.cwd()

  @doc "Changes the session's directory, like a shell's `cd`."
  @spec cd(Path.t()) :: Path.t() | {:error, term()}
  def cd(path) do
    case Elixos.Session.cd(path) do
      {:ok, dir} -> dir
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Lists the session's directory, or `path` inside it."
  @spec ls() :: [String.t()] | {:error, term()}
  def ls, do: ls(".")

  @spec ls(Path.t()) :: [String.t()] | {:error, term()}
  def ls(path), do: Elixos.Session.ls(path)
end
