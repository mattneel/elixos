defmodule :user_default do
  @moduledoc """
  The erl shell's session-aware built-ins (ADR-020, M9).

  The erl shell resolves unknown functions through `user_default`, and its
  `cd/1` comes from there and calls `file:set_cwd/1`, which moves the whole VM
  (ADR-016). This module is the same idea for erl as
  `Elixos.REPL.Helpers` is for IEx: the shell commands work on the session's
  directory and the VM never moves.

      ieshell> cd("/tmp").
      "/tmp"
      ieshell> pwd().
      "/tmp"

  It is an Erlang-named module on purpose: the shell only looks for
  `user_default`.
  """

  # The erl shell prints binaries as <<"...">>, so these speak Erlang: paths
  # are charlists, the way file/1 and friends expect them.

  @doc "Changes the session's directory."
  def cd(path) do
    case Elixos.Session.cd(to_string(path)) do
      {:ok, dir} -> to_charlist(dir)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The session's working directory."
  def pwd, do: to_charlist(Elixos.Session.cwd())

  @doc "Lists the session's directory, or `path` inside it."
  def ls, do: ls(".")

  def ls(path) do
    case Elixos.Session.ls(to_string(path)) do
      names when is_list(names) -> Enum.map(names, &to_charlist/1)
      {:error, reason} -> {:error, reason}
    end
  end
end
