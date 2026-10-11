defmodule Elixos.Toolset.Peer do
  @moduledoc """
  The supervised tool-host peer (M21, docs/ROADMAP.md, ADR-047).

  QuickBEAM 0.11.3 runs only in this supervised `:peer` BEAM node, never in
  the main VM. A `QuickBEAM.ContextPool` owns contexts started with
  `apis: false`, positive `:memory_limit` and `:max_reductions`;
  `:timeout` is passed to every context eval/call, not only startup.
  The high-level `QuickBEAM.start/1` ignores reduction budgets in this version.
  A peer failure returns
  `{:error, :tool_host_down}` to in-flight callers without interrupting the
  main prompt or shim heartbeat; supervision starts a fresh tool host for
  later calls, without retrying the lost call's effects.

  The pinned SDK inventory is recorded, but no per-tool reference fixtures or
  reference-validated peer recovery scenarios exist yet.
  """

  @doc "Returns the current tool-host peer's node name."
  @spec node() :: node()
  def node, do: Elixos.NotImplemented.raise!(21, "Elixos.Toolset.Peer.node/0")

  @doc "Kills the current tool-host peer, interrupting any in-flight calls."
  @spec kill() :: :ok
  def kill, do: Elixos.NotImplemented.raise!(21, "Elixos.Toolset.Peer.kill/0")

  @doc "Returns the context policy, including the positive timeout passed to each eval/call."
  @spec quickbeam_options() :: keyword()
  def quickbeam_options,
    do: Elixos.NotImplemented.raise!(21, "Elixos.Toolset.Peer.quickbeam_options/0")
end
