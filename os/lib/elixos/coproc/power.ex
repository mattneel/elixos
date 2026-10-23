defmodule Elixos.Coproc.Power do
  @moduledoc """
  The K230 PMU's power key and main-supply enable, owned by the coprocessor
  (ADR-109). Subscribers receive `{:power_key, :pressed | :released}`.

  Driver: `:coproc_power` (os/src/coproc_power.erl).
  """

  @doc """
  Asks the coprocessor to cut the main supply: the last step of a power-off,
  after Linux has synced and stopped. On the board it does not return.
  """
  @spec poweroff() :: :ok | {:error, term()}
  def poweroff, do: Elixos.Coproc.driver_call(:coproc_power, :poweroff, [])

  @doc "Subscribes `pid` to power-key events."
  @spec subscribe(pid()) :: :ok | {:error, term()}
  def subscribe(pid \\ self()), do: Elixos.Coproc.subscribe(:power, pid)

  @doc "What the driver reports."
  @spec info() :: map() | {:error, term()}
  def info, do: Elixos.Coproc.driver_call(:coproc_power, :info, [])
end
