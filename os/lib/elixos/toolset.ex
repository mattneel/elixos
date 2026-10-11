defmodule Elixos.Toolset do
  @moduledoc """
  The pinned OMP coding-agent toolset (M21, docs/ROADMAP.md, ADR-047).

  The dispatcher chooses an implementation before each call and records the
  implementation, revision and peer node that ran it. Initially the pure core
  runs in QuickBEAM in a supervised peer, with Elixir effects scoped to the
  calling session's workspace and M9 session directory.

  The per-tool choice is code in the generation, configured in
  `os/config/config.exs`, so every OS build loads the selection:

      config :elixos, Elixos.Toolset,
        implementations: %{"<tool>" => {:elixir, ImplementationModule}}

  The tuple's implementation is `:elixir` or `:native`; a tool absent from
  this map runs on `:quickbeam`. M24's `Elixos.Native.promote/1` and
  `Elixos.Native.revert/1` provide runtime overrides on top of this selection.

  OMP 18.8.7 is the reference for all 35 SDK factory tools, including hidden
  and settings-gated tools. Inventory membership does not bypass a factory's
  dependency or settings gates; `task` is deferred until M22. MCP and extension
  tools are not this inventory.

  No per-tool reference fixtures have been recorded yet. M21 must record and
  replay them before claiming output, failure or effect parity with OMP.
  Differential replay executes effects once; shadow comparisons are pure only.
  """

  @type implementation :: :quickbeam | :elixir | :native
  @type run_record :: %{
          tool: String.t(),
          implementation: implementation(),
          revision: String.t(),
          node: node()
        }

  @doc "Returns the pinned SDK's tool names in recorded inventory order."
  @spec inventory() :: [String.t()]
  def inventory, do: Elixos.NotImplemented.raise!(21, "Elixos.Toolset.inventory/0")

  @doc "Returns the tools waiting for a later milestone and their milestone numbers."
  @spec waiting() :: %{String.t() => pos_integer()}
  def waiting, do: Elixos.NotImplemented.raise!(21, "Elixos.Toolset.waiting/0")

  @doc """
  Calls a tool with OMP parameters in the calling session's isolated tool host.

  `:session` (`Elixos.Toolset.Session`) is required; `:timeout` is the caller's
  deadline in milliseconds, separate from the SDK bash timeout in seconds.
  Losing the peer mid-call returns `{:error, :tool_host_down}` without replaying
  the interrupted call's effects. Unknown, unavailable and deferred tools
  return distinct errors. Calls never change the main VM's cwd or environment.
  """
  @spec call(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def call(_tool, _params, _opts),
    do: Elixos.NotImplemented.raise!(21, "Elixos.Toolset.call/3")

  @doc """
  Returns the implementation the dispatcher will select for the next call.

  The generation's `os/config/config.exs` selects modules through
  `config :elixos, Elixos.Toolset, implementations: %{"<tool>" => {kind, module}}`,
  where `kind` is `:elixir` or `:native`; absent tools use `:quickbeam`.
  M24's `Elixos.Native.promote/1` and `Elixos.Native.revert/1` are runtime
  overrides on top of that generation configuration.
  """
  @spec implementation(String.t()) :: implementation()
  def implementation(_tool),
    do: Elixos.NotImplemented.raise!(21, "Elixos.Toolset.implementation/1")

  @doc "Returns the last run's provenance, or nil when the tool has not run."
  @spec last_run(String.t()) :: run_record() | nil
  def last_run(_tool), do: Elixos.NotImplemented.raise!(21, "Elixos.Toolset.last_run/1")
end
