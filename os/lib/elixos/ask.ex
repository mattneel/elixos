defmodule Elixos.Ask do
  @moduledoc """
  Questions are data in the OS; front-ends are only views (M20,
  docs/ROADMAP.md).

  `ask/2` puts a question in a queue and blocks the *asker* until a front-end
  answers it (`answer/2`), dismisses it (`dismiss/1`), it times out, or the
  asker goes away. `pending/0` is what every front-end renders; the console
  REPL is the first one, and it prints one notice line per new question
  (PROTOCOL.md §6):

      elixos-ask: question <id> (<kind>): <prompt>

  Every answer is validated against its question before it is accepted - a
  choice must be one of its options (or free text when the question offered
  it), a multi a non-empty subset of them, a confirm a boolean - so a
  front-end cannot hand back something the question never allowed.

  A question has an `id`, a `kind` (`:text`, `:choice`, `:multi`, `:confirm`),
  the options a choice or multi offers, the asking process, an optional
  `:default` a front-end may offer, and an optional `:timeout` in
  milliseconds. With no timeout a question stays open until it is resolved or
  its asker dies; it is never answered by guesswork.

  The queue is not boot-critical and runs no part of rescue: with no server
  the accessors answer `{:error, :not_running}`.
  """

  use GenServer

  @timeout_message :question_timeout

  defmodule Question do
    @moduledoc """
    One open question: what a front-end renders and what an answer is checked
    against. `id` is unique for the life of the queue.
    """

    defstruct [
      :id,
      :kind,
      :prompt,
      :options,
      :allow_other,
      :default,
      :timeout,
      :asker,
      :asked_at
    ]

    @type t :: %__MODULE__{
            id: pos_integer(),
            kind: :text | :choice | :multi | :confirm,
            prompt: String.t(),
            options: [String.t()],
            allow_other: boolean(),
            default: term(),
            timeout: pos_integer() | nil,
            asker: pid(),
            asked_at: DateTime.t()
          }
  end

  @doc """
  Starts the queue (`:mode` is `:normal` or `:rescue`; rescue starts nothing).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Asks the human a question of `kind` and blocks until it is resolved.

  Options: `:prompt` (required), `:options` (a choice or multi), `:allow_other`
  (offer free text beside those options), `:default`, and `:timeout` in
  milliseconds. Returns `{:ok, answer}`, `{:error, :timeout}`, or
  `{:error, :dismissed}`.
  """
  @spec ask(:text | :choice | :multi | :confirm, keyword()) ::
          {:ok, term()} | {:error, :timeout | :dismissed | :not_running}
  def ask(kind, opts) when kind in [:text, :choice, :multi, :confirm] do
    call({:ask, kind, opts})
  end

  @doc "The open questions, oldest first."
  @spec pending() :: [Question.t()] | {:error, :not_running}
  def pending, do: call(:pending)

  @doc """
  Answers `id` with `value`, which is checked against the question: `:ok`, or
  `{:error, :invalid_answer}` (the question never allowed that answer) or
  `{:error, :unknown_question}` (nothing is open under that id).
  """
  @spec answer(pos_integer(), term()) ::
          :ok | {:error, :invalid_answer | :unknown_question | :not_running}
  def answer(id, value) when is_integer(id), do: call({:answer, id, value})

  @doc "Dismisses `id` without an answer; its asker gets `{:error, :dismissed}`."
  @spec dismiss(pos_integer()) :: :ok | {:error, :unknown_question | :not_running}
  def dismiss(id) when is_integer(id), do: call({:dismiss, id})

  defp call(message) do
    GenServer.call(__MODULE__, message, :infinity)
  catch
    :exit, _reason -> {:error, :not_running}
  end

  @impl true
  def init(opts) do
    case Keyword.get(opts, :mode, :normal) do
      :rescue -> :ignore
      :normal -> {:ok, %{questions: [], next_id: 1, waiters: %{}, monitors: %{}}}
    end
  end

  @impl true
  def handle_call({:ask, kind, opts}, from, state) do
    with :ok <- validate_question(kind, opts) do
      question = new_question(kind, opts, asker(from), state.next_id)
      notice(question)

      state =
        state
        |> Map.update!(:questions, &(&1 ++ [question]))
        |> Map.update!(:next_id, &(&1 + 1))
        |> Map.put(:waiters, Map.put(state.waiters, question.id, from))
        |> Map.put(
          :monitors,
          Map.put(state.monitors, question.id, Process.monitor(question.asker))
        )
        |> schedule_timeout(question, opts)

      {:noreply, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:pending, _from, state), do: {:reply, state.questions, state}

  def handle_call({:answer, id, value}, _from, state) do
    case find(state, id) do
      nil ->
        {:reply, {:error, :unknown_question}, state}

      question ->
        if accepts?(question, value) do
          {:reply, :ok, resolve(state, id, {:ok, value})}
        else
          {:reply, {:error, :invalid_answer}, state}
        end
    end
  end

  def handle_call({:dismiss, id}, _from, state) do
    case find(state, id) do
      nil -> {:reply, {:error, :unknown_question}, state}
      _question -> {:reply, :ok, resolve(state, id, {:error, :dismissed})}
    end
  end

  @impl true
  def handle_info({@timeout_message, id}, state) do
    case find(state, id) do
      nil -> {:noreply, state}
      _question -> {:noreply, resolve(state, id, {:error, :timeout})}
    end
  end

  # The asker is a front-end that must not be left waiting: when it goes away
  # (its session ended, its process was killed) its questions leave the queue,
  # never answered by guesswork.
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    ids = for question <- state.questions, question.asker == pid, do: question.id
    {:noreply, Enum.reduce(ids, state, &drop(&2, &1))}
  end

  def handle_info(_message, state), do: {:noreply, state}

  ## Questions

  defp new_question(kind, opts, asker, id) do
    %Question{
      id: id,
      kind: kind,
      prompt: Keyword.fetch!(opts, :prompt),
      options: Keyword.get(opts, :options, []),
      allow_other: Keyword.get(opts, :allow_other, false),
      default: Keyword.get(opts, :default),
      timeout: Keyword.get(opts, :timeout),
      asker: asker,
      asked_at: DateTime.utc_now()
    }
  end

  defp validate_question(kind, opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, :invalid_question}

      not is_binary(Keyword.get(opts, :prompt)) ->
        {:error, :invalid_question}

      kind in [:choice, :multi] and not valid_options?(Keyword.get(opts, :options)) ->
        {:error, :invalid_question}

      true ->
        :ok
    end
  end

  defp valid_options?(options) when is_list(options) do
    options != [] and Enum.all?(options, &is_binary/1)
  end

  defp valid_options?(_other), do: false

  # An answer is checked against its question, never against whatever a
  # front-end felt like returning.
  defp accepts?(%Question{kind: :text}, value), do: is_binary(value)

  defp accepts?(%Question{kind: :confirm}, value), do: is_boolean(value)

  defp accepts?(%Question{kind: :choice} = question, value) when is_binary(value) do
    value in question.options or question.allow_other
  end

  defp accepts?(%Question{kind: :multi} = question, value) when is_list(value) do
    value != [] and Enum.all?(value, &(&1 in question.options))
  end

  defp accepts?(_question, _value), do: false

  defp find(state, id), do: Enum.find(state.questions, &(&1.id == id))

  defp schedule_timeout(state, question, opts) do
    case Keyword.get(opts, :timeout) do
      timeout when is_integer(timeout) and timeout > 0 ->
        Process.send_after(self(), {@timeout_message, question.id}, timeout)
        state

      _absent ->
        state
    end
  end

  # One resolution: the asker is told (if it is still there), the monitor
  # stops, and the question leaves the queue.
  defp resolve(state, id, reply) do
    state = forget(state, id)

    case Map.pop(state.waiters, id) do
      {nil, waiters} ->
        %{state | waiters: waiters}

      {from, waiters} ->
        GenServer.reply(from, reply)
        %{state | waiters: waiters}
    end
  end

  # The asker is gone; nobody is replied to.
  defp drop(state, id), do: %{forget(state, id) | waiters: Map.delete(state.waiters, id)}

  defp forget(state, id) do
    case Map.pop(state.monitors, id) do
      {nil, _monitors} ->
        state

      {ref, monitors} ->
        Process.demonitor(ref, [:flush])
        %{state | monitors: monitors}
    end
    |> Map.update!(:questions, &Enum.reject(&1, fn question -> question.id == id end))
  end

  defp asker({pid, _tag}), do: pid

  defp notice(%Question{id: id, kind: kind, prompt: prompt}) do
    IO.puts("elixos-ask: question #{id} (#{kind}): #{prompt}")
  end
end
