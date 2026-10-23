defmodule @MODULE@.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _arguments), do: @MODULE@.Supervisor.start_link([])
end
