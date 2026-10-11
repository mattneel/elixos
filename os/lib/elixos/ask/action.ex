defmodule Elixos.Ask.Action do
  @moduledoc """
  Asking the human, as a Jido action (M20, docs/ROADMAP.md): an agent routes a
  signal here and blocks until a front-end answers, so the same question works
  from IEx, from an ssh session, or (M27) from the GUI.

      defmodule MyAgent do
        use Jido.Agent,
          name: "asker",
          signal_routes: [{"ask_human", Elixos.Ask.Action}]
      end

  The action's result carries the answer into the agent's state under
  `:answer`, so whatever runs after it has the value.
  """

  use Jido.Action,
    name: "ask_human",
    schema: [
      kind: [type: :string, default: "text"],
      prompt: [type: :string, default: ""],
      options: [type: {:list, :string}, default: []],
      allow_other: [type: :boolean, default: false]
    ]

  @impl Jido.Action
  def run(params, _context) do
    with {:ok, kind} <- kind(params.kind),
         :ok <- options_for(kind, params.options),
         {:ok, answer} <-
           Elixos.Ask.ask(kind,
             prompt: params.prompt,
             options: params.options,
             allow_other: params.allow_other
           ) do
      {:ok, %{answer: answer}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # The wire carries a string; the queue takes the atom. Only the four kinds
  # exist, so a typo comes back as an error instead of interning a new atom.
  defp kind("text"), do: {:ok, :text}
  defp kind("choice"), do: {:ok, :choice}
  defp kind("multi"), do: {:ok, :multi}
  defp kind("confirm"), do: {:ok, :confirm}
  defp kind(other), do: {:error, "unknown question kind: #{inspect(other)}"}

  defp options_for(kind, options) when kind in [:choice, :multi] and options == [] do
    {:error, "a #{kind} question needs options"}
  end

  defp options_for(_kind, _options), do: :ok
end
