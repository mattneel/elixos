defmodule SampleApp do
  @moduledoc "Fixture app for packaging tests."

  def where, do: Application.fetch_env!(:sample_app, :where)
end

defmodule SampleApp.Worker do
  @moduledoc "A service the installer starts from the elixos: key."
  use GenServer

  def start_link(arg), do: GenServer.start_link(__MODULE__, arg, name: __MODULE__)

  def ping, do: GenServer.call(__MODULE__, :ping)

  @impl true
  def init(arg), do: {:ok, arg}

  @impl true
  def handle_call(:ping, _from, state), do: {:reply, :pong, state}
end
