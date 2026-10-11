defmodule Elixos.Shim.Protocol do
  @moduledoc """
  The shim control protocol, BEAM side (docs/PROTOCOL.md §2).

  One ASCII line per message, BEAM -> shim, over the control pipe:

  | message           | wire              |
  |-------------------|-------------------|
  | `:heartbeat`      | `HB\\n`            |
  | `{:commit, gen}`  | `COMMIT <gen>\\n`  |
  | `{:next, gen}`    | `NEXT <gen>\\n`    |
  | `:reboot`         | `REBOOT\\n`        |
  | `:poweroff`       | `POWEROFF\\n`      |
  | `:halt`           | `HALT\\n`          |
  | `{:helper, name}` | `HELPER <name>\\n` |

  `gen` is a canonical decimal u32 (PROTOCOL.md §1). The Zig shim parses the
  same lines; both suites run `spec/protocol.vectors`, so they cannot drift.
  The BEAM only encodes in production; `decode/1` exists for tooling and tests.
  """

  @max_line 64

  @type generation :: 0..4_294_967_295
  @type message ::
          :heartbeat
          | {:commit, generation}
          | {:next, generation}
          | :reboot
          | :poweroff
          | :halt
          | {:helper, String.t()}

  @doc "Longest accepted line, excluding the trailing newline."
  @spec max_line_length() :: pos_integer()
  def max_line_length, do: @max_line

  @doc """
  Decodes one line, given without its trailing `\\n`.

  Lines longer than #{@max_line} bytes are `{:error, :too_long}` regardless of
  content; anything else that is not exactly a valid message is `{:error, :invalid}`.
  """
  @spec decode(binary()) :: {:ok, message()} | {:error, :invalid | :too_long}
  def decode(line) when is_binary(line) do
    # The length limit is checked before anything else (PROTOCOL.md §2).
    if byte_size(line) > @max_line do
      {:error, :too_long}
    else
      case line do
        "HB" ->
          {:ok, :heartbeat}

        "REBOOT" ->
          {:ok, :reboot}

        "POWEROFF" ->
          {:ok, :poweroff}

        "HALT" ->
          {:ok, :halt}

        "COMMIT " <> rest ->
          numbered(:commit, rest)

        "NEXT " <> rest ->
          numbered(:next, rest)

        "HELPER " <> name ->
          if Elixos.Privileges.valid_name?(name),
            do: {:ok, {:helper, name}},
            else: {:error, :invalid}

        _ ->
          {:error, :invalid}
      end
    end
  end

  defp numbered(kind, rest) do
    case Elixos.Decimal.parse_u32(rest) do
      {:ok, generation} -> {:ok, {kind, generation}}
      :error -> {:error, :invalid}
    end
  end

  @doc """
  Encodes a message as a wire line, including the trailing `\\n`.

  Raises `ArgumentError` for anything that is not a valid `t:message/0`.
  """
  @spec encode(message()) :: binary()
  def encode(:heartbeat), do: "HB\n"
  def encode({:commit, generation}), do: "COMMIT #{generation!(generation)}\n"
  def encode({:next, generation}), do: "NEXT #{generation!(generation)}\n"
  def encode(:reboot), do: "REBOOT\n"
  def encode(:poweroff), do: "POWEROFF\n"
  def encode(:halt), do: "HALT\n"

  def encode({:helper, name}) do
    case Elixos.Privileges.encode_request(name) do
      {:ok, line} -> line
      {:error, :invalid_name} -> raise ArgumentError, "not a helper name: #{inspect(name)}"
    end
  end

  def encode(other), do: raise(ArgumentError, "not a control message: #{inspect(other)}")

  defp generation!(generation)
       when is_integer(generation) and generation >= 0 and generation <= 4_294_967_295,
       do: generation

  defp generation!(other), do: raise(ArgumentError, "not a generation: #{inspect(other)}")
end
