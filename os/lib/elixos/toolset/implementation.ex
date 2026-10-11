defmodule Elixos.Toolset.Implementation do
  @moduledoc """
  The per-tool implementation contract (M21, docs/ROADMAP.md, ADR-047).

  Generation configuration can select an Elixir or native module implementing
  this callback. The dispatcher supplies the OMP parameters and the isolated
  tool session, and records the selected implementation's run provenance.

  An implementation preserves the pinned tool's successful result or error
  kind/message and applies session-scoped effects once. It does not replay
  effects for differential comparison. No per-tool reference fixtures exist
  yet; configuration alone does not establish OMP parity.
  """

  @doc "Runs a tool with OMP parameters and session-scoped access."
  @callback call(params :: map(), session :: Elixos.Toolset.Session.t()) ::
              {:ok, term()} | {:error, term()}
end
