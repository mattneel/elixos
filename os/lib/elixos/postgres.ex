defmodule Elixos.Postgres do
  @moduledoc """
  The system PostgreSQL (M18, docs/ROADMAP.md).

  Postgres ships with the machine, in the read-only system image on `/system`,
  and runs as the `postgres` uid - never as root - through M17's shim helper
  allow-list. Nothing here is boot-critical: startup runs in a monitored worker,
  and a failed start leaves the manager available without restarting helpers.
  Rescue starts neither the initialization helper nor the server.

  Initialization waits for the actual helper process to exit, then readiness
  requires a successful SQL connection. The shim may reap initdb before its exit
  status can be observed; readiness, not disappearance of that PID, establishes
  success. A postmaster's PID and Linux start time identify it for its lifetime.

  On `Elixos.poweroff/0` or `Elixos.halt/0`, the shim stops Postgres cleanly
  after the BEAM. This manager does not stop the server during VM shutdown, so
  applications can keep using their database until the VM stops.

  `start_link/1` accepts `:mode` (`:normal` or `:rescue`), `:name` (this module
  by default; nil leaves it unregistered), and `:privileges` (the existing helper
  client). Startup is bounded to 105 seconds, including helper replies, a
  60-second initialization wait and a 30-second SQL-readiness wait.

  `:profile` is the image profile (ADR-111, `Elixos.Boot.Cmdline.profile/0`).
  Under `:full`, the default, normal mode starts the server at once. Under
  `:deck`, normal mode starts nothing at boot: the first `query/1` (or
  `ensure_started/0`, which `Elixos.Oban` calls for its own first use) starts
  it through the same worker, and `status/0` stays `{:error, :not_running}`
  until then.
  """

  use GenServer, restart: :temporary

  alias Elixos.{Privileges, Session}

  require Logger

  @psql "/system/usr/libexec/postgresql17/psql"
  @startup_timeout_ms 105_000
  @init_timeout_ms 60_000
  @ready_timeout_ms 30_000
  @probe_timeout_ms 5_000
  @poll_ms 50
  @child_env [
    {"LD_LIBRARY_PATH", "/system/lib:/system/usr/lib:/system/usr/lib/postgresql17"},
    {"PATH", "/system/usr/libexec/postgresql17:/system/usr/bin:/usr/bin:/bin"},
    {"PGCONNECT_TIMEOUT", "3"},
    {"PGHOSTADDR", "127.0.0.1"},
    {"PGSERVICE", nil}
  ]

  @doc "Starts the non-critical service manager without waiting for PostgreSQL."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  The ready, live server: `{:ok, pid}` with its positive UNIX PID, not a BEAM
  PID, or `{:error, :not_running}`. Starting, failed and rescue services are
  not running. A dead or reused PID is never reported as the postmaster.
  """
  @spec status() :: {:ok, pos_integer()} | {:error, :not_running}
  def status, do: call(:status)

  @doc """
  Runs `sql` (one or more statements) directly through `psql`.

  Waits for bounded startup if necessary, then executes the user's SQL exactly
  once in the caller's session directory. It prints the command's output to
  that session and returns the same bytes, including successful command tags.
  SQL and connection failures return `{:error, {:psql, exit_status, output}}`,
  including stderr. Execution failures return `{:error, {:exec, reason}}`.
  Startup failures return `{:error, {:startup_failed, reason}}`; rescue, a
  missing manager, or a dead server returns `{:error, :not_running}`.

  This is the prompt's interface to the database, not a wire client. SQL itself
  has no execution timeout: cancelling or retrying it could obscure effects
  already committed by the server. It never runs inside the manager.
  """
  @spec query(String.t()) :: {:ok, String.t()} | {:error, term()}
  def query(sql) when is_binary(sql) do
    with :ok <- call(:await_ready) do
      run_sql(sql, session_dir())
    end
  end

  @doc """
  Starts a deck-profile server that has not started yet, without waiting for
  it; any other server is left as it is. Always `:ok`.
  """
  @spec ensure_started() :: :ok
  def ensure_started, do: GenServer.cast(__MODULE__, :start)

  @doc """
  Waits until the server is ready, without starting it: `:ok`, or the error
  `query/1` would return. A deck-profile server that has not started keeps the
  caller waiting for whoever starts it; `Elixos.Oban` follows the database so.
  """
  @spec await_started() :: :ok | {:error, term()}
  def await_started, do: call(:await_started)

  defp call(message) do
    GenServer.call(__MODULE__, message, :infinity)
  catch
    :exit, _reason -> {:error, :not_running}
  end

  @impl true
  def init(opts) do
    state = %{phase: :rescue, worker: nil, timer: nil, waiters: [], postmaster: nil, error: nil}

    case Keyword.fetch!(opts, :mode) do
      :rescue ->
        {:ok, state}

      :normal ->
        privileges = Keyword.get(opts, :privileges, Privileges)

        case Keyword.get(opts, :profile, :full) do
          :full ->
            send(self(), {:start, privileges})
            {:ok, %{state | phase: :starting}}

          # ADR-111: on the deck the first use starts the server.
          :deck ->
            {:ok, Map.merge(state, %{phase: :idle, privileges: privileges})}
        end
    end
  end

  @impl true
  def handle_call(:status, _from, %{phase: :ready} = state) do
    if live?(state.postmaster) do
      {pid, _start_time} = state.postmaster
      {:reply, {:ok, pid}, state}
    else
      {:reply, {:error, :not_running}, stopped(state)}
    end
  end

  def handle_call(:status, _from, state),
    do: {:reply, {:error, :not_running}, state}

  def handle_call(:await_ready, from, %{phase: :idle} = state),
    do: handle_call(:await_ready, from, start(state))

  def handle_call(:await_ready, from, %{phase: :starting} = state),
    do: {:noreply, %{state | waiters: [from | state.waiters]}}

  def handle_call(:await_ready, _from, %{phase: :ready} = state) do
    if live?(state.postmaster) do
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_running}, stopped(state)}
    end
  end

  def handle_call(:await_ready, _from, %{phase: :failed, error: reason} = state),
    do: {:reply, {:error, {:startup_failed, reason}}, state}

  def handle_call(:await_ready, _from, state),
    do: {:reply, {:error, :not_running}, state}

  # Oban waits on a deck-profile server without being its first use.
  def handle_call(:await_started, from, %{phase: :idle} = state),
    do: {:noreply, %{state | waiters: [from | state.waiters]}}

  def handle_call(:await_started, from, state), do: handle_call(:await_ready, from, state)

  @impl true
  def handle_cast(:start, %{phase: :idle} = state), do: {:noreply, start(state)}
  def handle_cast(:start, state), do: {:noreply, state}

  @impl true
  def handle_info({:start, privileges}, %{phase: :starting, worker: nil} = state) do
    owner = self()

    {worker, monitor} =
      spawn_monitor(fn ->
        send(owner, {:startup_result, self(), start_server(privileges)})
      end)

    timer = Process.send_after(self(), {:startup_timeout, worker}, @startup_timeout_ms)
    {:noreply, %{state | worker: {worker, monitor}, timer: timer}}
  end

  def handle_info({:startup_result, worker, result}, %{worker: {worker, _monitor}} = state) do
    case result do
      {:ok, postmaster} ->
        if live?(postmaster) do
          state = finish_worker(state, :ok)
          {:noreply, %{state | phase: :ready, postmaster: postmaster}}
        else
          {:noreply, failed(state, :postmaster_exited)}
        end

      {:error, reason} ->
        {:noreply, failed(state, reason)}
    end
  end

  def handle_info({:startup_timeout, worker}, %{worker: {worker, _monitor}} = state) do
    Process.exit(worker, :kill)
    {:noreply, failed(state, :timeout)}
  end

  def handle_info(
        {:DOWN, monitor, :process, worker, reason},
        %{worker: {worker, monitor}} = state
      ),
      do: {:noreply, failed(state, {:startup_worker, reason})}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{worker: {worker, _monitor}}) do
    Process.exit(worker, :kill)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp finish_worker(state, reply) do
    {_worker, monitor} = state.worker
    Process.demonitor(monitor, [:flush])
    Process.cancel_timer(state.timer)
    Enum.each(state.waiters, &GenServer.reply(&1, reply))
    %{state | worker: nil, timer: nil, waiters: []}
  end

  defp failed(state, reason) do
    Logger.error("postgres: startup failed: #{inspect(reason)}")
    state = finish_worker(state, {:error, {:startup_failed, reason}})
    %{state | phase: :failed, error: reason}
  end

  defp stopped(state), do: %{state | phase: :stopped, postmaster: nil}

  # A deck-profile server's first use: the same start a full boot sends itself.
  defp start(state) do
    send(self(), {:start, state.privileges})
    %{state | phase: :starting}
  end

  defp start_server(privileges) do
    with {:ok, init_pid} <- helper(privileges, "postgres-init"),
         :ok <- wait_for_init(init_pid, nil, deadline(@init_timeout_ms)),
         {:ok, pid} <- helper(privileges, "postgres"),
         {:ok, %{start_time: start_time, state: proc_state}} <- process_info(pid),
         true <- proc_state not in ["Z", "X", "x"],
         postmaster = {pid, start_time},
         :ok <- wait_for_sql(postmaster, deadline(@ready_timeout_ms), nil) do
      {:ok, postmaster}
    else
      false -> {:error, :postmaster_exited}
      {:error, reason} -> {:error, reason}
    end
  end

  defp helper(privileges, name) do
    case Privileges.request(privileges, name) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, {:helper, name, reason}}
    end
  end

  defp wait_for_init(pid, expected_start_time, until) do
    case process_info(pid) do
      {:ok, %{start_time: start_time}}
      when not is_nil(expected_start_time) and start_time != expected_start_time ->
        :ok

      {:ok, %{state: state, exit_code: exit_code}} when state in ["Z", "X", "x"] ->
        if exit_code == 0, do: :ok, else: {:error, {:init_exit, exit_code}}

      {:ok, %{start_time: start_time}} ->
        if remaining(until) > 0 do
          Process.sleep(min(@poll_ms, remaining(until)))
          wait_for_init(pid, start_time, until)
        else
          {:error, :init_timeout}
        end

      {:error, reason} when reason in [:enoent, :esrch] ->
        :ok

      {:error, reason} ->
        {:error, {:init_process, reason}}
    end
  end

  defp wait_for_sql(postmaster, until, last_error) do
    cond do
      not live?(postmaster) ->
        {:error, :postmaster_exited}

      remaining(until) == 0 ->
        {:error, {:readiness_timeout, last_error}}

      true ->
        case probe_sql(min(@probe_timeout_ms, remaining(until))) do
          {:ok, output} ->
            if String.trim(output) == "1" do
              :ok
            else
              {:error, {:readiness_output, output}}
            end

          {:error, {:exec, _reason}} = error ->
            error

          {:error, reason} ->
            Process.sleep(min(@poll_ms, remaining(until)))
            wait_for_sql(postmaster, until, reason)
        end
    end
  end

  defp live?({pid, expected_start_time}) do
    case process_info(pid) do
      {:ok, %{start_time: ^expected_start_time, state: state}} ->
        state not in ["Z", "X", "x"]

      _ ->
        false
    end
  end

  # Linux comm is parenthesized but can itself contain spaces and parentheses.
  # Fields after its final ')' start with state (field 3); starttime is field 22
  # and exit_code is field 52. starttime survives exec and prevents PID reuse.
  defp process_info(pid) do
    with {:ok, stat} <- File.read("/proc/#{pid}/stat"),
         [_ | _] = closers <- :binary.matches(stat, ")"),
         {end_of_comm, 1} = List.last(closers),
         fields =
           stat
           |> binary_part(end_of_comm + 1, byte_size(stat) - end_of_comm - 1)
           |> String.split(),
         state when is_binary(state) <- Enum.at(fields, 0),
         {start_time, ""} <- Integer.parse(Enum.at(fields, 19, "")),
         {exit_code, ""} <- Integer.parse(Enum.at(fields, 49, "")) do
      {:ok, %{state: state, start_time: start_time, exit_code: exit_code}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_proc_stat}
    end
  end

  defp run_sql(sql, dir) do
    {output, status} =
      System.cmd(@psql, arguments(sql), cd: dir, env: @child_env, stderr_to_stdout: true)

    IO.binwrite(output)
    if status == 0, do: {:ok, output}, else: {:error, {:psql, status, output}}
  rescue
    error in [ErlangError, ArgumentError] -> {:error, {:exec, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:exec, reason}}
  end

  # Only the side-effect-free readiness statement can be retried or timed out.
  # Owning its port here also closes it if the startup worker is killed.
  defp probe_sql(timeout_ms) do
    port =
      Port.open({:spawn_executable, String.to_charlist(@psql)}, [
        :binary,
        :use_stdio,
        :stderr_to_stdout,
        :exit_status,
        {:args, arguments("SELECT 1")},
        {:cd, ~c"/"},
        {:env, Enum.map(@child_env, &port_env/1)}
      ])

    collect_probe(port, deadline(timeout_ms), [])
  rescue
    error in [ErlangError, ArgumentError] -> {:error, {:exec, Exception.message(error)}}
  end

  defp collect_probe(port, until, output) do
    receive do
      {^port, {:data, data}} ->
        collect_probe(port, until, [data | output])

      {^port, {:exit_status, status}} ->
        output = output |> Enum.reverse() |> IO.iodata_to_binary()
        if status == 0, do: {:ok, output}, else: {:error, {:psql, status, output}}
    after
      remaining(until) ->
        close_port(port)
        {:error, :probe_timeout}
    end
  end

  defp close_port(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp port_env({key, nil}), do: {String.to_charlist(key), false}
  defp port_env({key, value}), do: {String.to_charlist(key), String.to_charlist(value)}

  defp arguments(sql) do
    [
      "-h",
      "127.0.0.1",
      "-p",
      "5432",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-w",
      "-X",
      "-A",
      "-t",
      "-v",
      "ON_ERROR_STOP=1",
      "-c",
      sql
    ]
  end

  defp session_dir, do: Session.cwd()

  defp deadline(timeout_ms), do: System.monotonic_time(:millisecond) + timeout_ms
  defp remaining(until), do: max(until - System.monotonic_time(:millisecond), 0)
end
