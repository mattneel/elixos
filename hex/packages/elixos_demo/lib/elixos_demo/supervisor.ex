defmodule ElixosDemo.Supervisor do
  @moduledoc "A service tree started by ordinary OTP or the native Elixos installer."
  use Supervisor

  def start_link(options), do: Supervisor.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(_options) do
    Supervisor.init([{ElixosDemo.Journal, []}], strategy: :one_for_one)
  end
end
