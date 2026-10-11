defmodule Elixos.Native.Patch do
  @moduledoc """
  Pure patch application hot path (M24, docs/ROADMAP.md, ADR-050).

  This plain-Elixir milestone stub is replaced by pure Zigler work only when
  recorded OMP differential results are identical and concurrent dispatcher
  p99 (conversion included) is strictly lower. Bounded synchronous work must
  remain well below 1 ms; otherwise use dirty/threaded admission.

  Reference-validation limit: M21's recorded per-tool fixtures do not exist
  yet, and this contract has not been checked against an M24 implementation.
  """

  @doc "Applies a patch to text, returning the resulting text or the patch failure."
  @spec apply_patch(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def apply_patch(_text, _patch),
    do: Elixos.NotImplemented.raise!(24, "Elixos.Native.Patch.apply_patch/2")
end
