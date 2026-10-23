defmodule ElixosDemo.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _arguments), do: ElixosDemo.Supervisor.start_link([])
end
