defmodule Elixos.Toolset.Actions.Todo do
  @moduledoc """
  The complete OMP Todo state machine as a Jido Action (M21).

  Schema and description are generation-owned upstream catalog values. The
  original validator, lenient repairs and atomic state transitions run in the
  peer; `Elixos.Toolset.Action.execute/3` is the no-retry model boundary.
  """

  use Jido.Action,
    name: "todo",
    description: Elixos.Toolset.Catalog.default_variant("todo")["fields"]["description"],
    schema: Elixos.Toolset.Catalog.default_schema("todo")

  @impl Jido.Action
  def run(params, context) do
    Elixos.Toolset.Action.run(%{"tool" => "todo", "arguments" => params}, context)
  end
end
