defmodule Elixos.REPL do
  @moduledoc """
  REPLs are the login shells (ADR-012). There is no sh: logging in, on the
  console or over SSH, drops you into erl, IEx or gsh, all attached to the
  same running VM.

  The contract every REPL meets is the one OTP already uses for
  `:shell.start_interactive/1` and the `ssh` daemon's `:shell` option: an MFA
  whose call starts the shell and returns its pid.

    * `:erl` - `{:shell, :start, []}`
    * `:lfe` - LFE's shell, `{:lfe_shell, :start, []}`, when its package is in
    * `:clojerl` - Clojerl's shell, when its package is in
    * `:iex` - an Elixos-owned MFA that spawns `IEx.Server.run/1` and returns
      the pid. `IEx.Server.run/1` takes an `:env` option; Elixos passes an env
      whose `tracers` include the capture tracer, so every module typed at the
      prompt is journaled (see `Elixos.Image.Capture`). Note: Elixir 1.20 has
      no public `IEx.start`; `IEx.Server.run/1` is the documented entry point.
    * `:gsh` - Gleam's community REPL, only when its modules are installed

  `available/0` is sorted; `mfa/1` returns `{:error, :unknown_repl}` for names
  that are not REPLs and `{:error, :unavailable}` for known ones not installed.
  """

  @type name :: :iex | :erl | :lfe | :clojerl | :gsh

  # Every language's shell entry point, as OTP's contract wants it: an MFA
  # whose call starts the shell and returns its pid.
  @repls [
    iex: {Elixos.Boot.Login, :start_iex, []},
    erl: {:shell, :start, []},
    lfe: {:lfe_shell, :start, []},
    clojerl: {:clojerl, :start, []},
    gsh: {:gsh, :start, []}
  ]

  @spec available() :: [name()]
  def available do
    # IEx and erl are part of Elixos; the other languages are offered when a
    # package installed their modules *and* their shell entry point is really
    # callable - an entry that cannot start is worse than no entry.
    Enum.sort(for {name, mfa} <- @repls, name in [:iex, :erl] or callable?(mfa), do: name)
  end

  @spec mfa(atom()) :: {:ok, {module(), atom(), list()}} | {:error, :unknown_repl | :unavailable}
  def mfa(name) when is_atom(name) do
    case Keyword.fetch(@repls, name) do
      {:ok, mfa} -> if name in available(), do: {:ok, mfa}, else: {:error, :unavailable}
      :error -> {:error, :unknown_repl}
    end
  end

  defp callable?({module, function, args}) do
    Code.ensure_loaded?(module) and function_exported?(module, function, length(args))
  end

  @doc "The REPL used when the user has not chosen one."
  @spec default() :: name()
  def default, do: :iex
end
