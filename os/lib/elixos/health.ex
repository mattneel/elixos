defmodule Elixos.Health do
  @moduledoc """
  Real generation health checks (M23, docs/ROADMAP.md, ADR-049).

  AutoCommit must run the system's own test suite and the toolset smoke tests,
  not merely check that a supervisor is alive. Failed checks are named in the
  result and retained with the candidate's evidence.

  The default checks include `:system_suite` and `:toolset_smoke`. Tests may
  replace the named checks through `Application.get_env(:elixos, :health_checks)`;
  `run/0` evaluates every check and reports every failure, without short-circuiting.
  """

  @type check :: {atom(), (-> :ok | {:error, term()})}

  @doc "Returns the named system-suite and toolset-smoke health predicates."
  @spec checks() :: [check()]
  def checks, do: Elixos.NotImplemented.raise!(23, "Elixos.Health.checks/0")

  @doc "Runs all checks, returning their names and reasons when any fail."
  @spec run() :: :ok | {:error, [{atom(), term()}]}
  def run, do: Elixos.NotImplemented.raise!(23, "Elixos.Health.run/0")
end
