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
  def info do
    case Elixos.Boot.Env.current() do
      {:ok, :host} ->
        %{generation: nil, mode: :host, attempt: nil, version: version()}

      {:ok, env} ->
        %{generation: env.generation, mode: env.mode, attempt: env.attempt, version: version()}

      {:error, {kind, name}} ->
        # The shim sets all four variables or none (PROTOCOL.md §3); a partial
        # contract means the boot is broken, so say so loudly.
        raise "broken launch contract: #{kind} #{name} (PROTOCOL.md §3)"
    end
  end

  @doc "The version of the running OS, the :elixos application's."
  @spec version() :: String.t()
  def version do
    case Application.spec(:elixos, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end
end
