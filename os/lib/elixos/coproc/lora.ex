defmodule Elixos.Coproc.LoRa do
  @moduledoc """
  The deck's LoRa radio (SX1262), owned by the coprocessor (ADR-107).
  Sending is a call; subscribers receive each packet as
  `{:lora, packet, %{rssi: rssi, snr: snr}}`. Packets received while nobody
  is subscribed - Elixos restarting, say - wait in the driver.

  Driver: `:coproc_lora` (os/src/coproc_lora.erl).
  """

  @doc "Transmits `packet` (1 to 255 bytes)."
  @spec send(binary()) :: :ok | {:error, term()}
  def send(packet) when is_binary(packet), do: Elixos.Coproc.driver_call(:coproc_lora, :send, [packet])

  @doc "Subscribes `pid` to received packets."
  @spec subscribe(pid()) :: :ok | {:error, term()}
  def subscribe(pid \\ self()), do: Elixos.Coproc.subscribe(:lora, pid)

  @doc "What the driver reports: packets sent and received, queued events."
  @spec info() :: map() | {:error, term()}
  def info, do: Elixos.Coproc.driver_call(:coproc_lora, :info, [])
end
