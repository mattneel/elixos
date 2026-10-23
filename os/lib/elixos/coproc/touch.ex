defmodule Elixos.Coproc.Touch do
  @moduledoc """
  The panel's touch controller, owned by the coprocessor (ADR-106).
  Subscribers receive `{:touch, :down | :move | :up, x, y}` in panel
  coordinates (568x1232).

  Driver: `:coproc_touch` (os/src/coproc_touch.erl).
  """

  @doc "Subscribes `pid` to touches."
  @spec subscribe(pid()) :: :ok | {:error, term()}
  def subscribe(pid \\ self()), do: Elixos.Coproc.subscribe(:touch, pid)

  @doc "What the driver reports."
  @spec info() :: map() | {:error, term()}
  def info, do: Elixos.Coproc.driver_call(:coproc_touch, :info, [])
end
