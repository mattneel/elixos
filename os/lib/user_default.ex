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

  @doc "Changes the session's directory."
  def cd(path), do: Elixos.NotImplemented.raise!(9, ":user_default.cd/1 #{inspect(path)}")

  @doc "The session's working directory."
  def pwd, do: Elixos.NotImplemented.raise!(9, ":user_default.pwd/0")

  @doc "Lists the session's directory, or `path` inside it."
  def ls, do: Elixos.NotImplemented.raise!(9, ":user_default.ls/0")

  def ls(path), do: Elixos.NotImplemented.raise!(9, ":user_default.ls/1 #{inspect(path)}")
end
