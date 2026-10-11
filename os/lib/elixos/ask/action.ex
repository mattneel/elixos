defmodule Elixos.Ask.Action do
  @moduledoc """
  The Ask queue as a Jido tool (M20, docs/ROADMAP.md): an agent action whose
  parameters are a question (kind, prompt, options, default, timeout) and
  whose value is the answer - so an agent can ask the human something and act
  on what comes back.

      use Jido.Agent, ..., signal_routes: [{"ask_human", Elixos.Ask.Action}]

  `perform/2` blocks like `Elixos.Ask.ask/2` does, inside the agent's process;
  a timeout or a dismissal is an action error, not an answer.
  """
end
