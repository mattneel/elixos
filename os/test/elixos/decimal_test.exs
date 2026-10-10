defmodule Elixos.DecimalTest do
  # Mirrors shim/src/decimal.zig, case for case.
  use ExUnit.Case, async: true

  @moduletag milestone: 2

  alias Elixos.Decimal

  test "accepts canonical u32 values" do
    assert Decimal.parse_u32("0") == {:ok, 0}
    assert Decimal.parse_u32("7") == {:ok, 7}
    assert Decimal.parse_u32("10") == {:ok, 10}
    assert Decimal.parse_u32("4294967295") == {:ok, 4_294_967_295}
  end

  test "rejects everything that is not canonical" do
    rejected = [
      "",
      "00",
      "07",
      "-1",
      "+1",
      " 1",
      "1 ",
      "1\n",
      "1.0",
      "0x10",
      "1_000",
      "1e3",
      "4294967296",
      "4294967300",
      "99999999999999999999",
      "١",
      nil,
      7
    ]

    for text <- rejected do
      assert Decimal.parse_u32(text) == :error, "#{inspect(text)} must be rejected"
    end
  end
end
