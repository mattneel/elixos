defmodule Elixos.Package.Proto do
  @moduledoc false
  # The subset of protocol buffers the Hex registry uses (varint and
  # length-delimited fields), enough to read `names`, `versions` and
  # `packages/<name>` and to split a signed resource into payload and
  # signature. Unknown wire types are refused, not skipped: a resource this
  # code does not understand must not be silently half-read.

  @type message :: %{pos_integer() => [non_neg_integer() | binary()]}

  @spec decode(binary()) :: {:ok, message()} | {:error, term()}
  def decode(binary) when is_binary(binary), do: decode(binary, %{})

  defp decode(<<>>, acc), do: {:ok, acc}

  defp decode(bin, acc) do
    with {:ok, tag, rest} <- varint(bin) do
      field = Bitwise.bsr(tag, 3)
      wire = Bitwise.band(tag, 7)

      case wire do
        0 ->
          with {:ok, value, rest} <- varint(rest), do: decode(rest, put(acc, field, value))

        2 ->
          with {:ok, length, rest} <- varint(rest),
               {:ok, data, rest} <- take(rest, length) do
            decode(rest, put(acc, field, data))
          end

        other ->
          {:error, {:wire_type, other}}
      end
    end
  end

  @doc "Every value of `field`, in order."
  @spec all(message(), pos_integer()) :: [non_neg_integer() | binary()]
  def all(message, field), do: Map.get(message, field, [])

  @doc "The first value of `field`, or nil."
  @spec one(message(), pos_integer()) :: non_neg_integer() | binary() | nil
  def one(message, field) do
    case all(message, field) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp put(acc, field, value) do
    Map.update(acc, field, [value], &(&1 ++ [value]))
  end

  defp varint(bin), do: varint(bin, 0, 0)

  defp varint(<<byte, rest::binary>>, shift, acc) when shift < 64 do
    acc = Bitwise.bor(acc, Bitwise.bsl(Bitwise.band(byte, 0x7F), shift))

    if Bitwise.band(byte, 0x80) == 0 do
      {:ok, acc, rest}
    else
      varint(rest, shift + 7, acc)
    end
  end

  defp varint(_, _, _), do: {:error, :varint}

  defp take(bin, length) when byte_size(bin) >= length do
    {:ok, binary_part(bin, 0, length), binary_part(bin, length, byte_size(bin) - length)}
  end

  defp take(_bin, _length), do: {:error, :truncated}
end
