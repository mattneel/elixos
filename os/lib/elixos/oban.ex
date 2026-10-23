defmodule Elixos.Oban do
  @moduledoc """
  Oban on Elixos (M19, docs/ROADMAP.md): the machine's scheduler.

  Jobs are rows in the system Postgres (M18), so they survive a power cycle,
  fail and retry; an app declares its queues and its cron entries in its
  `elixos:` key, next to its services (M11's spec), and `options/1` turns one
  app's declaration into Oban's options. Oban is not boot-critical and does
  not run in rescue; the VM's shutdown stops it before the shim stops Postgres.

  `start_link/1` takes `:mode` (`:normal` or `:rescue`) and, for an isolated
  instance, `:name` (this supervisor, `Elixos.Oban` by default), `:manager`
  (`Elixos.Oban.Manager`), `:repo` (`Elixos.Oban.Repo`) and `:oban` (the
  Oban instance's own name, `Oban`). The accessors below address the default
  instance. `:profile` is the image profile (ADR-111): under `:deck` the
  scheduler follows a Postgres that starts on first use, and its own first
  use (`status/0`, `enqueue/3`) starts the database.

  Boot order is load-bearing: the manager starts before
  `Elixos.Boot.Restore`, so a generation's `configure_app!/2` boot MFAs are
  collected while the image restores, and `activate/0` - called once the
  supervision tree is up - releases the queues, so no job can run against a
  half-restored image. A declaration that is rejected at boot raises, which
  fails the boot and lets the shim fall back (ADR-007).
  """

  use Supervisor

  alias Elixos.Package.Spec

  @manager Elixos.Oban.Manager

  @doc "Starts the scheduler manager. See the moduledoc for the options."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Supervisor.init([{Elixos.Oban.Manager, opts}], strategy: :one_for_one)
  end

  @doc """
  The running scheduler: `{:ok, pid}` or `{:error, :not_running}`.

  The first normal-mode caller waits, bounded, while the database comes up and
  the migrations run; rescue, and a scheduler that failed to start, answer at
  once.
  """
  @spec status() :: {:ok, pid()} | {:error, :not_running}
  def status do
    case manager() do
      nil -> {:error, :not_running}
      pid -> GenServer.call(pid, :status, :infinity)
    end
  end

  @doc """
  Inserts `worker` with `args` (keyword `opts` go to `Oban.Job.new/3`: queue,
  `schedule_in`, priority, and so on) and returns `{:ok, id}` - the job's id
  in the database, where the rest of it can be read (`Elixos.Oban.Repo`).

  Like `status/0`, this waits for bounded startup, then returns Oban's real
  insert result; `{:error, :not_running}` when there is no scheduler, and
  Oban's own errors (a rejected changeset, a conflict) unchanged.
  """
  @spec enqueue(module(), map(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def enqueue(worker, args, opts \\ []) do
    with {:ok, instance} <- await_instance() do
      case Oban.insert(instance, worker.new(args, opts)) do
        {:ok, %Oban.Job{id: id}} -> {:ok, id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  One app's Oban options from its `elixos:` declaration: the queues it runs
  and the `Oban.Plugins.Cron` plugin it needs, if any.
  """
  @spec options(Spec.t()) :: keyword()
  def options(%Spec{oban: oban}) do
    queues = Elixos.Oban.Declaration.queues(oban)
    cron = Elixos.Oban.Declaration.cron(oban)

    [queues: queues]
    |> Enum.reject(fn {_key, value} -> value == [] end)
    |> Kernel.++(if cron == [], do: [], else: [plugins: [%{crontab: cron}]])
  end

  @doc """
  Adds or replaces the `oban:` declaration of installed app `app`, `[]` to
  remove it, and applies the change to the running scheduler.

  `:ok` accepts it; `{:error, :invalid}` refuses a malformed declaration, and
  `{:error, {:conflict, queue}}` refuses one that disagrees with another app's
  limit for the same queue - the accepted configuration is left alone. A
  declaration accepted while no scheduler runs is kept for the next normal
  boot; a declaration is never quietly dropped.
  """
  @spec configure_app(atom(), keyword()) :: :ok | {:error, term()}
  def configure_app(app, declaration) do
    case manager() do
      nil -> {:error, :not_running}
      pid -> GenServer.call(pid, {:configure_app, app, declaration}, :infinity)
    end
  end

  @doc """
  `configure_app/2`, as a boot MFA: a rejected declaration raises
  `Elixos.Oban.ConfigurationError` so the generation cannot boot half-configured.
  """
  @spec configure_app!(atom(), keyword()) :: :ok
  def configure_app!(app, declaration) do
    case configure_app(app, declaration) do
      :ok -> :ok
      {:error, reason} -> raise Elixos.Oban.ConfigurationError, {app, reason}
    end
  end

  @doc """
  Asks the manager to release the queues, once the supervision tree - and with
  it the restored image - is up. Called by `Elixos.Application` after the
  children start; queues never run before it.

  It returns immediately: the boot must not wait on the scheduler, and a
  scheduler that could not start never fabricates a queue from a cast that
  arrived anyway.
  """
  @spec activate() :: :ok
  def activate do
    case manager() do
      nil -> :ok
      pid -> GenServer.cast(pid, :activate)
    end

    :ok
  end

  defp await_instance do
    case manager() do
      nil -> {:error, :not_running}
      pid -> GenServer.call(pid, :await_instance, :infinity)
    end
  end

  defp manager do
    case Process.whereis(@manager) do
      nil -> nil
      pid -> pid
    end
  end
end
