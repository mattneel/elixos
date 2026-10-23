defmodule Elixos.DeckProfileTest do
  @moduledoc """
  The deck image profile on the BEAM side (ADR-111, M33): `elixos.profile=deck`
  boots with PostgreSQL, Oban and the OS's coding runtime off; the first use of
  the database starts Postgres, and Oban follows it.

  These run the real managers against a fake shim, as
  postgres_lifecycle_test.exs does. The host has no database: a ready server
  is stood in for by a startup result naming this VM's own live UNIX process,
  and Oban's Repo by a module that reports when the scheduler starts it.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 33
  @moduletag :tmp_dir
  @moduletag :capture_log

  alias Elixos.{Approvals, Postgres, Privileges}
  alias Elixos.Boot.Cmdline
  alias Elixos.Shim.Control
  # `Elixos.Oban` would shadow the scheduler library of the same name.
  alias Elixos.Oban, as: Scheduler

  defmodule ReplySource do
    def open(owner) do
      send(owner, {:reply_reader, self()})
      {:ok, owner}
    end

    def read(_owner) do
      receive do
        {:line, line} -> {:ok, line}
      end
    end

    def close(_owner), do: :ok
  end

  # Elixos.Oban.Repo's place: the manager starts it once Postgres is ready.
  defmodule Repo do
    def connection_options, do: []

    def start_link(_opts) do
      send(Elixos.DeckProfileTest, :repo_started)
      Agent.start_link(fn -> nil end)
    end
  end

  setup do
    Process.register(self(), __MODULE__)

    control =
      start_supervised!(
        {Control, name: nil, sink: {Elixos.Test.ProcessSink, self()}, heartbeat_ms: 20}
      )

    assert_receive {:shim_write, "HB\n"}

    privileges =
      start_supervised!({Privileges, name: nil, control: control, source: {ReplySource, self()}})

    assert_receive {:reply_reader, reader}
    {:ok, privileges: privileges, reader: reader}
  end

  # The startup worker a first use spawned, once the manager has admitted it.
  defp worker(server, attempts \\ 1_000)
  defp worker(_server, 0), do: flunk("no startup worker")

  defp worker(server, attempts) do
    case :sys.get_state(server) do
      %{phase: :starting, worker: {worker, _monitor}} -> worker
      _ -> worker(server, attempts - 1)
    end
  end

  # A live UNIX process and its start time, as the manager identifies a
  # postmaster: this VM itself.
  defp live_process do
    pid = String.to_integer(System.pid())
    stat = File.read!("/proc/#{pid}/stat")
    {end_of_comm, 1} = stat |> :binary.matches(")") |> List.last()

    fields =
      stat |> binary_part(end_of_comm + 1, byte_size(stat) - end_of_comm - 1) |> String.split()

    {pid, String.to_integer(Enum.at(fields, 19))}
  end

  defp deck_database(ctx) do
    start_supervised!({Postgres, mode: :normal, profile: :deck, privileges: ctx.privileges})
  end

  test "elixos.profile selects the deck only for exactly deck" do
    assert Cmdline.profile(Cmdline.parse("console=ttyS0 elixos.profile=deck quiet")) == :deck
    assert Cmdline.profile(Cmdline.parse("elixos.profile=full")) == :full
    assert Cmdline.profile(Cmdline.parse("")) == :full
    # A bare flag is not a profile.
    assert Cmdline.profile(Cmdline.parse("elixos.profile")) == :full
    # The last occurrence wins, as for every setting.
    assert Cmdline.profile(Cmdline.parse("elixos.profile=deck elixos.profile=full")) == :full
    assert Cmdline.profile(Cmdline.parse("elixos.profile=full elixos.profile=deck")) == :deck

    for garbage <- ["Deck", "DECK", "decks", "deck,full", "", "1"] do
      assert Cmdline.profile(%{"profile" => garbage}) == :full
    end

    # The zero-arity form reads the running kernel's command line.
    assert Cmdline.profile() == Cmdline.profile(Cmdline.current())
  end

  test "the deck's Postgres starts on first use, not at boot", ctx do
    server = deck_database(ctx)

    refute_receive {:shim_write, "HELPER postgres-init\n"}, 200
    assert :sys.get_state(server).phase == :idle
    assert Postgres.status() == {:error, :not_running}

    # The first query starts the server through the boot's own worker and
    # waits for it, like a query during a full boot's startup.
    query = Task.async(fn -> Postgres.query("select 1") end)
    assert_receive {:shim_write, "HELPER postgres-init\n"}

    send(ctx.reader, {:line, "HELPER postgres-init REFUSED\n"})
    error = {:error, {:startup_failed, {:helper, "postgres-init", :refused}}}
    assert Task.await(query) == error
    # A failed start is final, as in a full boot: no retry on the next use.
    assert Postgres.query("select 2") == error
    refute_received {:shim_write, "HELPER postgres-init\n"}
  end

  test "the deck boots neither database nor scheduler; Oban follows the first query", ctx do
    server = deck_database(ctx)
    start_supervised!({Scheduler, mode: :normal, profile: :deck, repo: Repo})
    # As Elixos.Application does once the tree is up.
    assert Scheduler.activate() == :ok

    refute_receive {:shim_write, "HELPER postgres-init\n"}, 200
    assert :sys.get_state(Elixos.Oban.Manager).phase == :waiting_postgres
    assert :sys.get_state(server).phase == :idle
    refute_received :repo_started

    query = Task.async(fn -> Postgres.query("select 1") end)
    assert_receive {:shim_write, "HELPER postgres-init\n"}
    worker = worker(server)
    refute_received :repo_started

    {pid, _start_time} = postmaster = live_process()
    send(server, {:startup_result, worker, {:ok, postmaster}})

    # The scheduler was waiting on the database, not on a deadline.
    assert_receive :repo_started, 5_000
    assert Postgres.status() == {:ok, pid}
    # The host has no psql: the query ran exactly when the server was ready.
    assert {:error, {:exec, _reason}} = Task.await(query)
  end

  test "the scheduler's own first use starts the deck's database", ctx do
    server = deck_database(ctx)
    start_supervised!({Scheduler, mode: :normal, profile: :deck, repo: Repo})
    refute_receive {:shim_write, "HELPER postgres-init\n"}, 200

    status = Task.async(fn -> Scheduler.status() end)
    assert_receive {:shim_write, "HELPER postgres-init\n"}
    assert :sys.get_state(server).phase == :starting

    # Oban fails with the database it follows, as after a full boot.
    send(ctx.reader, {:line, "HELPER postgres-init REFUSED\n"})
    assert Task.await(status, 5_000) == {:error, :not_running}
    assert :sys.get_state(Elixos.Oban.Manager).phase == :failed
    assert Postgres.status() == {:error, :not_running}
    refute_received :repo_started
  end

  # A user's runtime with the OS host, as approvals_test.exs starts them.
  defp user_session(ctx) do
    runtime = Module.concat(__MODULE__, "UserRuntime")

    start_supervised!(
      {OhMyJido,
       name: runtime,
       host: {Approvals.Host, []},
       storage: {Jido.Storage.File, path: Path.join(ctx.tmp_dir, "sessions")},
       question_timeout_ms: 30_000}
    )

    workspace = Path.join(ctx.tmp_dir, "workspace")
    File.mkdir_p!(workspace)

    {:ok, session} =
      OhMyJido.start_session(runtime,
        workspace: workspace,
        tools: [OhMyJido.Tools.Question],
        permissions: [:ask]
      )

    session
  end

  test "the deck starts no coding runtime, and still indexes the user's sessions", ctx do
    start_supervised!({DynamicSupervisor, name: Elixos.Package.Services, strategy: :one_for_one})
    start_supervised!({Approvals, mode: :normal, profile: :deck})
    {:ok, []} = Approvals.subscribe()

    assert DynamicSupervisor.which_children(Elixos.Package.Services) == []

    session = user_session(ctx)
    parent = self()

    spawn(fn ->
      send(
        parent,
        {:answered, OhMyJido.execute_tool(session, "question", %{question: "Ship it?"})}
      )
    end)

    assert_receive {:elixos_approvals, [%Approvals.Request{kind: :text} = request]}, 5_000
    assert request.session_id == session.id
    assert Approvals.answer(request.id, "yes") == :ok
    assert_receive {:answered, {:ok, _answer}}, 5_000
  end

  test "the full profile still starts the coding runtime at boot", ctx do
    previous = Application.fetch_env(:elixos, :priv_dir)
    Application.put_env(:elixos, :priv_dir, ctx.tmp_dir)

    on_exit(fn ->
      case previous do
        {:ok, priv_dir} -> Application.put_env(:elixos, :priv_dir, priv_dir)
        :error -> Application.delete_env(:elixos, :priv_dir)
      end
    end)

    start_supervised!({DynamicSupervisor, name: Elixos.Package.Services, strategy: :one_for_one})
    start_supervised!({Approvals, mode: :normal, profile: :full})
    # The runtime starts in the index's handle_continue; this call follows it.
    assert Approvals.pending() == []

    assert [{_id, runtime, _type, _modules}] =
             DynamicSupervisor.which_children(Elixos.Package.Services)

    assert is_pid(runtime)
  end
end
