defmodule Elixos.Coproc do
  @moduledoc """
  The coprocessor: an AtomVM node that is Elixos's peer (M29, ADR-098).

  Elixos becomes a distributed node only for this link. Distribution starts
  when this process starts, bound to the coprocessor link's address
  (`inet_dist_use_interface`), on a fixed port, with no epmd daemon
  (`Elixos.Coproc.Epmd` answers for the one peer and refuses every other
  node), and it stops when this process stops. Elixos is always the side that
  connects; the process monitors the peer, reconnects every
  `:reconnect_ms` while it is down, and runs calls on it.

  The coprocessor's code is generation content (ADR-099): a generation may
  carry an AtomVM bundle (`Elixos.Coproc.Bundle`), and the coprocessor must
  run the bundle of the generation that is running here - or, once a new one
  is saved, that one. Whenever the peer comes up, the bundle it reports is
  compared with the wanted one and, if they differ, the wanted one is
  deployed: the coprocessor's runtime (`:elixos_coproc`) stores it and
  restarts its VM. Falling back to `last_good` boots that generation, whose
  bundle is then deployed the same way.

  The coprocessor owns subsystems Linux cannot drive (M32: the UART3
  console, the display unit with touch and HDMI, LoRa, the power key and
  power-off; ADR-104, ADR-106, ADR-107, ADR-109). Each is a driver process its
  runtime starts at boot, independent of this link, reached through
  `Elixos.Coproc.Console`, `.Display`, `.Touch`, `.LoRa` and `.Power`.
  Subscriptions (`subscribe/2`) are held here and renewed whenever the peer
  comes up; the drivers queue events until a subscriber acknowledges them,
  so what happens while Elixos restarts arrives when it is back. Only a
  bundle change restarts the coprocessor's VM: the drivers restart with it,
  taking over their predecessors' state, and a generation switch that keeps
  the bundle leaves them running.

  At boot (`start_link(:boot)`) the link is configured from:

    * `/priv/coproc/config.exs` - a literal keyword list: `node:` the peer
      (required), `port:` its distribution port, `listen_port:` this node's
      (both default #{4370});
    * `/priv/coproc/cookie` - the shared cookie (`configure/1` creates it);
    * `elixos.coproc_link=<interface>,<address>/<prefix>` on the kernel
      command line - the link the shim configured, whose address the
      listener binds (PROTOCOL.md §5).

  Without a config file, in rescue mode, or when distribution cannot start,
  the child steps aside (`:ignore`) and the boot goes on.
  """

  use GenServer
  import Kernel, except: [node: 0]
  require Logger

  alias Elixos.Coproc.{Bundle, Epmd}

  @default_port 4370
  @reconnect_ms 1_000
  @call_timeout 5_000

  # The coprocessor's drivers (M32): each subsystem's registered process on
  # the peer (os/src/coproc_*.erl).
  @drivers %{
    console: :coproc_console,
    display: :coproc_display,
    touch: :coproc_touch,
    lora: :coproc_lora,
    power: :coproc_power
  }

  # The runtime archive: the start module, the drivers and their simulated
  # backends (ADR-098; M32).
  @runtime [
    :elixos_coproc,
    :coproc_drivers,
    :coproc_driver,
    :coproc_console,
    :coproc_console_sim,
    :coproc_display,
    :coproc_display_sim,
    :coproc_touch,
    :coproc_touch_sim,
    :coproc_lora,
    :coproc_lora_sim,
    :coproc_power,
    :coproc_power_sim
  ]

  @type bundle :: Bundle.t() | nil
  @type subsystem :: :console | :display | :touch | :lora | :power

  ## API

  @doc """
  Starts the link. `:boot` reads the configuration (see the moduledoc);
  otherwise the options are explicit:

    * `node:` the peer's node name (required);
    * `listen:` `{address, port}` this node listens on (required);
    * `cookie:` the shared cookie, a string (required);
    * `port:` the peer's distribution port (default #{@default_port});
    * `address:` the peer's address (default: parsed from `node`);
    * `name:` this node's name (default `elixos@<listen address>`);
    * `bundle:` the bundle the coprocessor must run, or `nil` for none;
      `:unmanaged` leaves whatever it runs alone (the default);
    * `reconnect_ms:` the retry interval (default #{@reconnect_ms}).
  """
  def start_link(:boot) do
    with {:ok, opts} <- boot_options(),
         {:error, reason} <- start_link(opts) do
      # The coprocessor is never a reason not to boot.
      Logger.warning("Elixos.Coproc not started: #{inspect(reason)}")
      :ignore
    end
  end

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def child_spec(arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :transient}
  end

  @doc "The peer's node name, connected or not."
  @spec node() :: node()
  def node, do: GenServer.call(__MODULE__, :node)

  @doc "Where the link stands: the peer, whether it is up, the bundle it runs and the one it should."
  @spec status() :: map()
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Calls `module.function(args)` on the coprocessor."
  @spec call(module(), atom(), list(), timeout()) :: {:ok, term()} | {:error, term()}
  def call(module, function, args, timeout \\ @call_timeout) do
    erpc(node(), module, function, args, timeout)
  end

  ## Drivers (M32)

  @doc """
  The coprocessor's driver processes, one per subsystem it owns (ADR-104,
  ADR-106, ADR-107, ADR-109). They run on the peer whether Elixos is
  connected or not; `Elixos.Coproc.Display` and its siblings reach them.
  """
  @spec drivers() :: {:ok, %{subsystem() => pid() | :undefined}} | {:error, term()}
  def drivers do
    with {:ok, pids} <- call(:coproc_drivers, :pids, []) do
      {:ok, Map.new(@drivers, fn {subsystem, name} -> {subsystem, Map.get(pids, name, :undefined)} end)}
    end
  end

  @doc """
  Subscribes `pid` to `subsystem`'s events: it receives each event term as a
  message, e.g. `{:lora, packet, meta}`. The subscription belongs to this
  link, not to the connection: it is renewed whenever the peer comes up, and
  events the coprocessor queued meanwhile arrive then. It ends when `pid`
  exits or unsubscribes.
  """
  @spec subscribe(subsystem(), pid()) :: :ok | {:error, term()}
  def subscribe(subsystem, pid \\ self()) when is_map_key(@drivers, subsystem) and is_pid(pid) do
    GenServer.call(__MODULE__, {:subscribe, subsystem, pid})
  end

  @doc "Ends `pid`'s subscription to `subsystem`."
  @spec unsubscribe(subsystem(), pid()) :: :ok
  def unsubscribe(subsystem, pid \\ self()) when is_map_key(@drivers, subsystem) and is_pid(pid) do
    GenServer.call(__MODULE__, {:unsubscribe, subsystem, pid})
  end

  @doc """
  Feeds `stimulus` to a simulated driver backend, as the hardware would: a
  touch, a packet from the air, a key press (the `simulate/2` clauses in
  `os/src/coproc_*_sim.erl`). A hardware backend refuses it.
  """
  @spec simulate(subsystem(), term()) :: term()
  def simulate(subsystem, stimulus) when is_map_key(@drivers, subsystem) do
    driver_call(:coproc_driver, :simulate, [Map.fetch!(@drivers, subsystem), stimulus])
  end

  @doc false
  # Runs a driver API function on the peer: its reply, or {:error, reason}
  # when the call itself failed.
  def driver_call(module, function, args) do
    case call(module, function, args) do
      {:ok, reply} -> reply
      {:error, _} = error -> error
    end
  end

  @doc """
  Makes `bundle` (`nil` for none) the one the coprocessor must run, and waits
  until it does: deployed, restarted and reconnected, or `{:error, :timeout}`.
  """
  @spec deploy(bundle(), timeout()) :: {:ok, String.t() | :none} | {:error, term()}
  def deploy(bundle, timeout \\ 60_000) when is_binary(bundle) or is_nil(bundle) do
    GenServer.call(__MODULE__, {:deploy, bundle, timeout}, timeout + 1_000)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @doc """
  After `Elixos.save/1` wrote generation `number`: deploys its bundle when a
  coprocessor is linked. A missing link is not an error - the bundle is
  deployed when this generation boots and the peer comes up.
  """
  @spec generation_saved(Elixos.Image.t(), pos_integer()) :: :ok | {:error, term()}
  def generation_saved(image, number) do
    with pid when is_pid(pid) <- Process.whereis(__MODULE__),
         {:ok, bundle} <- Elixos.Image.coproc_bundle(image, number),
         {:ok, _digest} <- deploy(bundle) do
      :ok
    else
      nil -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Writes the link's configuration (`node:`, `port:`, `listen_port:`) and
  creates the cookie if there is none, then (re)starts the link when it runs
  under the system's supervisor. Returns the cookie.
  """
  @spec configure(keyword()) :: {:ok, String.t()} | {:error, term()}
  def configure(opts) do
    node = Keyword.fetch!(opts, :node)
    config = [node: node, port: Keyword.get(opts, :port, @default_port),
              listen_port: Keyword.get(opts, :listen_port, @default_port)]

    with :ok <- File.mkdir_p(dir()),
         :ok <- File.write(config_path(), inspect(config, pretty: true) <> "\n"),
         {:ok, cookie} <- ensure_cookie() do
      restart_under_supervisor()
      {:ok, cookie}
    end
  end

  @doc """
  The coprocessor runtime archive: `:elixos_coproc`, the archive's start
  module, and the drivers it starts (`:coproc_drivers` and the
  `:coproc_*` modules, M32).
  """
  @spec runtime() :: {:ok, Bundle.t()} | {:error, term()}
  def runtime do
    with {:ok, beams} <- beams(@runtime, &object_code/1) do
      Bundle.pack(beams, start: :elixos_coproc)
    end
  end

  @doc """
  A bundle of `modules`, from the bytecode the live image recorded for them
  (modules defined at the prompt) or else from the code path.
  """
  @spec bundle([module()]) :: {:ok, Bundle.t()} | {:error, term()}
  def bundle(modules) when is_list(modules) do
    if Process.whereis(Elixos.Boot.Recorder), do: :ok = Elixos.Boot.Recorder.sync()

    with {:ok, beams} <- beams(modules, &bytecode/1), do: Bundle.pack(beams)
  end

  defp beams(modules, fetch) do
    modules
    |> Enum.reduce_while({:ok, []}, fn module, {:ok, acc} ->
      case fetch.(module) do
        {:ok, bytecode} -> {:cont, {:ok, [{module, bytecode} | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, beams} -> {:ok, Enum.reverse(beams)}
      error -> error
    end
  end

  @doc """
  Records `bundle` (an archive, a list of modules to pack, or `nil` for none)
  as the coprocessor's code in the working set; the next `Elixos.save/1`
  makes it generation content and deploys it.
  """
  @spec put_bundle(Bundle.t() | [module()] | nil) :: {:ok, String.t() | nil} | {:error, term()}
  def put_bundle(modules) when is_list(modules) do
    with {:ok, archive} <- bundle(modules), do: put_bundle(archive)
  end

  def put_bundle(bundle) when is_binary(bundle) or is_nil(bundle) do
    with :ok <- valid(bundle),
         image when is_pid(image) <- Process.whereis(Elixos.Image) || {:error, :no_image} do
      Elixos.Image.record_coproc(image, bundle)
    end
  end

  ## Configuration

  @doc false
  # The `elixos.coproc_link` value: interface, address and prefix length.
  @spec parse_link(String.t()) :: {:ok, {String.t(), :inet.ip4_address(), 0..32}} | :error
  def parse_link(value) when is_binary(value) do
    with [interface, cidr] <- String.split(value, ",", parts: 2),
         true <- interface != "",
         [address, prefix] <- String.split(cidr, "/", parts: 2),
         {:ok, {_, _, _, _} = ip} <- :inet.parse_strict_address(String.to_charlist(address)),
         {:ok, length} when length <= 32 <- Elixos.Decimal.parse_u32(prefix) do
      {:ok, {interface, ip, length}}
    else
      _ -> :error
    end
  end

  def parse_link(_value), do: :error

  defp boot_options do
    env = Elixos.Boot.Env.current()

    with {:ok, %{mode: :normal} = env} <- env,
         {:ok, config} <- read_config(),
         {:ok, cookie} <- read_cookie(),
         {:ok, {_interface, address, _prefix}} <- link(),
         {:ok, bundle} <- running_bundle(env.generation) do
      {:ok,
       [
         node: Keyword.fetch!(config, :node),
         port: Keyword.get(config, :port, @default_port),
         listen: {address, Keyword.get(config, :listen_port, @default_port)},
         cookie: cookie,
         bundle: bundle
       ]}
    else
      {:ok, _rescue_or_host} ->
        :ignore

      :unconfigured ->
        :ignore

      {:error, reason} ->
        Logger.warning("Elixos.Coproc not started: #{inspect(reason)}")
        :ignore
    end
  end

  defp read_config do
    case File.read(config_path()) do
      {:ok, text} ->
        with {:ok, quoted} <- Code.string_to_quoted(text),
             {:ok, config} <- Elixos.User.literals(quoted),
             node when is_atom(node) and node != nil <- Keyword.get(config, :node) do
          {:ok, config}
        else
          _ -> {:error, {:malformed, config_path()}}
        end

      {:error, :enoent} ->
        :unconfigured

      {:error, reason} ->
        {:error, {config_path(), reason}}
    end
  end

  defp read_cookie do
    case File.read(cookie_path()) do
      {:ok, text} -> cookie(String.trim(text))
      {:error, reason} -> {:error, {cookie_path(), reason}}
    end
  end

  defp cookie(""), do: {:error, :empty_cookie}
  defp cookie(cookie), do: {:ok, cookie}

  defp ensure_cookie do
    case read_cookie() do
      {:ok, cookie} ->
        {:ok, cookie}

      {:error, {_path, :enoent}} ->
        cookie = :crypto.strong_rand_bytes(24) |> Base.encode16(case: :lower)

        with :ok <- File.write(cookie_path(), cookie <> "\n"),
             :ok <- File.chmod(cookie_path(), 0o600) do
          {:ok, cookie}
        end

      error ->
        error
    end
  end

  defp link do
    case Map.get(Elixos.Boot.Cmdline.current(), "coproc_link") do
      nil -> {:error, :no_coproc_link}
      value -> with :error <- parse_link(value), do: {:error, {:malformed_coproc_link, value}}
    end
  end

  defp running_bundle(0), do: {:ok, nil}

  defp running_bundle(generation) do
    case Process.whereis(Elixos.Image) do
      nil -> {:error, :no_image}
      image -> Elixos.Image.coproc_bundle(image, generation)
    end
  end

  defp restart_under_supervisor do
    supervisor = Process.whereis(Elixos.Supervisor)

    if supervisor && Enum.any?(Supervisor.which_children(supervisor), &match?({__MODULE__, _, _, _}, &1)) do
      _ = Supervisor.terminate_child(supervisor, __MODULE__)
      _ = Supervisor.restart_child(supervisor, __MODULE__)
    end

    :ok
  end

  defp dir, do: Path.join(Application.get_env(:elixos, :priv_dir, "/priv"), "coproc")
  defp config_path, do: Path.join(dir(), "config.exs")
  defp cookie_path, do: Path.join(dir(), "cookie")

  ## GenServer

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    peer = Keyword.fetch!(opts, :node)
    {listen_address, listen_port} = Keyword.fetch!(opts, :listen)
    port = Keyword.get(opts, :port, @default_port)
    name = Keyword.get(opts, :name, :"elixos@#{:inet.ntoa(listen_address)}")

    with {:ok, address} <- peer_address(peer, Keyword.get(opts, :address)),
         :ok <- start_distribution(name, listen_address, listen_port, {peer, address, port},
                                   Keyword.fetch!(opts, :cookie)) do
      send(self(), :connect)

      {:ok,
       %{
         peer: peer,
         up: false,
         digest: nil,
         wanted: wanted(Keyword.get(opts, :bundle, :unmanaged)),
         deployed: nil,
         waiting: [],
         timer: nil,
         reconnect_ms: Keyword.get(opts, :reconnect_ms, @reconnect_ms),
         # subsystem => %{subscriber pid => monitor ref}
         subscribers: %{},
         # subsystem => {driver pid, last sequence number delivered}
         seen: %{}
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:node, _from, state), do: {:reply, state.peer, state}

  def handle_call(:status, _from, state) do
    {:reply,
     %{node: state.peer, connected: state.up, digest: state.digest,
       wanted: wanted_digest(state.wanted)}, state}
  end

  def handle_call({:deploy, bundle, timeout}, from, state) do
    ref = make_ref()
    Process.send_after(self(), {:deploy_timeout, ref}, timeout)
    state = %{state | wanted: wanted(bundle), deployed: nil, waiting: [{ref, from} | state.waiting]}
    {:noreply, sync(state)}
  end

  def handle_call({:subscribe, subsystem, pid}, _from, state) do
    pids = Map.get(state.subscribers, subsystem, %{})

    if Map.has_key?(pids, pid) do
      {:reply, :ok, state}
    else
      pids = Map.put(pids, pid, Process.monitor(pid))
      state = put_in(state.subscribers[subsystem], pids)
      # Subscribing again is harmless: the driver resends what it still
      # queues, and whatever was delivered already is dropped as a duplicate.
      {:reply, :ok, remote_subscribe(state, subsystem)}
    end
  end

  def handle_call({:unsubscribe, subsystem, pid}, _from, state) do
    case Map.get(state.subscribers, subsystem, %{}) do
      %{^pid => ref} ->
        Process.demonitor(ref, [:flush])
        {:reply, :ok, drop_subscriber(state, subsystem, pid)}

      _ ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(:connect, state) do
    state = %{state | timer: nil}

    case Node.connect(state.peer) do
      true -> {:noreply, up(state)}
      _ -> {:noreply, schedule(state)}
    end
  end

  def handle_info({:nodeup, peer, _info}, %{peer: peer} = state), do: {:noreply, up(state)}

  def handle_info({:nodedown, peer, _info}, %{peer: peer} = state) do
    {:noreply, schedule(%{state | up: false})}
  end

  # A driver event (os/src/coproc_driver.erl): fanned out to the subsystem's
  # subscribers, then acknowledged so the driver stops queueing it. Without a
  # subscriber it is left unacknowledged: the driver keeps it for the next.
  def handle_info({:coproc_event, name, driver, seq, event}, state) do
    with {:ok, subsystem} <- subsystem(name),
         pids when map_size(pids) > 0 <- Map.get(state.subscribers, subsystem, %{}) do
      unless duplicate?(state.seen, subsystem, driver, seq) do
        for pid <- Map.keys(pids), do: send(pid, event)
      end

      GenServer.cast(driver, {:ack, seq})
      {:noreply, put_in(state.seen[subsystem], {driver, max_seen(state.seen, subsystem, driver, seq)})}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state =
      Enum.reduce(state.subscribers, state, fn {subsystem, pids}, state ->
        if Map.has_key?(pids, pid), do: drop_subscriber(state, subsystem, pid), else: state
      end)

    {:noreply, state}
  end

  def handle_info({:deploy_timeout, ref}, state) do
    case List.keytake(state.waiting, ref, 0) do
      {{^ref, from}, waiting} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | waiting: waiting}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state) do
    _ = :net_kernel.stop()
    Epmd.clear()

    # During a VM shutdown the application controller is going too, and a
    # call to it would only fail; the environment goes with the VM anyway.
    try do
      Application.delete_env(:kernel, :epmd_module)
      Application.delete_env(:kernel, :inet_dist_use_interface)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  ## Internals

  defp start_distribution(name, listen_address, listen_port, {peer, _, _} = target, cookie) do
    if Node.alive?() do
      {:error, {:already_distributed, Kernel.node()}}
    else
      Epmd.configure(listen_port, target)
      Application.put_env(:kernel, :epmd_module, Epmd)
      Application.put_env(:kernel, :inet_dist_use_interface, listen_address)

      case :net_kernel.start(name, %{name_domain: :longnames}) do
        {:ok, _pid} ->
          cookie = String.to_atom(cookie)
          true = :erlang.set_cookie(cookie)
          true = :erlang.set_cookie(peer, cookie)
          :ok = :net_kernel.monitor_nodes(true, node_type: :all)
          :ok

        {:error, reason} ->
          Epmd.clear()
          Application.delete_env(:kernel, :epmd_module)
          Application.delete_env(:kernel, :inet_dist_use_interface)
          {:error, {:distribution, reason}}
      end
    end
  end

  defp peer_address(_peer, {_, _, _, _} = address), do: {:ok, address}

  defp peer_address(peer, nil) do
    with [_name, host] <- String.split(Atom.to_string(peer), "@", parts: 2),
         {:ok, {_, _, _, _} = address} <- :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, address}
    else
      _ -> {:error, {:peer_address, peer}}
    end
  end

  defp up(%{up: true} = state), do: state

  # The peer is (back) up: converge on the wanted bundle, then renew every
  # subscription - the peer's drivers may be new (a restarted coprocessor), or
  # the old ones holding events queued while the link was down.
  defp up(state) do
    state = sync(%{state | up: true})
    Enum.reduce(Map.keys(state.subscribers), state, &remote_subscribe(&2, &1))
  end

  defp remote_subscribe(%{up: false} = state, _subsystem), do: state

  defp remote_subscribe(state, subsystem) do
    name = Map.fetch!(@drivers, subsystem)

    case erpc(state.peer, :coproc_driver, :subscribe, [name, self()], @call_timeout) do
      {:ok, {:ok, _driver}} ->
        state

      other ->
        Logger.warning("Elixos.Coproc: subscribing to #{name} on #{state.peer} failed: #{inspect(other)}")
        state
    end
  end

  defp drop_subscriber(state, subsystem, pid) do
    pids = state.subscribers |> Map.fetch!(subsystem) |> Map.delete(pid)

    if map_size(pids) == 0 do
      if state.up do
        _ = erpc(state.peer, :coproc_driver, :unsubscribe, [Map.fetch!(@drivers, subsystem), self()], @call_timeout)
      end

      %{state | subscribers: Map.delete(state.subscribers, subsystem)}
    else
      %{state | subscribers: Map.put(state.subscribers, subsystem, pids)}
    end
  end

  defp subsystem(name) do
    case Enum.find(@drivers, fn {_subsystem, driver} -> driver == name end) do
      {subsystem, _driver} -> {:ok, subsystem}
      nil -> :error
    end
  end

  # Events are numbered per driver process; a new driver starts a new series.
  defp duplicate?(seen, subsystem, driver, seq) do
    match?({^driver, last} when seq <= last, Map.get(seen, subsystem))
  end

  defp max_seen(seen, subsystem, driver, seq) do
    case Map.get(seen, subsystem) do
      {^driver, last} -> max(last, seq)
      _ -> seq
    end
  end

  defp schedule(%{timer: nil} = state) do
    %{state | timer: Process.send_after(self(), :connect, state.reconnect_ms)}
  end

  defp schedule(state), do: state

  # The peer is up: learn what it runs, and deploy what it should run when
  # that differs - once per wanted bundle, so a coprocessor that cannot take
  # it is reported instead of being restarted forever.
  defp sync(%{up: false} = state), do: state

  defp sync(state) do
    case erpc(state.peer, :elixos_coproc, :digest, [], @call_timeout) do
      {:ok, digest} ->
        digest = if digest == :none, do: :none, else: to_string(digest)
        state = %{state | digest: digest}
        converge(state, wanted_digest(state.wanted))

      {:error, reason} ->
        Logger.warning("Elixos.Coproc: #{state.peer} did not report its bundle: #{inspect(reason)}")
        state
    end
  end

  defp converge(state, :unmanaged), do: reply_waiting(state, {:ok, state.digest})
  defp converge(%{digest: digest} = state, digest), do: reply_waiting(state, {:ok, digest})

  defp converge(%{deployed: wanted} = state, wanted) do
    Logger.error("Elixos.Coproc: #{state.peer} still runs #{state.digest} after deploying #{wanted}")
    reply_waiting(state, {:error, {:deploy_failed, state.digest}})
  end

  defp converge(state, wanted) do
    {_digest, bundle} = state.wanted
    Logger.info("Elixos.Coproc: deploying bundle #{inspect(wanted)} to #{state.peer}")

    case erpc(state.peer, :elixos_coproc, :deploy, [bundle || :none], 30_000) do
      # The coprocessor restarts on it: the next nodeup checks the result.
      {:ok, :ok} -> %{state | deployed: wanted}
      {:ok, error} -> reply_waiting(state, {:error, {:deploy, error}})
      {:error, reason} -> reply_waiting(state, {:error, {:deploy, reason}})
    end
  end

  defp reply_waiting(state, reply) do
    for {_ref, from} <- state.waiting, do: GenServer.reply(from, reply)
    %{state | waiting: []}
  end

  defp wanted(:unmanaged), do: :unmanaged
  defp wanted(nil), do: {:none, nil}
  defp wanted(bundle) when is_binary(bundle), do: {Bundle.digest(bundle), bundle}

  defp wanted_digest(:unmanaged), do: :unmanaged
  defp wanted_digest({digest, _bundle}), do: digest

  defp erpc(node, module, function, args, timeout) do
    {:ok, :erpc.call(node, module, function, args, timeout)}
  rescue
    error in ErlangError -> {:error, error.original}
  catch
    :exit, reason -> {:error, reason}
  end

  defp valid(nil), do: :ok

  defp valid(bundle) do
    case Bundle.modules(bundle) do
      {:ok, _modules, _start} -> :ok
      error -> error
    end
  end

  defp bytecode(module) do
    with image when is_pid(image) <- Process.whereis(Elixos.Image),
         {:ok, bytecode} <- Elixos.Image.bytecode(image, module) do
      {:ok, bytecode}
    else
      _ -> object_code(module)
    end
  end

  defp object_code(module) do
    case :code.get_object_code(module) do
      {^module, bytecode, _path} -> {:ok, bytecode}
      :error -> {:error, {:no_object_code, module}}
    end
  end
end
