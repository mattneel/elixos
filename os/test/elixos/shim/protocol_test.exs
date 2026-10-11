defmodule Elixos.Shim.ProtocolTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 2

  alias Elixos.Shim.Protocol
  alias Elixos.Test.Vectors

  # The same file the Zig shim's tests read: the two sides cannot drift.
  @external_resource Elixos.Test.Paths.spec("protocol.vectors")

  for {line, wire, expected} <- Vectors.protocol() do
    @wire wire
    @expected expected

    test "spec/protocol.vectors:#{line} #{inspect(wire, binaries: :as_strings)}" do
      assert Protocol.decode(@wire) == @expected

      case @expected do
        {:ok, message} -> assert Protocol.encode(message) == @wire <> "\n"
        {:error, _} -> :ok
      end
    end
  end

  test "the vectors cover every message kind" do
    kinds =
      for {_, _, {:ok, message}} <- Vectors.protocol(), uniq: true do
        if is_tuple(message), do: elem(message, 0), else: message
      end

    assert Enum.sort(kinds) ==
             Enum.sort([:heartbeat, :commit, :next, :reboot, :poweroff, :halt, :helper])
  end

  test "encode rejects anything that is not a message" do
    for bad <- [
          {:commit, -1},
          {:commit, 4_294_967_296},
          {:commit, 1.0},
          {:next, "3"},
          {:helper, ""},
          {:helper, "UPPER"},
          {:helper, "a\n"},
          {:helper, String.duplicate("a", 33)},
          {:helper, nil},
          :bogus,
          "HB"
        ] do
      assert_raise ArgumentError, fn -> Protocol.encode(bad) end
    end
  end

  test "the line limit matches the shim" do
    assert Protocol.max_line_length() == 64
  end
end
