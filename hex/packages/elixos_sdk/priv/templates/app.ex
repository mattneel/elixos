defmodule @MODULE@ do
  @moduledoc """
  A supervised durable counter that runs as an ordinary Mix application.

  Host: `mix test` or `iex -S mix`. Elixos: package the source with
  `MIX_ENV=prod MIX_TARGET=elixos mix elixos.package`, then build/install it
  natively using `Elixos.Package.install/1` in real Elixos. The OS dependency
  is supplied by that running system, never fetched or bundled on the host.

  State is stored under `var/state` on the host and `/priv/data/@APP@/state`
  on Elixos, outside the replaceable installed code. `persist: ["state"]`
  does not make a Live system's RAM survive a kernel reboot.
  """

  @doc "Reads the current durable value."
  def value, do: @MODULE@.Counter.value(@MODULE@.Counter)

  @doc "Adds a positive integer and replies only after the write succeeds."
  def increment(amount \\ 1), do: @MODULE@.Counter.increment(@MODULE@.Counter, amount)

  @doc "Portable counter arithmetic, independent of any OS runtime."
  def advance(value, amount) when is_integer(value) and is_integer(amount) and amount > 0 do
    value + amount
  end
end
