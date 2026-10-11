defmodule Elixos.Image do
  @moduledoc """
  The live image: store + journal + generations (docs/ARCHITECTURE.md §4).

  There is no heap snapshot on the BEAM, so the image is code plus data plus a
  boot spec, rebuilt into a running system at boot (ADR-005). Layout under `root`:

      root/store/          Elixos.Image.Store blobs
      root/journal.log     Elixos.Image.Journal
      root/generations/    Elixos.Image.Generation manifests (<n>.gen)

  The *working set* is the latest recorded hash of every module that has not
  been forgotten, rebuilt by replaying the journal on `open/1`. `save/2` turns
  the working set into a new generation.
  """

  use GenServer

  alias Elixos.Image.{Generation, Journal, Store}

  @type t :: pid()

  @spec open(Path.t()) :: {:ok, t()} | {:error, term()}
  def open(root) do
    with {:ok, store} <- Store.open(store_dir(root)),
         {:ok, journal} <- Journal.open(journal_path(root)) do
      # The working set is the journal replayed: every definition, in order,
      # with the ones that were forgotten left out.
      case Journal.read(journal_path(root)) do
        {:ok, entries, _status} ->
          state = %{
            root: root,
            store: store,
            journal: journal,
            modules: working_set(entries),
            apps: apps_of(entries),
            agents: agents_of(entries)
          }

          GenServer.start_link(__MODULE__, state)

        {:error, reason} ->
          :ok = Journal.close(journal)
          {:error, reason}
      end
    end
  end

  @doc "Stores `bytecode`, journals `{:module, module, hash}`, updates the working set."
  @spec record(t(), module(), binary()) :: {:ok, Elixos.Image.Store.hash()} | {:error, term()}
  def record(image, module, bytecode) do
    # Durable recording is the one boundary that must not time out: a slow fsync
    # is still a successful record, and the caller (the recorder) would lose
    # queued captures if this call exited.
    GenServer.call(image, {:record, module, bytecode}, :infinity)
  end

  @doc "Journals `{:forget, module}` and drops it from the working set."
  @spec forget(t(), module()) :: :ok | {:error, term()}
  def forget(image, module) do
    GenServer.call(image, {:forget, module})
  end

  @spec modules(t()) :: %{module() => Elixos.Image.Store.hash()}
  def modules(image) do
    GenServer.call(image, :modules)
  end

  @doc """
  Writes the working set as generation `Generation.next_number/1`, with parent
  the previous highest generation (0 if none), and journals `{:generation, n}`.
  Options: `boot: [{module, function, args}]`.
  """
  @spec save(t(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def save(image, opts \\ []) do
    GenServer.call(image, {:save, opts})
  end

  @doc "Loads every module of generation `n` into the VM."
  @spec restore(t(), non_neg_integer()) ::
          {:ok, [module()]} | {:error, :not_found | {:missing_blob, module()} | term()}
  def restore(image, n) do
    GenServer.call(image, {:restore, n})
  end

  @doc """
  Modules in the working set that are absent from generation `n` or differ
  from it (unsaved changes), sorted. Generation 0, the factory, holds no user
  modules, so against it every recorded module is unsaved.
  """
  @spec unsaved(t(), non_neg_integer()) :: [module()]
  def unsaved(image, n) do
    GenServer.call(image, {:unsaved, n})
  end

  @doc "Loads the working-set versions of `modules` into the VM."
  @spec recover(t(), [module()]) :: {:ok, [module()]} | {:error, term()}
  def recover(image, modules) do
    GenServer.call(image, {:recover, modules})
  end

  @doc "The manifest of generation `n`, or `{:error, :not_found}`."
  @spec generation(t(), non_neg_integer()) ::
          {:ok, Generation.t()} | {:error, :not_found | :corrupt}
  def generation(image, n) do
    GenServer.call(image, {:generation, n})
  end

  @doc "Saved generation numbers, oldest first."
  @spec generations(t()) :: [pos_integer()]
  def generations(image) do
    GenServer.call(image, :generations)
  end

  @spec close(t()) :: :ok
  def close(image) do
    GenServer.stop(image)
  end

  ## GenServer

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:apps, _from, state), do: {:reply, state.apps, state}

  def handle_call({:record_app, app, version, services, deps, oban}, _from, state) do
    # One journal entry: an app's services, requirements and scheduler
    # declaration are one install, and a replay must never see half of it.
    with {:ok, _seq} <- Journal.append(state.journal, {:app, app, version, services, deps, oban}) do
      {:reply, :ok,
       %{
         state
         | apps:
             Map.put(state.apps, app, %{
               version: version,
               services: services,
               deps: deps,
               oban: oban
             })
       }}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:agents, _from, state), do: {:reply, state.agents, state}

  def handle_call({:record_agent, id, module, opts}, _from, state) do
    with {:ok, _seq} <- Journal.append(state.journal, {:agent, id, module, opts}) do
      {:reply, :ok, %{state | agents: Map.put(state.agents, id, %{module: module, opts: opts})}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:forget_agent, id}, _from, state) do
    case Map.fetch(state.agents, id) do
      {:ok, _agent} ->
        with {:ok, _seq} <- Journal.append(state.journal, {:agent_removed, id}) do
          {:reply, :ok, %{state | agents: Map.delete(state.agents, id)}}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      :error ->
        {:reply, {:error, :unknown_agent}, state}
    end
  end

  def handle_call({:forget_app, app}, _from, state) do
    case Map.fetch(state.apps, app) do
      {:ok, %{services: services}} ->
        with {:ok, _seq} <- Journal.append(state.journal, {:uninstall, app}) do
          {:reply, {:ok, services}, %{state | apps: Map.delete(state.apps, app)}}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      :error ->
        {:reply, {:error, :not_installed}, state}
    end
  end

  def handle_call({:record, module, bytecode}, _from, state) do
    # A full or read-only disk is an error to report, not a reason to take the
    # image service down (the caller would lose every queued capture with it).
    with {:ok, hash} <- Store.put(state.store, bytecode),
         {:ok, _seq} <- Journal.append(state.journal, {:module, module, hash}) do
      {:reply, {:ok, hash}, %{state | modules: Map.put(state.modules, module, hash)}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:forget, module}, _from, state) do
    with {:ok, _seq} <- Journal.append(state.journal, {:forget, module}) do
      {:reply, :ok, %{state | modules: Map.delete(state.modules, module)}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:modules, _from, state), do: {:reply, state.modules, state}

  def handle_call({:generation, number}, _from, state) do
    {:reply, Generation.read(generations_dir(state.root), number), state}
  end

  def handle_call(:generations, _from, state) do
    {:reply, Generation.list(generations_dir(state.root)), state}
  end

  def handle_call({:save, opts}, _from, state) do
    dir = generations_dir(state.root)
    saved = Generation.list(dir)

    generation = %Generation{
      number: Generation.next_number(dir),
      parent: if(saved == [], do: 0, else: Enum.max(saved)),
      modules: state.modules,
      # The scheduler declarations and services of every installed app boot
      # with this generation: that is what makes an install survive a power
      # cycle (M11, M19).
      boot: Enum.uniq(Keyword.get(opts, :boot, []) ++ oban_boot(state.apps) ++ service_boot(state.apps)),
      created_at: DateTime.utc_now()
    }

    with :ok <- Generation.write(dir, generation),
         {:ok, _seq} <- Journal.append(state.journal, {:generation, generation.number}) do
      {:reply, {:ok, generation.number}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:restore, number}, _from, state) do
    case Generation.read(generations_dir(state.root), number) do
      {:ok, generation} -> {:reply, load_all(state.store, generation.modules), state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unsaved, number}, _from, state) do
    modules =
      case Generation.read(generations_dir(state.root), number) do
        {:ok, generation} ->
          Enum.sort(
            for {module, hash} <- state.modules,
                Map.get(generation.modules, module) != hash,
                do: module
          )

        {:error, _reason} ->
          Enum.sort(Map.keys(state.modules))
      end

    {:reply, modules, state}
  end

  def handle_call({:recover, modules}, _from, state) do
    hashes = Map.take(state.modules, modules)
    {:reply, load_all(state.store, hashes), state}
  end

  @impl true
  def terminate(_reason, state) do
    :ok = Journal.close(state.journal)
    :ok
  end

  ## The image on disk

  @doc "Installed apps and versions. (M11)"
  @spec apps(t()) :: %{atom() => String.t()}
  def apps(image) do
    for {app, %{version: version}} <- GenServer.call(image, :apps), into: %{}, do: {app, version}
  end

  @doc """
  Records that `app` (at `version`) is installed with `services` from its
  `elixos:` key, the `deps` it requires (ADR-015) and its `oban:`
  declaration: journaled as one entry, so the whole install replays at boot.
  (M11, M15, M19)
  """
  @spec record_app(t(), atom(), String.t(), [term()], %{atom() => String.t()}, keyword()) ::
          :ok | {:error, term()}
  def record_app(image, app, version, services, deps, oban) do
    GenServer.call(image, {:record_app, app, version, services, deps, oban}, :infinity)
  end

  @doc """
  Every installed package as the resolver wants it: `app`, `version` and what
  it requires. (M15)
  """
  @spec packages(t()) :: [%{app: atom(), version: String.t(), deps: %{atom() => String.t()}}]
  def packages(image) do
    for {app, entry} <- GenServer.call(image, :apps) do
      %{app: app, version: entry.version, deps: Map.get(entry, :deps, %{})}
    end
  end

  @doc """
  Forgets `app`: it is no longer installed. The services its `elixos:` key
  asked for come back, so the caller stops exactly what it started. (M14)
  """
  @spec forget_app(t(), atom()) :: {:ok, [term()]} | {:error, term()}
  def forget_app(image, app) do
    GenServer.call(image, {:forget_app, app}, :infinity)
  end

  @doc """
  Agents the journal knows: `id => %{module: module, opts: opts}`. (M15)

  An agent is a module the image already keeps plus the fact that it should
  be *running*; the record is what `Elixos.Agents` replays at boot.
  """
  @spec agents(t()) :: %{String.t() => %{module: module(), opts: keyword()}}
  def agents(image), do: GenServer.call(image, :agents)

  @doc "Records that agent `id` (of `module`, started with `opts`) is wanted. (M15)"
  @spec record_agent(t(), String.t(), module(), keyword()) :: :ok | {:error, term()}
  def record_agent(image, id, module, opts) do
    GenServer.call(image, {:record_agent, id, module, opts}, :infinity)
  end

  @doc "Forgets agent `id`: the next boot does not start it. (M15)"
  @spec forget_agent(t(), String.t()) :: :ok | {:error, term()}
  def forget_agent(image, id) do
    GenServer.call(image, {:forget_agent, id}, :infinity)
  end

  # What an install did, replayed: the newest entry for each app wins, and it
  # carries the services that app's elixos: key asked for.
  defp apps_of(entries) do
    Enum.reduce(entries, %{}, fn {_seq, entry}, apps ->
      case entry do
        # The whole install in one entry (M19).
        {:app, app, version, services, deps, oban} ->
          Map.put(apps, app, %{version: version, services: services, deps: deps, oban: oban})

        # Historical entries: M11 wrote services, M15 added requirements
        # separately. They replay as an install that declared no scheduler.
        {:app, app, version, services} ->
          Map.put(apps, app, %{version: version, services: services})

        {:uninstall, app} ->
          Map.delete(apps, app)

        {:app_deps, app, deps} ->
          Map.update(apps, app, %{deps: deps}, &Map.put(&1, :deps, deps))

        _other ->
          apps
      end
    end)
  end

  # The agents a boot should start: recorded, less any that were forgotten.
  defp agents_of(entries) do
    Enum.reduce(entries, %{}, fn {_seq, entry}, agents ->
      case entry do
        {:agent, id, module, opts} -> Map.put(agents, id, %{module: module, opts: opts})
        {:agent_removed, id} -> Map.delete(agents, id)
        _other -> agents
      end
    end)
  end

  # The services every installed app asked to have started under the system
  # tree. Each is a boot MFA: the generation's boot list runs it, so a service
  # comes back the same way at boot as it started at install time.
  defp service_boot(apps) do
    for {_app, %{services: services}} <- apps,
        service <- services,
        do: {Elixos.Package, :start_service, [service]}
  end

  # An app's scheduler declaration is part of the same boot spec, and comes
  # first: queues are configured before the services that may enqueue.
  # configure_app!/2 raises on a refused declaration, which fails the boot
  # (a generation does not boot half-configured).
  defp oban_boot(apps) do
    for {app, %{oban: oban}} <- apps,
        oban != [],
        do: {Elixos.Oban, :configure_app!, [app, oban]}
  end

  defp working_set(entries) do
    Enum.reduce(entries, %{}, fn {_seq, entry}, modules ->
      case entry do
        {:module, module, hash} -> Map.put(modules, module, hash)
        {:forget, module} -> Map.delete(modules, module)
        # A generation is a marker in the journal, not a change to the set.
        _other -> modules
      end
    end)
  end

  # Verify the entire generation before loading anything: an earlier @on_load
  # must not run when a later blob is missing or corrupt. Keep the verified
  # binaries, rather than rereading mutable candidate paths during loading.
  defp load_all(store, modules) do
    modules
    |> Enum.sort_by(fn {module, _hash} -> module end)
    |> Enum.reduce_while([], fn {module, hash}, verified ->
      case Store.get(store, hash) do
        {:ok, bytecode} -> {:cont, [{module, bytecode} | verified]}
        {:error, _reason} -> {:halt, {:error, {:missing_blob, module}}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      verified -> load_verified(Enum.reverse(verified))
    end
  end

  defp load_verified(modules) do
    modules
    |> Enum.reduce_while([], fn {module, bytecode}, loaded ->
      case :code.load_binary(module, ~c"elixos", bytecode) do
        {:module, ^module} -> {:cont, [module | loaded]}
        {:error, reason} -> {:halt, {:error, {:load_failed, module, reason}}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      loaded -> {:ok, Enum.reverse(loaded)}
    end
  end

  defp store_dir(root), do: Path.join(root, "store")
  defp generations_dir(root), do: Path.join(root, "generations")
  defp journal_path(root), do: Path.join(root, "journal.log")
end
