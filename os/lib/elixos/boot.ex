defmodule Elixos.Boot do
  @moduledoc """
  Facts about the running boot, from `Elixos.Boot.Env` (M4).

      iex> Elixos.Boot.info()
      %{generation: 0, mode: :normal, attempt: 1, version: "0.1.0"}

  On the dev host there is no shim; `info/0` then returns `%{mode: :host, ...}`.
  The QEMU tests read this from the console, so keep the keys stable.
  """

  @spec info() :: %{
          generation: non_neg_integer() | nil,
          mode: :normal | :rescue | :host,
          attempt: non_neg_integer() | nil,
          version: String.t()
        }
  def info, do: Elixos.NotImplemented.raise!(4, "Elixos.Boot.info/0")
end
