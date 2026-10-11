defmodule Elixos.ObanLifecycleTest do
  @moduledoc """
  The scheduler's lifecycle on the host (M19): rescue has none, a declaration
  is validated before it is kept, a refusal is visible rather than a silent
  overwrite, and a start that cannot reach a database ends as
  `{:error, :not_running}` instead of a fabricated scheduler.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 19

  # `Elixos.Oban` would shadow the scheduler library of the same name.
  alias Elixos.Oban, as: Scheduler

  defmodule Worker do
    use Oban.Worker, queue: :jobs

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  # The supervisor returned by start_supervised! starts the manager; the
  # machine's own state is the manager's, not the supervisor's.
  defp manager, do: Process.whereis(Elixos.Oban.Manager)

  # The manager answers a waiting caller from its own state, so this waits for
  # the waiter to be admitted rather than racing the 150ms startup timeout.
  defp admitted(attempts \\ 1_000)
  defp admitted(0), do: flunk("no caller was waiting for the scheduler")

  defp admitted(attempts) do
    case :sys.get_state(manager()) do
      %{waiters: [_ | _]} = state -> state
      _other -> admitted(attempts - 1)
    end
  end

  test "rescue runs no scheduler and cannot enqueue" do
    start_supervised!({Scheduler, mode: :rescue})

    assert Scheduler.status() == {:error, :not_running}
    assert Scheduler.enqueue(Worker, %{"line" => "never"}) == {:error, :not_running}
    assert :sys.get_state(manager()).phase == :rescue

    # Accepting a declaration in rescue keeps it for the next normal boot; it
    # does not conjure a queue to run it.
    assert Elixos.Oban.configure_app(:demo, queues: [jobs: 3]) == :ok
    assert Scheduler.status() == {:error, :not_running}
  end

  test "a declaration is validated, and a disagreement is refused not overwritten" do
    start_supervised!({Scheduler, mode: :rescue})

    assert Elixos.Oban.configure_app(:alpha, queues: [jobs: 3, mail: 1]) == :ok
    # A consistent shared limit is one queue, not a conflict.
    assert Elixos.Oban.configure_app(:beta, queues: [jobs: 3]) == :ok
    # A disagreement is an error, and alpha's accepted configuration stands.
    assert Elixos.Oban.configure_app(:gamma, queues: [jobs: 5]) == {:error, {:conflict, :jobs}}

    # Removing one app's declaration does not erase the other's: beta still
    # holds jobs at 3, so gamma's 5 is still a disagreement.
    assert Elixos.Oban.configure_app(:alpha, []) == :ok
    assert Elixos.Oban.configure_app(:gamma, queues: [jobs: 5]) == {:error, {:conflict, :jobs}}

    assert Elixos.Oban.configure_app(:beta, []) == :ok
    assert Elixos.Oban.configure_app(:gamma, queues: [jobs: 5]) == :ok

    # The system's own queue namespace is not an app's to declare.
    assert Elixos.Oban.configure_app(:delta, queues: [elixos_system: 1]) == {:error, :invalid}
    assert Elixos.Oban.configure_app(:epsilon, queues: [jobs: 0]) == {:error, :invalid}
    assert Elixos.Oban.configure_app(:zeta, queues: :many) == {:error, :invalid}
    assert Elixos.Oban.configure_app(:eta, unknown: 1) == {:error, :invalid}

    # Five fields, a real expression, and a worker module.
    assert Elixos.Oban.configure_app(:theta, cron: [{"0 3 * * *", Worker}]) == :ok
    assert Elixos.Oban.configure_app(:iota, cron: [{"0 3 * *", Worker}]) == {:error, :invalid}
    assert Elixos.Oban.configure_app(:kappa, cron: [{"* * * * * *", Worker}]) == {:error, :invalid}
    assert Elixos.Oban.configure_app(:lambda, cron: [{"@reboot", Worker}]) == {:error, :invalid}
    assert Elixos.Oban.configure_app(:mu, cron: [{"0 3 * * *"}]) == {:error, :invalid}
  end

  test "configure_app!/2 raises, because a boot MFA's return value is ignored" do
    start_supervised!({Scheduler, mode: :rescue})

    assert_raise Elixos.Oban.ConfigurationError, fn ->
      Elixos.Oban.configure_app!(:bad, queues: [jobs: -1])
    end

    assert Elixos.Oban.configure_app!(:good, queues: [jobs: 1]) == :ok
  end

  test "a start that never reaches Postgres ends as not running" do
    start_supervised!({Scheduler, mode: :normal, startup_timeout: 150})

    # Postgres is not running on the host, so the first caller waits - and is
    # answered when the manager gives up, not with a fabricated scheduler.
    status = Task.async(fn -> Scheduler.status() end)
    assert %{phase: :waiting_postgres} = admitted()

    assert Task.await(status, 5_000) == {:error, :not_running}
    assert :sys.get_state(manager()).phase == :failed

    # Activation releases queues; with no scheduler there is nothing to
    # release, and none appears.
    assert Scheduler.activate() == :ok
    assert Scheduler.status() == {:error, :not_running}
    assert Scheduler.enqueue(Worker, %{}) == {:error, :not_running}
  end

  test "activation is safe with no manager at all" do
    refute Process.whereis(Elixos.Oban.Manager)
    assert Scheduler.activate() == :ok
    assert Scheduler.status() == {:error, :not_running}
  end
end
