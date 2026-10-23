defmodule Elixos.Approvals.Host do
  @moduledoc """
  The OS's `OhMyJido.Host` (ADR-093): Oh-My-Jido's local policy, with every
  question left pending and indexed by `Elixos.Approvals` so any IEx or SSH
  session can answer it. Authorization, credentials and service dispatch are
  `OhMyJido.Host.Local`'s; options are passed through to it.

  A session started without this host can still ask, but only its own caller
  can see the question. Use it for agents that may run detached.
  """

  @behaviour OhMyJido.Host

  alias OhMyJido.Host.Local

  # Local's approval question names the effect but not the capability that
  # asked; keep that context so the person deciding can see it.
  @impl true
  def authorize(context, capability, effect, options) do
    case Local.authorize(context, capability, effect, options) do
      {:approval, question} when is_map(question) ->
        {:approval, Map.put_new(question, :capability, capability)}

      result ->
        result
    end
  end

  @impl true
  def credentials(context, account, options), do: Local.credentials(context, account, options)

  @impl true
  def invoke(context, capability, request, options),
    do: Local.invoke(context, capability, request, options)

  @impl true
  def question(context, question, _options) do
    if ambiguous?(question) do
      # A person could not tell these options apart, so neither can an answer.
      {:error, :invalid_question}
    else
      # Without the index the question still waits in its session and expires
      # closed; it is only harder to find. Never answer it here.
      _ = Elixos.Approvals.track(context, question)
      :pending
    end
  end

  defp ambiguous?(%{question: _text} = question) do
    labels = question |> Elixos.Approvals.describe() |> Map.fetch!(:options)
    Enum.any?(labels, &(&1 == "")) or length(Enum.uniq(labels)) != length(labels)
  end

  defp ambiguous?(_question), do: false
end
