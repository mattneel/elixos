defmodule Elixos.Coproc.Console do
  @moduledoc """
  The coprocessor's own console, UART3 (ADR-104). Subscribers receive each
  line typed into it as `{:console, line}`.

  Driver: `:coproc_console` (os/src/coproc_console.erl).
  """

  @doc "Writes `line` to UART3."
  @spec write(String.t()) :: :ok | {:error, term()}
  def write(line) when is_binary(line), do: Elixos.Coproc.driver_call(:coproc_console, :write, [line])

  @doc "Subscribes `pid` to console input."
  @spec subscribe(pid()) :: :ok | {:error, term()}
  def subscribe(pid \\ self()), do: Elixos.Coproc.subscribe(:console, pid)

  @doc "What the driver reports."
  @spec info() :: map() | {:error, term()}
  def info, do: Elixos.Coproc.driver_call(:coproc_console, :info, [])
end
