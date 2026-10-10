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
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Protocol.decode/1")
  end

  @doc """
  Encodes a message as a wire line, including the trailing `\\n`.

  Raises `ArgumentError` for anything that is not a valid `t:message/0`.
  """
  @spec encode(message()) :: binary()
  def encode(message) do
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Protocol.encode/1 #{inspect(message)}")
  end
end
