defmodule Elixos.Agents do
  @moduledoc """
  Agents are ordinary Elixos code that is *running* (M15).

  The M6 image already keeps a module a prompt defined: `Elixos.save/1`,
  power off, and the next boot has the module back. A module cannot, by
  itself, come back *running* with what it remembered - that is this module.
  `start/2` starts an agent under `Elixos.Agents.Supervisor` and records it in
  the image's journal, so the next boot starts it again; `stop/1` writes what
  it remembered, stops it and forgets it. `list/0` is what is running,
  `whereis/1` how to reach one.

  What an agent remembers belongs on `/priv` with the rest of the machine's
  state (PROTOCOL.md §7): `snapshot/1` writes `/priv/agents/<id>.term`, and it
  is written when `Elixos.save/1` runs - one action, one durable moment - and
  when an agent stops. An agent module is either a Jido agent (`use
  Jido.Agent`): started through Jido's `AgentServer`, its state read back as
  the agent struct and handed to `AgentServer` again on the next boot; or a
  plain module following this contract:

    * `start_link/1` - starts it, with the recorded options and `:snapshot`
      (nil when there is nothing remembered)
    * `snapshot/1` - what to keep, as a term (optional)
  """

  use GenServer

  require Logger

  @doc "Starts an agent and records it, so the next boot starts it too."
  @spec start(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(module, opts \\ []) do
    GenServer.call(__MODULE__, {:start, module, opts}, :infinity)
  end

  @doc "Stops an agent: what it remembers is written, and it is forgotten."
  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(id), do: GenServer.call(__MODULE__, {:stop, id}, :infinity)

  @doc "Every recorded agent: id => pid, or nil when it is not running."
  @spec list() :: %{String.t() => pid() | nil}
  def list, do: GenServer.call(__MODULE__, :list)

  @doc "The pid of the agent `id`, or nil."
  @spec whereis(String.t()) :: pid() | nil
  def whereis(id), do: GenServer.call(__MODULE__, {:whereis, id})

  @doc "Writes what one agent remembers, now."
  @spec snapshot(String.t()) :: :ok | {:error, term()}
  def snapshot(id), do: GenServer.call(__MODULE__, {:snapshot, id}, :infinity)

  @doc """
  Writes what every running agent remembers (`Elixos.save/1` calls this).

  Every failure is named: a memory that could not be written is the live
  image's promise broken, and the callers refuse to call the save (or the
  power-off) done.
  """
  @spec snapshot_all() :: :ok | {:error, {:snapshot_failed, [String.t()]}}
  def snapshot_all do
    failures =
      for {id, pid} <- list(), pid != nil, {:error, _reason} <- [snapshot(id)], do: id

    case failures do
      [] -> :ok
      ids -> {:error, {:snapshot_failed, ids}}
    end
  end

  @doc "Supervisor child: starts every recorded agent (normal boots only)."
  def start_link(arg \\ nil)

  def start_link(image) when is_pid(image) or is_nil(image), do: start_link({image, :normal})

  def start_link({image, mode}) do
    GenServer.start_link(__MODULE__, {image, mode}, name: __MODULE__)
  end

  @doc "Starts every recorded agent that is not running (boot, or after a crash)."
  @spec restore() :: :ok
  def restore, do: GenServer.call(__MODULE__, :restore, :infinity)

  @impl true
  def init({_image, :rescue}) do
    # A rescue boot is the factory with /priv mounted: the minimum to get a
    # prompt and fix the machine. User agents are not part of the minimum.
    Logger.info("agents: rescue boot, not starting agents")
    {:ok, %{}, {:continue, :nothing}}
  end

  def init({image, _mode}), do: {:ok, %{}, {:continue, {:restore, image}}}

  @impl true
  def handle_continue(:nothing, agents), do: {:noreply, agents}
  def handle_continue({:restore, _image}, agents), do: {:noreply, restore_into(agents)}

  # Every agent the journal knows and is not up, with what it remembered. A
  # failure is logged and the rest still start - an agent is not the system.
  defp restore_into(agents) do
    case Process.whereis(Elixos.Image) do
      nil ->
        agents

      image ->
        Enum.reduce(Elixos.Image.agents(image), agents, fn {id, %{module: module, opts: opts}},
                                                           acc ->
          if alive(Map.get(acc, id, %{pid: nil}).pid) do
            acc
          else
            case start_child(module, id, Keyword.put(opts, :id, id)) do
              {:ok, pid} ->
                Map.put(acc, id, %{module: module, opts: opts, pid: pid})

              {:error, reason} ->
                log_failed(id, reason)
                acc
            end
          end
        end)
    end
  end

  @impl true
  def handle_call(:restore, _from, agents), do: {:reply, :ok, restore_into(agents)}

  def handle_call({:start, module, opts}, _from, agents) do
    id = Keyword.get(opts, :id) || default_id(module)

    case start_child(module, id, opts) do
      {:ok, pid} ->
        with :ok <- record(id, module, opts) do
          {:reply, {:ok, pid}, Map.put(agents, id, %{module: module, opts: opts, pid: pid})}
        else
          {:error, reason} ->
            _ = DynamicSupervisor.terminate_child(Elixos.Agents.Supervisor, pid)
            {:reply, {:error, reason}, agents}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, agents}
    end
  end

  def handle_call({:stop, id}, _from, agents) do
    case Map.fetch(agents, id) do
      :error ->
        {:reply, {:error, :unknown_agent}, agents}

      {:ok, %{module: module} = record} ->
        # A snapshot that cannot be written stops the stop: nothing is lost
        # silently, and the record stays so the next boot still starts it.
        case write_snapshot(id, snapshot_of(module, live_pid(id, record))) do
          :ok ->
            if pid = live_pid(id, record),
              do: DynamicSupervisor.terminate_child(Elixos.Agents.Supervisor, pid)

            # Forgetting is written down too (the journal, like the record).
            # If that write fails, the durable record stays - which is what
            # the next boot reads - and the stop is not done: a second stop
            # retries the forgetting instead of lying to the caller.
            case forget(id) do
              :ok -> {:reply, :ok, Map.delete(agents, id)}
              {:error, reason} -> {:reply, {:error, reason}, agents}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, agents}
        end
    end
  end

  def handle_call(:list, _from, agents) do
    {:reply, Map.new(agents, fn {id, record} -> {id, live_pid(id, record)} end), agents}
  end

  def handle_call({:whereis, id}, _from, agents) do
    {:reply, live_pid_of(id, agents), agents}
  end

  def handle_call({:snapshot, id}, _from, agents) do
    case Map.fetch(agents, id) do
      :error ->
        {:reply, {:error, :unknown_agent}, agents}

      {:ok, %{module: module} = record} ->
        {:reply, write_snapshot(id, snapshot_of(module, live_pid(id, record))), agents}
    end
  end

  defp live_pid_of(id, agents) do
    case Map.fetch(agents, id) do
      {:ok, record} -> live_pid(id, record)
      :error -> nil
    end
  end

  # Every plain-agent start, including supervisor restarts, registers its binary
  # ID as data. The supervisor pid scopes names to this tree, including when a
  # connected peer runs its own Elixos instance. Jido already has a string registry.
  defp live_pid(id, %{module: module, opts: opts}) do
    case :global.whereis_name(registration_key(id)) do
      :undefined ->
        if jido_agent?(module) do
          Jido.AgentServer.whereis(Jido.registry_name(Keyword.get(opts, :jido, Jido)), id)
        end

      pid ->
        pid
    end
  end

  defp registration_key(id), do: {__MODULE__, Process.whereis(Elixos.Agents.Supervisor), id}

  @doc false
  # The child spec's start MFA: the agent starts and its name is registered,
  # which is what a lookup reads after a supervisor restart.
  def start_agent_child(module, id, opts) do
    key = registration_key(id)

    if :global.whereis_name(key) != :undefined do
      {:error, {:already_started, id}}
    else
      case module.start_link(opts) do
        {:ok, pid} ->
          case :global.register_name(key, pid) do
            :yes ->
              {:ok, pid}

            :no ->
              # Lost a race with another start of the same id: that one wins,
              # and this child does not exist.
              Process.exit(pid, :shutdown)
              {:error, {:already_started, id}}
          end

        error ->
          error
      end
    end
  end

  ## Starting

  defp start_child(module, id, opts) do
    snapshot = read_snapshot(id)
    child = child_spec(module, id, opts, snapshot)

    DynamicSupervisor.start_child(Elixos.Agents.Supervisor, child)
  end

  # A Jido agent runs through Jido's AgentServer, which is what makes it a
  # process; the AgentServer takes the agent struct when there is one to
  # restore, the module otherwise. A plain agent is its own GenServer.
  defp child_spec(module, id, opts, snapshot) do
    if jido_agent?(module) do
      instance = Keyword.get(opts, :jido, Jido)
      :ok = start_jido(instance)

      options = Keyword.drop(opts, [:id, :jido])
      # What was remembered goes in as the agent's *state*: the module is the
      # one the record names, and a restored `%Jido.Agent{}` struct would
      # tell the server the module is `Jido.Agent` itself.
      options = if snapshot, do: Keyword.put(options, :initial_state, snapshot), else: options

      {Jido.AgentServer, Keyword.merge(options, agent: module, id: id, jido: instance)}
    else
      %{
        id: {:elixos_agent, id},
        start:
          {__MODULE__, :start_agent_child, [module, id, Keyword.put(opts, :snapshot, snapshot)]}
      }
    end
  end

  # A Jido instance is a supervision tree of its own (registry, agent
  # supervisor, worker pool): the first agent that needs it starts it. An
  # instance module writes its own `start_link/0` (`use Jido`); the library
  # module itself only has `start_link/1`, and naming it is how an agent joins
  # the instance the OS calls `Jido` - that is what `jido: Jido` means.
  defp start_jido(instance) do
    cond do
      Process.whereis(instance) ->
        :ok

      function_exported?(instance, :start_link, 0) ->
        jido_started(instance, apply(instance, :start_link, []))

      function_exported?(instance, :start_link, 1) ->
        {:ok, _apps} = Application.ensure_all_started(:jido)
        jido_started(instance, apply(instance, :start_link, [[name: instance]]))

      true ->
        {:error, {:jido_instance_failed, instance, :no_start_link}}
    end
  end

  defp jido_started(_instance, {:ok, _pid}), do: :ok
  defp jido_started(_instance, {:error, {:already_started, _pid}}), do: :ok
  defp jido_started(instance, {:error, reason}), do: {:error, {:jido_instance_failed, instance, reason}}

  defp jido_agent?(module) do
    is_atom(module) and Code.ensure_loaded?(module) and
      function_exported?(module, :__agent_metadata__, 0)
  end

  ## Snapshots

  defp snapshot_of(module, pid) do
    cond do
      pid == nil -> nil
      jido_agent?(module) -> jido_snapshot(pid)
      function_exported?(module, :snapshot, 1) -> module.snapshot(pid)
      true -> nil
    end
  end

  # What an agent remembers is its state map; the module comes from the
  # record, so this is all a restart needs.
  defp jido_snapshot(pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, state} -> Map.get(state, :agent).state
      {:error, _reason} -> nil
    end
  end

  defp read_snapshot(id) do
    case File.read(snapshot_path(id)) do
      {:ok, bytes} ->
        safe_binary_to_term(bytes)

      {:error, :enoent} ->
        nil

      {:error, reason} ->
        Logger.error("agents: #{id} snapshot unreadable: #{inspect(reason)}")
        nil
    end
  end

  defp safe_binary_to_term(bytes) do
    :erlang.binary_to_term(bytes)
  rescue
    ArgumentError ->
      Logger.error("agents: a snapshot is corrupt; starting without it")
      nil
  end

  defp write_snapshot(_id, nil), do: :ok

  # Temporary file, fsync, rename, fsync of the directory: the same promise
  # every other file the image keeps makes (Elixos.Image.Generation does it
  # the same way), so a power loss cannot leave half an agent's memory.
  defp write_snapshot(id, term) do
    path = snapshot_path(id)
    tmp = path <> ".tmp"
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         {:ok, file} <- :file.open(tmp, [:write, :raw, :binary]),
         :ok <- :file.write(file, :erlang.term_to_binary(term)),
         :ok <- :file.sync(file),
         :ok <- :file.close(file),
         :ok <- File.rename(tmp, path),
         {:ok, dir_file} <- :file.open(dir, [:read, :directory]),
         :ok <- :file.sync(dir_file),
         :ok <- :file.close(dir_file) do
      :ok
    else
      error ->
        File.rm(tmp)
        Logger.error("agents: could not write #{path}: #{inspect(error)}")
        {:error, {:snapshot_failed, id}}
    end
  end

  defp snapshot_path(id), do: Path.join(agents_dir(), "#{id}.term")

  defp agents_dir do
    Application.get_env(:elixos, :agents_dir, Path.join(priv(), "agents"))
  end

  defp priv, do: Application.get_env(:elixos, :priv_dir, "/priv")

  ## The record (the image's journal, like an installed app)

  defp record(id, module, opts) do
    case Process.whereis(Elixos.Image) do
      nil -> :ok
      image -> Elixos.Image.record_agent(image, id, module, opts)
    end
  end

  defp forget(id) do
    case Process.whereis(Elixos.Image) do
      nil -> :ok
      image -> Elixos.Image.forget_agent(image, id)
    end
  end

  defp alive(nil), do: nil
  defp alive(pid), do: if(Process.alive?(pid), do: pid, else: nil)

  defp default_id(module), do: module |> Module.split() |> List.last() |> Macro.underscore()

  defp log_failed(id, reason), do: Logger.error("agents: #{id} did not start: #{inspect(reason)}")
end
