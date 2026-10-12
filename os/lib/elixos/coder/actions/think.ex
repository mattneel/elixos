defmodule Elixos.Coder.Actions.Think do
  @moduledoc """
  OMP's private scratchpad as a Jido Action (M21).

  The original schema and execution/validation run in the supervised peer.
  Neither the success result nor provenance records accepted scratchpad contents.
  """
  use Jido.Action,
    name: "think",
    description: Elixos.Toolset.Catalog.default_variant("think")["fields"]["description"],
    schema: Elixos.Toolset.Catalog.default_schema("think")

  @impl Jido.Action
  def run(params, context) do
    Elixos.Toolset.Action.run(%{"tool" => "think", "arguments" => params}, context)
  end
end
