defmodule Elixos.Oban.Manager do
  @moduledoc """
  The scheduler's lifecycle (M19, ADR-057).

  Startup is asynchronous and never boot-critical: wait for M18's Postgres,
  start `Elixos.Oban.Repo`, run Oban's migrations once, then wait for
  `Elixos.Oban.activate/0` before any queue exists. The wait is what keeps a
  job from running against a half-restored image: the manager starts before
  `Elixos.Boot.Restore`, and activation comes after the supervision tree is up.

  Declarations arrive from two places - a generation's `configure_app!/2`
  boot MFAs, and a package install or removal at the prompt. A declaration is
  validated and merged before anything is applied; conflicts are refused, so
  two apps cannot silently overwrite each other's queue limits. Live changes
  go to the real queues through Oban's own API; a cron change restarts the
  Oban supervisor with the new plugin list while the Repo stays up.

  Nothing here is a scheduler fallback: in rescue, or when Postgres never came
  up, `status/0` is `{:error, :not_running}` and no queue exists. The manager
  does not restart a failed scheduler on its own.

  Under the deck profile (ADR-111) Postgres starts on first use, so the
  manager waits for it without a deadline and without starting it; a caller
  that needs the scheduler (`status/0`, `enqueue/3`) is such a first use.
  """

  use GenServer

  require Logger

  alias Elixos.Oban.{Declaration, Migration}

  @default_queue_limit 10
  @postgres_timeout_ms 120_000
  @poll_ms 200
  @await_timeout_ms 120_000
  @stop_timeout_ms 30_000

  @phases [:waiting_postgres, :migrating, :pending_activation]

  @doc """
  Starts the manager. `:mode` is required (`:normal` or `:rescue`).

  `:startup_timeout` bounds the wait for Postgres (default two minutes);
  `:repo` and `:oban` name the connection module and the Oban instance.
  `:profile` (`:full` by default, or `:deck`) is the image profile; see the
  moduledoc.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :manager, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    state = %{
      mode: Keyword.fetch!(opts, :mode),
      phase: :rescue,
      activated: false,
      declarations: %{},
      running: %{},
      profile: Keyword.get(opts, :profile, :full),
      cron: [],
      postgres_timeout: Keyword.get(opts, :startup_timeout, @postgres_timeout_ms),
      repo: Keyword.get(opts, :repo, Elixos.Oban.Repo),
      repo_pid: nil,
      repo_ref: nil,
      oban: Keyword.get(opts, :oban, Oban),
      oban_pid: nil,
      oban_ref: nil,
      waiters: []
    }

    case state.mode do
      :rescue ->
        {:ok, state}

      :normal ->
        # The wait for Postgres runs in an unlinked task: the manager must
        # answer boot-time configure_app!/2 calls (and status/0, which may
        # wait) while the database is still coming up.
        {:ok, %{state | phase: :waiting_postgres}, {:continue, :start}}
    end
  end

  @impl true
  def handle_continue(:start, state) do
    manager = self()

    {profile, timeout} = {state.profile, state.postgres_timeout}

    Task.start(fn ->
      case await_postgres(profile, timeout) do
        :ok -> send(manager, :postgres_ready)
        {:error, reason} -> send(manager, {:startup_failed, {:postgres, reason}})
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, %{phase: :running} = state) do
    {:reply, {:ok, state.oban_pid}, state}
  end

  def handle_call(:status, from, %{phase: phase} = state) when phase in @phases do
    {:noreply, wait(state, from, :status)}
  end

  def handle_call(:status, _from, state), do: {:reply, {:error, :not_running}, state}

  def handle_call(:await_instance, _from, %{phase: :running} = state) do
    {:reply, {:ok, state.oban}, state}
  end

  def handle_call(:await_instance, from, %{phase: phase} = state) when phase in @phases do
    {:noreply, wait(state, from, :instance)}
  end

  def handle_call(:await_instance, _from, state), do: {:reply, {:error, :not_running}, state}

  def handle_call(:activate, _from, state) do
    {:reply, :ok, activated(state)}
  end

  def handle_call({:configure_app, app, declaration}, _from, state) do
    with :ok <- Declaration.validate(declaration),
         declarations = put_declaration(state.declarations, app, declaration),
         {:ok, _queues} <- Declaration.merge_queues(Map.values(declarations)) do
      {:reply, :ok, apply_live(%{state | declarations: declarations})}
    else
      {:error, :invalid} -> {:reply, {:error, :invalid}, state}
      {:error, {:conflict, name}} -> {:reply, {:error, {:conflict, name}}, state}
    end
  end

  @impl true
  def handle_cast(:activate, state), do: {:noreply, activated(state)}

  @impl true
  def handle_info(:postgres_ready, state) do
    case start_repo(state) do
      {:ok, pid, ref} -> {:noreply, migrate(%{state | repo_pid: pid, repo_ref: ref})}
      {:error, reason} -> {:noreply, fail(state, {:repo, reason})}
    end
  end

  def handle_info({:startup_failed, reason}, state), do: {:noreply, fail(state, reason)}

  def handle_info(:migrated, state) do
    state = %{state | phase: :pending_activation}

    if state.activated do
      {:noreply, start_scheduler(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:migration_failed, reason}, state), do: {:noreply, fail(state, reason)}

  def handle_info({:await_timeout, token}, state) do
    {expired, waiting} = Enum.split_with(state.waiters, &(elem(&1, 0) == token))

    for {_token, from, _timer, _kind} <- expired do
      GenServer.reply(from, {:error, :not_running})
    end

    {:noreply, %{state | waiters: waiting}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    cond do
      ref == state.repo_ref -> {:noreply, fail(%{state | repo_pid: nil, repo_ref: nil}, {:repo, reason})}
      ref == state.oban_ref -> {:noreply, fail(%{state | oban_pid: nil, oban_ref: nil}, {:oban, reason})}
      true -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  ## Startup

  # ADR-111: the deck's Postgres starts on its first use, whenever that is.
  defp await_postgres(:deck, _timeout), do: Elixos.Postgres.await_started()

  defp await_postgres(:full, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_postgres_deadline(deadline)
  end

  defp await_postgres_deadline(deadline) do
    case Elixos.Postgres.status() do
      {:ok, _pid} ->
        :ok

      {:error, :not_running} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(@poll_ms)
          await_postgres_deadline(deadline)
        end
    end
  end

  defp start_repo(state) do
    case state.repo.start_link(state.repo.connection_options()) do
      {:ok, pid} -> {:ok, pid, Process.monitor(pid)}
      # A previous incarnation's Repo may still be alive (a manager restart):
      # one pool per VM, adopted rather than duplicated.
      {:error, {:already_started, pid}} -> {:ok, pid, Process.monitor(pid)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp migrate(state) do
    %{state | phase: :migrating}
    |> tap(fn state ->
      manager = self()

      Task.start(fn ->
        result =
          try do
            Ecto.Migrator.up(state.repo, Migration.version(), Migration, log: false)
          rescue
            error -> {:error, error}
          end

        case result do
          result when result in [:ok, :already_up] -> send(manager, :migrated)
          {:error, reason} -> send(manager, {:migration_failed, {:migration, reason}})
        end
      end)
    end)
  end

  defp start_scheduler(state) do
    queues = effective_queues(state.declarations)
    cron = Declaration.merge_cron(Map.values(state.declarations))

    options = [
      name: state.oban,
      repo: state.repo,
      queues: Enum.sort(queues),
      plugins: plugin_options(cron)
    ]

    case Oban.start_link(options) do
      {:ok, pid} ->
        Logger.info("oban: scheduler started, queues #{inspect(Map.keys(queues))}")
        state = %{state | phase: :running, oban_pid: pid, oban_ref: Process.monitor(pid), running: queues, cron: cron}
        release(state, &{:ok, result(&1, state)})

      {:error, {:already_started, pid}} ->
        state = %{state | phase: :running, oban_pid: pid, oban_ref: Process.monitor(pid), running: queues, cron: cron}
        release(state, &{:ok, result(&1, state)})

      {:error, reason} ->
        fail(state, {:oban, reason})
    end
  end

  ## Live configuration

  defp put_declaration(declarations, app, []), do: Map.delete(declarations, app)
  defp put_declaration(declarations, app, declaration), do: Map.put(declarations, app, declaration)

  defp effective_queues(declarations) do
    {:ok, merged} = Declaration.merge_queues(Map.values(declarations))
    Map.put_new(merged, :default, @default_queue_limit)
  end

  defp plugin_options([]), do: []
  defp plugin_options(cron), do: [{Oban.Plugins.Cron, crontab: cron}]

  defp apply_live(%{phase: :running} = state) do
    state = diff_queues(state, effective_queues(state.declarations))
    cron = Declaration.merge_cron(Map.values(state.declarations))

    if cron == state.cron do
      state
    else
      restart_scheduler(%{state | cron: cron})
    end
  end

  defp apply_live(state), do: state

  defp diff_queues(state, desired) do
    Enum.each(desired, fn {name, limit} ->
      case Map.fetch(state.running, name) do
        {:ok, ^limit} ->
          :ok

        {:ok, _changed} ->
          stop_queue(state, name)
          start_queue(state, name, limit)

        :error ->
          start_queue(state, name, limit)
      end
    end)

    for {name, _limit} <- state.running, not Map.has_key?(desired, name) do
      stop_queue(state, name)
    end

    %{state | running: desired}
  end

  defp start_queue(state, name, limit) do
    case Oban.start_queue(state.oban, queue: name, limit: limit) do
      :ok ->
        :ok

      {:error, error} ->
        Logger.error("oban: cannot start queue #{inspect(name)} (#{Exception.message(error)})")
    end
  end

  defp stop_queue(state, name) do
    case Oban.stop_queue(state.oban, queue: name) do
      :ok -> :ok
      {:error, error} -> Logger.error("oban: cannot stop queue #{inspect(name)} (#{Exception.message(error)})")
    end
  end

  # Cron is plugin configuration, fixed when the supervisor starts; the
  # honest live change is a real restart with the new list. The Repo stays
  # up, so no connection or migration is redone.
  defp restart_scheduler(state) do
    Logger.info("oban: restarting for a cron change")

    if is_pid(state.oban_pid) do
      ref = state.oban_ref
      Supervisor.stop(state.oban_pid, :normal, @stop_timeout_ms)
      if ref, do: Process.demonitor(ref, [:flush])
    end

    start_scheduler(%{state | phase: :pending_activation, oban_pid: nil, oban_ref: nil})
  end

  ## Answers

  defp activated(state) do
    state = %{state | activated: true}

    if state.phase == :pending_activation do
      start_scheduler(state)
    else
      state
    end
  end

  defp wait(state, from, kind) do
    # A caller waiting for the scheduler needs the database: on the deck that
    # is a first use (a no-op once Postgres has started).
    if state.profile == :deck, do: Elixos.Postgres.ensure_started()

    token = make_ref()
    timer = Process.send_after(self(), {:await_timeout, token}, @await_timeout_ms)
    %{state | waiters: state.waiters ++ [{token, from, timer, kind}]}
  end

  defp release(state, reply) do
    for {_token, from, timer, kind} <- state.waiters do
      Process.cancel_timer(timer)
      GenServer.reply(from, reply.(kind))
    end

    %{state | waiters: []}
  end

  defp result(:status, state), do: state.oban_pid
  defp result(:instance, state), do: state.oban

  defp fail(state, reason) do
    Logger.error("oban: scheduler unavailable (#{inspect(reason)})")

    state
    |> Map.merge(%{phase: :failed, oban_pid: nil, oban_ref: nil})
    |> release(fn _kind -> {:error, :not_running} end)
  end
end
