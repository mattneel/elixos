defmodule Elixos.Native.CrashProbe do
  @moduledoc """
  Deliberately crashing unproven native candidate (M24, docs/ROADMAP.md, ADR-050).

  M24 replaces this loud stub with a NIF that crashes its host. It must be
  invoked through `Elixos.Native.run_in_peer/3`, never directly in the main VM,
  so peer loss becomes `{:error, :tool_host_down}` and a fresh peer can serve
  the next tool call.

  Reference-validation limit: crash isolation has not been checked against
  an M24 implementation; this module does not yet contain a crashing NIF.
  """

  @doc "Crashes the hosting peer to exercise native candidate isolation."
  @spec crash() :: no_return()
  def crash, do: Elixos.NotImplemented.raise!(24, "Elixos.Native.CrashProbe.crash/0")
end
