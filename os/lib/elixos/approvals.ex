defmodule Elixos.Approvals do
  @moduledoc """
  Every open Oh-My-Jido approval and question on this machine, answerable from
  any IEx or SSH session (ADR-093).

  Oh-My-Jido owns the human-in-the-loop contract: a managed session pauses the
  waiting effect or question, keeps its context (session, run, capability,
  effect), fails closed on timeout, cancellation or a non-approving answer, and
  never revives an old question after a restart. A session belongs to its
  runtime, not to the REPL that started it, so an agent started in the
  background, from an Oban job or resumed after a reboot asks the same way.

  What the library does not provide is one place to find those questions
  across sessions. `Elixos.Approvals.Host` is the OS's `OhMyJido.Host`: its
  `question/3` callback leaves every question pending and registers its
  session here. This server subscribes to that session, indexes the open
  questions under small OS-local numbers, and drops them when the session
  reports them answered, withdrawn or expired, or when the session exits.

      iex> approvals()
      [%Elixos.Approvals.Request{id: 1, kind: :confirm, prompt: "exec: run", ...}]
      iex> approve(1)
      :ok

  Answers go through `OhMyJido.answer/3` unchanged: `approve/1` sends `true`,
  `deny/1` sends `:deny` (any non-approving value denies), and `answer/2`
  validates a clarification against its offered options. Nothing here answers
  on its own; a default is only display data.

  This index is not boot-critical and runs no part of rescue. It decides no
  privilege: the unprivileged BEAM and sealed commits hold whatever is approved.
  """

  use GenServer
  require Logger

  alias OhMyJido.{Event, SessionRef}

  @runtime Elixos.Coding

  defmodule Request do
    @moduledoc """
    One open Oh-My-Jido question as the OS presents it. `id` is OS-local;
    `session_id` and `question_id` identify it to Oh-My-Jido. `kind` is
    `:confirm` for an effect approval and `:text`, `:choice` or `:multi` for a
    clarification. `question` is the library's original (redacted) map.
    """

    defstruct [
      :id,
      :session,
      :session_id,
      :question_id,
      :run_id,
      :kind,
      :prompt,
      :question,
      :requested_at,
      options: [],
      choices: [],
      allow_other: false,
      default: nil
    ]

    @type t :: %__MODULE__{
            id: pos_integer(),
            session: OhMyJido.SessionRef.t(),
            session_id: String.t(),
            question_id: String.t(),
            run_id: String.t() | nil,
            kind: :confirm | :text | :choice | :multi,
            prompt: String.t(),
            question: map(),
            requested_at: DateTime.t(),
            options: [String.t()],
            choices: [term()],
            allow_other: boolean(),
            default: term()
          }
  end

  @doc "The OS's Oh-My-Jido runtime name; its sessions use `Elixos.Approvals.Host`."
  @spec runtime() :: atom()
  def runtime, do: @runtime

  @doc """
  Starts the index. In normal mode it also starts the OS's `Elixos.Coding`
  Oh-My-Jido runtime as a non-critical service; rescue starts neither.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    if Keyword.get(opts, :mode, :normal) == :rescue,
      do: :ignore,
      else: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Open requests, oldest first."
  @spec pending() :: [Request.t()] | {:error, :not_running}
  def pending, do: call(:pending)

  @doc """
  Subscribes the caller and returns the current requests. Later snapshots
  arrive as `{:elixos_approvals, requests}`; exiting removes the view.
  """
  @spec subscribe() :: {:ok, [Request.t()]} | {:error, :not_running}
  def subscribe, do: call({:subscribe, self()})

  @doc "Approves an effect or confirms a yes/no question."
  @spec approve(pos_integer()) :: :ok | {:error, term()}
  def approve(id) when is_integer(id), do: call({:answer, id, :approve})

  @doc "Denies an effect. The waiting operation gets `{:error, :approval_denied}`."
  @spec deny(pos_integer()) :: :ok | {:error, term()}
  def deny(id) when is_integer(id), do: call({:answer, id, :deny})

  @doc """
  Answers a request with a value checked against it: a boolean for `:confirm`,
  one offered option (or text when allowed) for `:choice`, a non-empty subset of
  the options for `:multi`, a string for `:text`.
  """
  @spec answer(pos_integer(), term()) :: :ok | {:error, term()}
  def answer(id, value) when is_integer(id), do: call({:answer, id, {:value, value}})

  @doc false
  # Called by Elixos.Approvals.Host from Oh-My-Jido's supervised question task.
  @spec track(OhMyJido.Context.t(), map()) :: :ok | {:error, :not_running}
  def track(%OhMyJido.Context{} = context, question), do: call({:track, context, question})

  defp call(message) do
    GenServer.call(__MODULE__, message, 30_000)
  catch
    :exit, _reason -> {:error, :not_running}
  end

  @impl true
  def init(opts) do
    state = %{
      next: 1,
      requests: %{},
      sessions: %{},
      views: %{},
      runtime: Keyword.get(opts, :runtime, true)
    }

    {:ok, state, {:continue, :runtime}}
  end

  @impl true
  def handle_continue(:runtime, %{runtime: false} = state), do: {:noreply, state}

  def handle_continue(:runtime, state) do
    # The runtime is a service, not a dependency of the prompt: a failure is
    # logged and IEx still comes up. Sessions keep their checkpoints on disk so
    # they can be resumed after a reboot; no old question is revived by that.
    spec =
      {OhMyJido,
       name: @runtime,
       host: {Elixos.Approvals.Host, []},
       storage: {Jido.Storage.File, path: storage_dir()},
       question_timeout_ms: Application.get_env(:elixos, :approval_timeout_ms, 3_600_000)}

    with :ok <- File.mkdir_p(storage_dir()),
         {:ok, _pid} <- DynamicSupervisor.start_child(Elixos.Package.Services, spec) do
      :ok
    else
      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("approvals: coding runtime unavailable: #{inspect(reason)}")
    end

    {:noreply, state}
  rescue
    error ->
      Logger.error("approvals: coding runtime unavailable: #{Exception.message(error)}")
      {:noreply, state}
  end

  @impl true
  def handle_call(:pending, _from, state), do: {:reply, ordered(state), state}

  def handle_call({:subscribe, pid}, _from, state) do
    ref = Process.monitor(pid)
    {:reply, {:ok, ordered(state)}, %{state | views: Map.put(state.views, ref, pid)}}
  end

  def handle_call({:track, context, question}, _from, state) do
    {state, session} = track_session(state, context)
    {:reply, :ok, sync(state, session, question)}
  end

  def handle_call({:answer, id, decision}, _from, state) do
    case Enum.find(Map.values(state.requests), &(&1.id == id)) do
      nil ->
        {:reply, {:error, :unknown_request}, state}

      request ->
        with {:ok, value} <- decide(request, decision),
             :ok <- OhMyJido.answer(request.session, request.question_id, value) do
          {:reply, :ok, drop(state, key(request))}
        else
          {:error, :unknown_question} ->
            {:reply, {:error, :unknown_request}, drop(state, key(request))}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  # A history read in sync/3 may already contain an event the relay delivers
  # afterwards; applying it twice could revive an answered question.
  def handle_info({:session_event, sk, %Event{seq: seq} = event}, state) do
    case Map.get(state.sessions, sk) do
      %{seq: seen} = session when seq > seen ->
        state = put_in(state.sessions[sk], %{session | seq: seq})
        {:noreply, apply_event(state, session, event)}

      _stale_or_unknown ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if Map.has_key?(state.views, ref) do
      {:noreply, %{state | views: Map.delete(state.views, ref)}}
    else
      case Enum.find(state.sessions, fn {_sk, session} -> session.monitor == ref end) do
        nil ->
          {:noreply, state}

        {sk, session} ->
          # A session that is gone cannot receive an answer; Oh-My-Jido
          # withdraws its questions and none of them becomes an approval.
          Process.unlink(session.relay)
          Process.exit(session.relay, :kill)
          state = drop_session(state, sk)
          {:noreply, %{state | sessions: Map.delete(state.sessions, sk)}}
      end
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp drop_session(state, sk) do
    keys = for {{^sk, _question} = key, _request} <- state.requests, do: key
    Enum.reduce(keys, state, &drop(&2, &1))
  end

  defp apply_event(state, session, %Event{kind: :approval_requested} = event),
    do: add(state, session, event)

  defp apply_event(state, session, %Event{kind: :approval_answered, payload: payload}),
    do: drop(state, {session.ref, payload[:id]})

  # Cancelling or finishing a run rejects every waiting question of the
  # session without an :approval_answered event; withdraw them here too.
  defp apply_event(state, session, %Event{kind: kind})
       when kind in [:cancellation_requested, :run_completed],
       do: drop_session(state, session.ref)

  defp apply_event(state, _session, _event), do: state

  # Events do not name their runtime, and two runtimes may reuse a session id.
  # One relay per session tags its events with the full session reference.
  defp track_session(state, context) do
    sk = %SessionRef{runtime: context.runtime, id: context.session_id}

    case Map.get(state.sessions, sk) do
      nil ->
        index = self()

        relay =
          spawn_link(fn ->
            _ = OhMyJido.subscribe(sk, self())
            send(index, {:relay_ready, self()})
            relay(index, sk)
          end)

        receive do
          {:relay_ready, ^relay} -> :ok
        after
          5_000 -> :ok
        end

        monitor = if is_pid(context.coordinator), do: Process.monitor(context.coordinator)
        session = %{ref: sk, monitor: monitor, relay: relay, seq: -1}
        {%{state | sessions: Map.put(state.sessions, sk, session)}, session}

      session ->
        {state, session}
    end
  end

  defp relay(index, sk) do
    receive do
      {:oh_my_jido, event} -> send(index, {:session_event, sk, event})
    end

    relay(index, sk)
  end

  # The request was emitted before the host callback ran, so read the bounded
  # history and apply, in order and exactly once, every event the relay has not
  # delivered yet. Live events at or below that sequence are then ignored.
  defp sync(state, session, _question) do
    current = Map.fetch!(state.sessions, session.ref)

    case OhMyJido.events(session.ref, after: max(current.seq, 0)) do
      events when is_list(events) ->
        events
        |> Enum.filter(&(&1.seq > current.seq))
        |> Enum.sort_by(& &1.seq)
        |> Enum.reduce(state, fn event, state ->
          seen = state.sessions[session.ref]
          state = put_in(state.sessions[session.ref], %{seen | seq: event.seq})
          apply_event(state, seen, event)
        end)

      {:error, reason} ->
        Logger.warning("approvals: cannot read session history: #{inspect(reason)}")
        state
    end
  end

  defp add(state, session, %Event{payload: %{id: question_id, question: question}} = event) do
    key = {session.ref, question_id}

    if Map.has_key?(state.requests, key) do
      state
    else
      request =
        question
        |> describe()
        |> Map.merge(%{
          id: state.next,
          session: session.ref,
          session_id: event.session_id,
          question_id: question_id,
          run_id: event.run_id,
          question: question,
          requested_at: DateTime.from_unix!(event.at_ms, :millisecond)
        })
        |> then(&struct!(Request, &1))

      Logger.notice(
        "approvals: request #{request.id} (#{request.kind}) from session #{request.session_id}: #{request.prompt}"
      )

      %{state | next: state.next + 1, requests: Map.put(state.requests, key, request)}
      |> notify()
    end
  end

  defp add(state, _session, _event), do: state

  defp drop(state, key) do
    if Map.has_key?(state.requests, key),
      do: notify(%{state | requests: Map.delete(state.requests, key)}),
      else: state
  end

  defp key(request), do: {request.session, request.question_id}

  defp ordered(state), do: state.requests |> Map.values() |> Enum.sort_by(& &1.id)

  defp notify(state) do
    snapshot = ordered(state)
    for {_ref, pid} <- state.views, do: send(pid, {:elixos_approvals, snapshot})
    state
  end

  @doc false
  # The library's question shapes: effect approvals carry `kind: :effect`;
  # the Question tool carries `question`, `options` and `multi`.
  @spec describe(map()) :: map()
  def describe(%{kind: :effect} = question) do
    effect = Map.get(question, :effect, %{})
    capability = Map.get(question, :capability) || Map.get(effect, :capability)
    operation = Map.get(effect, :operation) || Map.get(effect, :tool) || Map.get(effect, :kind)

    prompt =
      [capability, operation]
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(": ", &to_string/1)
      |> case do
        "" -> "Approve this effect?"
        text -> "Approve #{text}?"
      end

    %{kind: :confirm, prompt: prompt, options: [], choices: [], default: false}
  end

  def describe(%{question: text} = question) when is_binary(text) do
    choices = Map.get(question, :options, [])
    labels = Enum.map(choices, &label/1)

    kind =
      cond do
        choices == [] -> :text
        Map.get(question, :multi, false) -> :multi
        true -> :choice
      end

    %{kind: kind, prompt: text, options: labels, choices: choices, default: nil}
  end

  def describe(question),
    do: %{
      kind: :confirm,
      prompt: "Approve #{inspect(question, limit: 8)}?",
      options: [],
      choices: []
    }

  defp label(%{label: label}) when is_binary(label), do: label
  defp label(%{"label" => label}) when is_binary(label), do: label
  defp label(%{value: value}) when is_binary(value), do: value
  defp label(%{"value" => value}) when is_binary(value), do: value
  defp label(option) when is_binary(option), do: option
  defp label(option), do: inspect(option, limit: 8)

  @doc false
  # Converts a front-end decision into the exact value Oh-My-Jido receives.
  @spec decide(Request.t(), :approve | :deny | {:value, term()}) ::
          {:ok, term()} | {:error, :invalid_answer}
  def decide(%Request{kind: :confirm}, :approve), do: {:ok, true}
  def decide(%Request{kind: :confirm}, :deny), do: {:ok, :deny}
  def decide(%Request{kind: :confirm}, {:value, true}), do: {:ok, true}
  def decide(%Request{kind: :confirm}, {:value, false}), do: {:ok, :deny}

  def decide(%Request{kind: :text}, {:value, text}) when is_binary(text) and text != "",
    do: {:ok, text}

  def decide(%Request{kind: :choice} = request, {:value, label}) when is_binary(label) do
    case Enum.find_index(request.options, &(&1 == label)) do
      nil -> if request.allow_other, do: {:ok, label}, else: {:error, :invalid_answer}
      index -> {:ok, Enum.at(request.choices, index)}
    end
  end

  def decide(%Request{kind: :multi} = request, {:value, labels})
      when is_list(labels) and labels != [] do
    indexes = Enum.map(labels, fn label -> Enum.find_index(request.options, &(&1 == label)) end)

    if Enum.any?(indexes, &is_nil/1) or length(Enum.uniq(labels)) != length(labels),
      do: {:error, :invalid_answer},
      else: {:ok, Enum.map(indexes, &Enum.at(request.choices, &1))}
  end

  def decide(_request, _decision), do: {:error, :invalid_answer}

  defp storage_dir,
    do: Path.join(Application.get_env(:elixos, :priv_dir, "/priv"), "coding/sessions")
end
