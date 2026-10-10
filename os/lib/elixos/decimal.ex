defmodule Elixos.Decimal do
  @moduledoc """
  Canonical unsigned decimals (docs/PROTOCOL.md §1), the BEAM twin of
  shim/src/decimal.zig: `0` or `[1-9][0-9]*`, at most 4_294_967_295, ASCII
  digits only, no sign, no leading zeros, no whitespace.

  Used for generation numbers on the control protocol, the boot environment
  and `elixos.*` command line values, so both sides parse numbers identically.
  """

  @spec parse_u32(term()) :: {:ok, 0..4_294_967_295} | :error
  def parse_u32(text) do
    _ = text
    Elixos.NotImplemented.raise!(2, "Elixos.Decimal.parse_u32/1")
  end
end
