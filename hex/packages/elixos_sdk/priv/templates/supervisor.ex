defmodule @MODULE@.Supervisor do
  @moduledoc "The same service tree is started by ordinary OTP or the Elixos installer."
  use Supervisor

  def start_link(options), do: Supervisor.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(_options) do
    Supervisor.init([{@MODULE@.Counter, []}], strategy: :one_for_one)
  end
end
