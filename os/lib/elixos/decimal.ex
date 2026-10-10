defmodule Elixos.Decimal do
  @moduledoc """
  Canonical unsigned decimals (docs/PROTOCOL.md §1), the BEAM twin of
  shim/src/decimal.zig: `0` or `[1-9][0-9]*`, at most 4_294_967_295, ASCII
  digits only, no sign, no leading zeros, no whitespace.

  Used for generation numbers on the control protocol, the boot environment
  and `elixos.*` command line values, so both sides parse numbers identically.
  """

  @spec parse_u32(term()) :: {:ok, 0..4_294_967_295} | :error
  def parse_u32(text) when is_binary(text) and byte_size(text) in 1..10 do
    case text do
      # "0" is canonical; anything else starting with ?0 has a leading zero.
      "0" -> {:ok, 0}
      <<first, rest::binary>> when first in ?1..?9 -> value(rest, first - ?0)
      _ -> :error
    end
  end

  def parse_u32(_text), do: :error

  # Folds the remaining bytes in, so no non-digit ever reaches an integer parse.
  defp value(<<byte, rest::binary>>, acc) when byte in ?0..?9, do: value(rest, acc * 10 + (byte - ?0))
  defp value(<<>>, acc) when acc <= 4_294_967_295, do: {:ok, acc}
  defp value(_rest, _acc), do: :error
end
