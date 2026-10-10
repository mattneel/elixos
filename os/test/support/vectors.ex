defmodule Elixos.Test.Vectors do
  @moduledoc """
  Reads spec/protocol.vectors, the golden vectors shared with the Zig shim.
  The file documents its own format; this mirrors shim/src/protocol.zig.
  """

  @doc "Returns `[{line_number, wire, expected}]`."
  def protocol do
    Elixos.Test.Paths.spec("protocol.vectors")
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {line, _} -> line == "" or String.starts_with?(line, "#") end)
    |> Enum.map(fn {line, number} ->
      [wire, expected] = String.split(line, "\t", parts: 2)
      {number, unescape(wire, <<>>), expected(expected)}
    end)
  end

  defp unescape(<<"\\\\", rest::binary>>, acc), do: unescape(rest, <<acc::binary, ?\\>>)

  defp unescape(<<"\\x", hex::binary-size(2), rest::binary>>, acc),
    do: unescape(rest, <<acc::binary, String.to_integer(hex, 16)>>)

  defp unescape(<<byte, rest::binary>>, acc), do: unescape(rest, <<acc::binary, byte>>)
  defp unescape(<<>>, acc), do: acc

  defp expected("heartbeat"), do: {:ok, :heartbeat}
  defp expected("commit " <> gen), do: {:ok, {:commit, String.to_integer(gen)}}
  defp expected("next " <> gen), do: {:ok, {:next, String.to_integer(gen)}}
  defp expected("reboot"), do: {:ok, :reboot}
  defp expected("poweroff"), do: {:ok, :poweroff}
  defp expected("halt"), do: {:ok, :halt}
  defp expected("invalid"), do: {:error, :invalid}
  defp expected("too_long"), do: {:error, :too_long}
end
