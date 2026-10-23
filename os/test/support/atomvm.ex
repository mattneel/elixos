defmodule Elixos.Test.AtomVM do
  @moduledoc """
  The coprocessor stand-in (M29): AtomVM's Unix build on the host
  (`build/atomvm/`, `make atomvm`), running Elixos's coprocessor runtime.

  Like whatever loads a real coprocessor, the launcher restarts the VM every
  time it exits: a deploy stores the new bundle and ends AtomVM
  (`:elixos_coproc.deploy/1`), and a killed AtomVM comes back as well. Every
  start prints `elixos_coproc: <node> up, bundle <digest>`; `await_up/3` waits
  for the n-th one, `starts/1` counts them.

  The runtime's drivers (M32) run their simulated backends
  (`ELIXOS_COPROC_DRIVERS=sim`): AtomVM's standard output stands in for
  UART3, and `Elixos.Coproc.simulate/2` for the hardware.

  AtomVM's distribution binds 0.0.0.0 on the fixed port (ADR-098), and its epmd
  4369 unless the host already runs one.
  """

  use GenServer

  @enforce_keys [:pid, :node, :port, :dir]
  defstruct [:pid, :node, :port, :dir]

  @type t :: %__MODULE__{pid: pid(), node: node(), port: :inet.port_number(), dir: Path.t()}

  @doc """
  Starts AtomVM in `dir`. Options: `cookie:` (required), `node:` (default
  `coproc@127.0.0.1`), `port:` (default: a free one), `bundle:` the initial
  bundle (default none). Stopped when the test exits.
  """
  @spec start(Path.t(), keyword()) :: t()
  def start(dir, opts) do
    File.mkdir_p!(dir)
    node = Keyword.get(opts, :node, :"coproc@127.0.0.1")
    port = Keyword.get_lazy(opts, :port, &free_port/0)
    cookie_file = Path.join(dir, "cookie")
    bundle_file = Path.join(dir, "bundle.avm")
    runtime_file = Path.join(dir, "runtime.avm")

    {:ok, runtime} = Elixos.Coproc.runtime()
    File.write!(runtime_file, runtime)
    File.write!(cookie_file, Keyword.fetch!(opts, :cookie) <> "\n")

    # A fresh coprocessor: no bundle unless given, nothing handed off.
    File.rm(bundle_file <> ".drivers")

    case Keyword.get(opts, :bundle) do
      nil -> File.rm(bundle_file)
      bundle -> File.write!(bundle_file, bundle)
    end

    env = [
      {~c"ELIXOS_COPROC_NODE", Atom.to_charlist(node)},
      {~c"ELIXOS_COPROC_PORT", Integer.to_charlist(port)},
      {~c"ELIXOS_COPROC_COOKIE_FILE", String.to_charlist(cookie_file)},
      {~c"ELIXOS_COPROC_BUNDLE", String.to_charlist(bundle_file)},
      {~c"ELIXOS_COPROC_DRIVERS", ~c"sim"}
    ]

    args = [runtime_file, artifact("atomvmlib.avm")]
    {:ok, pid} = GenServer.start(__MODULE__, {artifact("AtomVM"), args, env, dir})
    ExUnit.Callbacks.on_exit(fn -> stop(pid) end)
    %__MODULE__{pid: pid, node: node, port: port, dir: dir}
  end

  @doc "Waits until AtomVM has come up `count` times in all, and returns the last bundle digest it reported."
  @spec await_up(t(), pos_integer(), timeout()) :: String.t()
  def await_up(%__MODULE__{pid: pid}, count \\ 1, timeout \\ 30_000) do
    GenServer.call(pid, {:await_up, count}, timeout)
  end

  @doc "How many times AtomVM has come up so far."
  @spec starts(t()) :: non_neg_integer()
  def starts(%__MODULE__{pid: pid}), do: GenServer.call(pid, :starts)

  @doc "Kills the running AtomVM (SIGKILL); the launcher starts it again."
  @spec kill(t()) :: :ok
  def kill(%__MODULE__{pid: pid}) do
    os_pid = GenServer.call(pid, :os_pid)
    {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(os_pid)])
    :ok
  end

  @doc "Everything AtomVM printed, across restarts."
  @spec output(t()) :: String.t()
  def output(%__MODULE__{pid: pid}), do: GenServer.call(pid, :output)

  @doc "The digest of the bundle file the runtime would load, or `nil`."
  @spec bundle_digest(t()) :: String.t() | nil
  def bundle_digest(%__MODULE__{dir: dir}) do
    case File.read(Path.join(dir, "bundle.avm")) do
      {:ok, bundle} -> Elixos.Coproc.Bundle.digest(bundle)
      {:error, :enoent} -> nil
    end
  end

  @doc "A free TCP port on the loopback interface."
  @spec free_port() :: :inet.port_number()
  def free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, reuseaddr: true)
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp stop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid)
    :ok
  end

  defp artifact(name) do
    path = Elixos.Test.Paths.build(Path.join("atomvm", name))
    File.exists?(path) || ExUnit.Assertions.flunk("missing #{path}; run `make atomvm` first")
    path
  end

  ## GenServer

  @impl true
  def init({binary, args, env, dir}) do
    Process.flag(:trap_exit, true)
    state = %{binary: binary, args: args, env: env, log: Path.join(dir, "atomvm.log"),
              output: "", ups: [], waiting: [], port: nil}
    {:ok, launch(state)}
  end

  @impl true
  def handle_call({:await_up, count}, from, state) do
    {:noreply, answer(%{state | waiting: [{count, from} | state.waiting]})}
  end

  def handle_call(:os_pid, _from, state) do
    {:os_pid, os_pid} = Port.info(state.port, :os_pid)
    {:reply, os_pid, state}
  end

  def handle_call(:output, _from, state), do: {:reply, state.output, state}
  def handle_call(:starts, _from, state), do: {:reply, length(state.ups), state}

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    File.write!(state.log, data, [:append])
    output = state.output <> data

    ups =
      Regex.scan(~r/elixos_coproc: \S+ up, bundle (\S+)/, output, capture: :all_but_first)
      |> List.flatten()

    {:noreply, answer(%{state | output: output, ups: ups})}
  end

  def handle_info({port, {:exit_status, _status}}, %{port: port} = state) do
    {:noreply, launch(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: port}) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> System.cmd("kill", ["-KILL", Integer.to_string(os_pid)])
      nil -> :ok
    end

    :ok
  end

  defp launch(state) do
    port =
      Port.open({:spawn_executable, state.binary}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: state.args,
        env: state.env
      ])

    %{state | port: port}
  end

  defp answer(state) do
    {ready, waiting} = Enum.split_with(state.waiting, fn {count, _from} -> length(state.ups) >= count end)
    for {count, from} <- ready, do: GenServer.reply(from, Enum.at(state.ups, count - 1))
    %{state | waiting: waiting}
  end
end
