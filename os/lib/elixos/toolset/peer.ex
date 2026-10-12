defmodule Elixos.Toolset.Peer do
  @moduledoc """
  The supervised tool-host peer (M21, ADR-047).

  The OS supervisor owns this keeper on both host and image. Its first
  `node/0`, `fetch/0` or `run/4` boots a second BEAM using raw `erlexec` and
  starts QuickBEAM there, never in the main VM. A peer failure leaves the
  keeper and the OS alive; a later call boots a replacement without replaying
  the interrupted call.

  `run/4` binds execution to the actual peer controller, not just its reusable
  node name. Names rotate through 128 slots to bound atom growth across
  crashes; the controller PID distinguishes every incarnation. Direct RPC
  users of `node/0` must not retain that name across peer loss.

  Child-local environment/code-path setup never changes the main VM's cwd or
  environment. No `erl` shell script is exec'd, and peer crash dumps are
  disabled because tool state can contain credentials. Contexts use
  `QuickBEAM.ContextPool`/`QuickBEAM.Context` with `apis: false`, positive heap
  and reduction budgets, and a deadline on every eval/call.
  """

  use GenServer

  # This module's node/0 returns the peer; the main VM's own name is always
  # spelled Kernel.node() here.
  import Kernel, except: [node: 0]

  alias Elixos.Toolset.Peer.Bootstrap

  @name __MODULE__
  @run_table :elixos_tool_runs

  # The parent and the peer are always on the same host, so the distribution
  # domain is the loopback address: resolvable without DNS or /etc/hosts.
  @host "127.0.0.1"

  @parent_prefix "elixos"
  @peer_prefix "elixos_tool"
  @peer_name_slots 128
  @counter_key {__MODULE__, :name_counter}

  # Bounded waits. The peer boots in a few hundred milliseconds on the dev
  # host; 15 s is :peer's own default. Starting the engine is a load of two
  # applications and a NIF.
  @boot_timeout 15_000
  @engine_timeout 30_000

  # Kill's bound: {:halt, N} sends erlang:halt/0 to the peer and force-closes
  # the control connection after N ms (1 000 is :peer's minimum).
  @disconnect_timeout 1_000

  # Context policy, deliberate and documented: a small JS heap is enough for
  # the pure cores and refused allocations must fail early; the reduction
  # budget is ~10 000 interpreter steps per unit, so this interrupts a runaway
  # loop in well under a second, and a caller with a longer deadline passes its
  # own :timeout per eval/call.
  @memory_limit 64 * 1024 * 1024
  @max_reductions 50_000
  @timeout 5_000

  @doc """
  Returns the live tool-host peer node, starting the peer if needed.

  Raises a `RuntimeError` when no peer can be started; `fetch/0` returns that
  failure instead. The node is never the main VM's own node (`Kernel.node/0`)
  and remains usable until `kill/0` or the peer's death.
  """
  @spec node() :: node()
  def node do
    case fetch() do
      {:ok, node} -> node
      {:error, reason} -> raise "tool host unavailable: #{inspect(reason)}"
    end
  end

  @doc """
  Returns `{:ok, node}` for the live tool-host peer, or the boot failure.

  Failures: `{:error, {:distribution_failed, reason}}` when the main VM cannot
  be distributed, `{:error, {:boot_failed, reason}}` when the peer does not
  boot, `{:error, {:engine_failed, reason}}` when QuickBEAM does not start in
  it, and `{:error, :unavailable}` - or `{:error, {:unavailable, reason}}` when
  asking the owner exits - when the owner process cannot be reached or started.
  All are local to one call; the next call tries a fresh peer.
  """
  @spec fetch() :: {:ok, node()} | {:error, term()}
  def fetch do
    case owner() do
      {:ok, owner} -> GenServer.call(owner, :node, :infinity)
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, reason -> {:error, {:unavailable, reason}}
  end

  @doc "Executes once through a specific peer controller and returns its node with the result."
  @spec run(module(), atom(), [term()], timeout()) ::
          {:ok, node(), term()} | {:error, term()}
  def run(module, function, arguments, timeout \\ @timeout) do
    with {:ok, owner} <- owner(),
         {:ok, {controller, node}} <- GenServer.call(owner, :host, :infinity) do
      {:ok, node, :peer.call(controller, module, function, arguments, timeout)}
    end
  catch
    :exit, reason -> {:error, {:tool_host_down, reason}}
  end

  @doc "Records a completed call's observed backend, revision and peer node."
  def record(%{tool: tool} = record), do: :ets.insert(@run_table, {tool, record})

  @doc "The last observed run, or nil before the tool has run."
  def last_run(tool) do
    case :ets.lookup(@run_table, tool) do
      [{^tool, record}] -> record
      [] -> nil
    end
  end

  @doc """
  Stops the current tool-host peer, interrupting in-flight calls.

  The call returns once the peer node is down (:peer's halt shutdown) or its
  control connection has been forcibly closed. Calls already crossing the
  boundary fail with `{:erpc, :noconnection}` and are not replayed; the
  effects of a call that was interrupted may or may not have happened. The next
  `node/0` starts a fresh, differently named peer. Stopping a peer twice, or
  stopping when none exists, is `:ok`.
  """
  @spec kill() :: :ok
  def kill do
    case Process.whereis(@name) do
      nil -> :ok
      owner -> GenServer.call(owner, :kill, :infinity)
    end
  catch
    :exit, _reason -> :ok
  end

  @doc """
  Returns the context policy for the tool host.

  The list is passed to `QuickBEAM.ContextPool`/`QuickBEAM.Context` (merged
  with call-site overrides) and its `:timeout` to every `eval`/`call`:

    * `:apis` - `false`: no browser, DOM or Node APIs; in particular no
      `process.env`, whose writes would reach `System.put_env/2` in the peer's
      VM. The sandbox exposes no `process`, `Bun` or `fetch`.
    * `:memory_limit` - positive JS heap budget in bytes, enforced per context
      (and per pool thread).
    * `:max_reductions` - positive reduction budget, enforced per context and
      reset per eval/call; an exhausted budget raises a QuickJS
      `InternalError: interrupted` without a wall-clock deadline.
    * `:timeout` - positive per-call timeout in milliseconds; a call still
      running at the deadline is interrupted the same way.
  """
  @spec quickbeam_options() :: keyword()
  def quickbeam_options do
    [
      apis: false,
      memory_limit: @memory_limit,
      max_reductions: @max_reductions,
      timeout: @timeout
    ]
  end

  @doc """
  Starts the idle peer owner under `Elixos.Supervisor`; no engine boots here.

  The first call boots the peer. Losing that peer never stops its owner.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link([]), do: GenServer.start_link(__MODULE__, :ok, name: @name)

  def start_link(opts), do: {:error, {:unsupported_options, opts}}

  @doc """
  Supervisor child specification, usable directly under `Elixos.Supervisor`.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @impl true
  def init(:ok) do
    # Know when the peer's control process goes away; an abnormal exit must not
    # take the owner (or the OS supervisor) with it.
    Process.flag(:trap_exit, true)
    :ets.new(@run_table, [:named_table, :public, read_concurrency: true])

    case :persistent_term.get(@counter_key, nil) do
      nil -> :persistent_term.put(@counter_key, :atomics.new(1, []))
      _counter -> :ok
    end

    {:ok, %{ctl: nil, node: nil}}
  end

  @impl true
  def handle_call(:node, _from, state) do
    case ensure_peer(state) do
      {:ok, node, state} -> {:reply, {:ok, node}, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:host, _from, state) do
    case ensure_peer(state) do
      {:ok, node, state} -> {:reply, {:ok, {state.ctl, node}}, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:kill, _from, state) do
    {:reply, :ok, stop_peer(state)}
  end

  @impl true
  def handle_info({:EXIT, ctl, _reason}, %{ctl: ctl} = state), do: {:noreply, forget(state)}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = stop_peer(state)
    :ok
  end

  defp owner do
    case Process.whereis(@name) do
      nil -> {:error, :unavailable}
      pid -> {:ok, pid}
    end
  end

  # -- peer lifecycle --------------------------------------------------------

  defp ensure_peer(%{ctl: ctl, node: node} = state) when is_pid(ctl) and is_atom(node) do
    if Process.alive?(ctl), do: {:ok, node, state}, else: start_peer(forget(state))
  end

  defp ensure_peer(state), do: start_peer(state)

  defp start_peer(state) do
    case boot_peer() do
      {:ok, ctl, node} -> {:ok, node, %{state | ctl: ctl, node: node}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp boot_peer do
    with {:ok, host} <- host_part(),
         {:ok, exec} <- exec_path(),
         {:ok, boot} <- boot_script() do
      name = peer_name(host)

      case peer_start(name, exec, boot) do
        {:ok, ctl, node} ->
          case bootstrap(node) do
            :ok ->
              {:ok, ctl, node}

            {:error, reason} ->
              _ = stop_controller(ctl)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # -- distribution ----------------------------------------------------------

  # The peer needs both VMs distributed; nothing else in the OS starts
  # distribution, so the main VM starts it with this module's name on first
  # use. A VM that is already distributed (a future caller, a test harness)
  # lends its host part and keeps its cookie.
  defp host_part do
    if Node.alive?() do
      host_of(Kernel.node())
    else
      case Node.start(String.to_atom("#{@parent_prefix}_#{System.pid()}@#{@host}"), :longnames) do
        {:ok, _pid} -> host_of(Kernel.node())
        {:error, {:already_started, _pid}} -> host_of(Kernel.node())
        {:error, reason} -> {:error, {:distribution_failed, reason}}
      end
    end
  end

  defp host_of(node_name) do
    case node_name |> Atom.to_string() |> String.split("@") do
      [_name, host] when host != "" -> {:ok, host}
      _other -> {:error, {:distribution_failed, {:unnamed, node_name}}}
    end
  end

  defp peer_name(host) do
    counter = :persistent_term.get(@counter_key)
    slot = rem(:atomics.add_get(counter, 1, 1), @peer_name_slots)
    "#{@peer_prefix}_#{System.pid()}_#{slot}@#{host}"
  end

  # -- the peer command ------------------------------------------------------

  defp peer_start(name, exec, boot) do
    options = %{
      name: String.to_charlist(name),
      longnames: :net_kernel.longnames(),
      exec: exec,
      args: peer_args(boot),
      env: peer_env(exec),
      # Distribution is the control channel's transport too; loopback only.
      connection: {{127, 0, 0, 1}, 0},
      shutdown: {:halt, @disconnect_timeout},
      peer_down: :stop,
      wait_boot: @boot_timeout
    }

    try do
      case :peer.start_link(options) do
        {:ok, ctl, node} ->
          {:ok, ctl, node}

        {:ok, ctl} ->
          # No node name came back: a peer that cannot be addressed is useless,
          # and leaving its controller linked would leak it.
          _ = stop_controller(ctl)
          {:error, {:boot_failed, :no_node}}

        other ->
          {:error, {:boot_failed, {:unexpected_start, other}}}
      end
    catch
      :exit, reason -> {:error, {:boot_failed, reason}}
    end
  end

  # :peer prepends the emulator and the -name/-sname flags; the rest is this
  # VM's identity (one cookie), one minimal boot, and the main VM's code path.
  # -pa prepends its arguments in reverse, so the reverse of the parent's path
  # gives the peer the same resolution order.
  defp peer_args(boot) do
    [
      ~c"-boot",
      boot,
      ~c"-mode",
      ~c"interactive",
      ~c"-noshell",
      ~c"-setcookie",
      Atom.to_charlist(Node.get_cookie()),
      ~c"-pa"
      | Enum.reverse(:code.get_path())
    ]
  end

  defp peer_env(exec) do
    [
      # erlexec reads these instead of the erl script having set them.
      {~c"ROOTDIR", :code.root_dir()},
      {~c"BINDIR", charlist(Path.dirname(List.to_string(exec)))},
      {~c"EMU", ~c"beam"},
      {~c"PROGNAME", ~c"erl"},
      # Tool state may contain credentials; no peer heap is dumped.
      {~c"ERL_CRASH_DUMP", ~c"/dev/null"},
      {~c"ERL_CRASH_DUMP_BYTES", ~c"0"},
      # Nothing may inject flags into the peer's command line, and the peer is
      # not the OS: the shim's variables do not describe it.
      {~c"ERL_FLAGS", false},
      {~c"ERL_AFLAGS", false},
      {~c"ERL_ZFLAGS", false},
      {~c"ELIXOS_GENERATION", false},
      {~c"ELIXOS_MODE", false},
      {~c"ELIXOS_ATTEMPT", false},
      {~c"ELIXOS_CTL_FD", false},
      {~c"ELIXOS_REPLY_FD", false}
    ]
  end

  # Raw erlexec, never an erl script (the image ships none): the layout of a
  # dev ERTS, then the image's /factory/erts symlink, then whatever BINDIR the
  # running VM was launched with.
  defp exec_path do
    candidates =
      [
        Path.join([root_dir(), "erts-#{erts_version()}", "bin", "erlexec"]),
        Path.join([root_dir(), "erts", "bin", "erlexec"]),
        Path.join([System.get_env("BINDIR") || "", "erlexec"])
      ]

    case Enum.find(candidates, &File.exists?/1) do
      nil -> {:error, {:boot_failed, {:erlexec_missing, candidates}}}
      path -> {:ok, charlist(path)}
    end
  end

  # $ROOT/bin/no_dot_erlang is the kernel+stdlib boot without .erlang; :peer
  # appends ".boot" itself, and the factory image keeps exactly this one
  # script in bin/ (escript needs it too).
  defp boot_script do
    path = Path.join([root_dir(), "bin", "no_dot_erlang"])

    if File.exists?(path <> ".boot") do
      {:ok, charlist(path)}
    else
      {:error, {:boot_failed, {:boot_script_missing, path <> ".boot"}}}
    end
  end

  defp root_dir, do: List.to_string(:code.root_dir())
  defp erts_version, do: List.to_string(:erlang.system_info(:version))

  defp charlist(value) when is_binary(value), do: String.to_charlist(value)

  # -- starting the engine in the peer ---------------------------------------

  # The peer is only usable with the engine up: without this, the first context
  # a caller starts would race the application.
  defp bootstrap(node) do
    case :erpc.call(node, Bootstrap, :start, [], @engine_timeout) do
      :ok -> :ok
      {:error, reason} -> {:error, {:engine_failed, reason}}
    end
  catch
    :error, {:erpc, _reason} = reason -> {:error, {:engine_failed, reason}}
    :exit, reason -> {:error, {:engine_failed, reason}}
  end

  # -- stopping or losing the peer -------------------------------------------

  # :peer.stop/1 halts the node and waits (bounded by :shutdown) for its
  # distribution connection to come down, so a killed peer cannot be answered
  # by a replacement node.
  defp stop_controller(ctl) do
    if Process.alive?(ctl), do: :peer.stop(ctl)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp stop_peer(%{ctl: nil} = state), do: state

  defp stop_peer(%{ctl: ctl} = state) do
    _ = stop_controller(ctl)
    forget(state)
  end

  defp forget(state), do: %{state | ctl: nil, node: nil}
end
