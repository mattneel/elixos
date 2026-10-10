defmodule Elixos.Boot.Recorder do
  @moduledoc """
  Records what the login REPL defines into the image (M6, ADR-005).

  The login IEx evaluates with a compilation tracer in its environment, and
  that tracer is this module: for every module defined at a prompt it hands the
  module and its exact bytecode to `Elixos.Image.record/3`, which stores the
  blob and journals the change before anything else happens. Nothing typed is
  ever lost, saved or not.

  Tracing runs inside the compiler, so `trace/2` does as little as possible
  synchronously: it casts to this server, which owns the image.

  Known limitation (reviewed against Elixir 1.20.4's IEx). A console interrupt
  (Ctrl+C, ADR-024) makes `IEx.Server` kill its evaluator and start a
  replacement with `rerun(state, [], ...)`. That path keeps only
  `evaluator_options = Keyword.take(opts, [:dot_iex])` (server.ex:363), and a
  replacement evaluator takes its environment from `opts[:env] ||
  Code.env_for_eval(file: "iex")` (evaluator.ex:256), so the traced env does
  not survive. Modules defined *after* an interrupt are therefore not
  journaled - and in-memory bytecode has no other source (`code.get_object_code/1`
  has nothing to read for a module that was never written to disk), so
  `Elixos.save/1` cannot see them either. Definitions before an interrupt, and
  everything in a session that was never interrupted, record normally.
  DECISIONS.md Q10 tracks the fix (a small patch to the pinned Elixir).
  """

  use GenServer

  alias Elixos.Image
  alias Elixos.Image.Capture

  @doc "Starts the recorder for `image`, linked to the caller."
  def start_link(image) do
    GenServer.start_link(__MODULE__, image, name: __MODULE__)
  end

  @doc """
  The compilation tracer (Elixir calls back into this module): a module defined
  in a traced evaluation is recorded in the image.
  """
  def trace({:on_module, bytecode, _ignore}, _env) do
    case Capture.module_of(bytecode) do
      # A *rejected* redefinition gets this far: Elixir traces the module
      # after compiling it, and only the load fails (the base is sticky, or a
      # conflict was refused). Recording base bytecode would put it in the
      # working set, and the next save would write a generation that cannot
      # boot - and every later save would carry it too.
      {:ok, module} ->
        if not :code.is_sticky(module) do
          GenServer.cast(__MODULE__, {:record, module, bytecode})
        end

      :error ->
        :ok
    end

    :ok
  end

  def trace(_event, _env), do: :ok

  @doc """
  Waits until every module traced so far has been recorded.

  `Elixos.save/1` calls this first: recording is asynchronous (tracing must not
  slow the compiler down), so without it a `defmodule` and a `save` typed in
  quick succession could race.
  """
  def sync, do: GenServer.call(__MODULE__, :sync, :infinity)

  @impl true
  def init(image), do: {:ok, image}

  @impl true
  def handle_call(:sync, _from, image), do: {:reply, :ok, image}

  @impl true
  def handle_cast({:record, module, bytecode}, image) do
    # A failed record must not take the recorder down: the prompt is more
    # important than the image, and the journal is what recovery reads.
    _ = Image.record(image, module, bytecode)
    {:noreply, image}
  end

  @doc false
  # The environment a traced evaluation needs (see Elixos.Image.Capture).
  def traced_env(opts \\ []) do
    %{Code.env_for_eval(opts) | tracers: [__MODULE__]}
  end
end
