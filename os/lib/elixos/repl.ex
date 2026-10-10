defmodule Elixos.REPL do
  @moduledoc """
  REPLs are the login shells (ADR-012). There is no sh: logging in, on the
  console or over SSH, drops you into erl, IEx or gsh, all attached to the
  same running VM.

  The contract every REPL meets is the one OTP already uses for
  `:shell.start_interactive/1` and the `ssh` daemon's `:shell` option: an MFA
  whose call starts the shell and returns its pid.

    * `:erl` - `{:shell, :start, []}`
    * `:iex` - an Elixos-owned MFA that spawns `IEx.Server.run/1` and returns
      the pid. `IEx.Server.run/1` takes an `:env` option; Elixos passes an env
      whose `tracers` include the capture tracer, so every module typed at the
      prompt is journaled (see `Elixos.Image.Capture`). Note: Elixir 1.20 has
      no public `IEx.start`; `IEx.Server.run/1` is the documented entry point.
    * `:gsh` - Gleam's community REPL, only when its modules are installed

  `available/0` is sorted; `mfa/1` returns `{:error, :unknown_repl}` for names
  that are not REPLs and `{:error, :unavailable}` for known ones not installed.
  """

  @type name :: :iex | :erl | :gsh

  @spec available() :: [name()]
  def available, do: Elixos.NotImplemented.raise!(9, "Elixos.REPL.available/0")

  @spec mfa(atom()) :: {:ok, {module(), atom(), list()}} | {:error, :unknown_repl | :unavailable}
  def mfa(name) when is_atom(name),
    do: Elixos.NotImplemented.raise!(9, "Elixos.REPL.mfa/1 #{inspect(name)}")

  @doc "The REPL used when the user has not chosen one."
  @spec default() :: name()
  def default, do: :iex
end
