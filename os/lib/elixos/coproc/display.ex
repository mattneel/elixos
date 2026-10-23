defmodule Elixos.Coproc.Display do
  @moduledoc """
  The deck's display unit, owned by the coprocessor (ADR-106): the 568x1232
  AMOLED, its touch controller (`Elixos.Coproc.Touch`) and the HDMI bridge.

  Elixos renders into the shared-memory framebuffer and reports which region
  changed (`update/1`); the coprocessor scans it out. `status/1` sets the
  line the coprocessor shows on its own while the BEAM restarts. Both stay
  on the panel while Elixos is away. Subscribers receive
  `{:display, {:hdmi, :connected | :disconnected}}`.

  Driver: `:coproc_display` (os/src/coproc_display.erl).
  """

  @type region :: {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()}

  @doc "Shows `text` as the coprocessor's status line."
  @spec status(String.t()) :: :ok | {:error, term()}
  def status(text) when is_binary(text), do: Elixos.Coproc.driver_call(:coproc_display, :status, [text])

  @doc "Scans out `{x, y, width, height}` of the shared framebuffer."
  @spec update(region()) :: :ok | {:error, term()}
  def update({_x, _y, _w, _h} = region), do: Elixos.Coproc.driver_call(:coproc_display, :update, [region])

  @doc "What the driver reports: size, status, frames scanned out, HDMI state."
  @spec info() :: map() | {:error, term()}
  def info, do: Elixos.Coproc.driver_call(:coproc_display, :info, [])

  @doc "Subscribes `pid` to display events."
  @spec subscribe(pid()) :: :ok | {:error, term()}
  def subscribe(pid \\ self()), do: Elixos.Coproc.subscribe(:display, pid)
end
