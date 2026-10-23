defmodule Elixos.Test.CoprocFirmware do
  @moduledoc """
  The bare-metal coprocessor firmware (M32, `coproc/`,
  docs/notes/coproc-firmware.md) on QEMU's virt machine, linked to the host
  through the §11 ring (docs/PROTOCOL.md).

  `boot/2` packs a payload (the coprocessor runtime from
  `Elixos.Coproc.runtime/0`, the firmware's own `atomvmlib.avm`, the cookie
  and the configuration block) with the firmware's `mkpayload.py`, and starts
  `qemu-system-riscv64 -M virt -bios none` on `coproc-qemu-virt.elf` with
  guest RAM in a shared file. The ring lives in that file at guest physical
  `0x81000000`, file offset 16 MiB (`@ring_offset`, the firmware's qemu-virt
  `COPROC_RING_ADDR`). `link/2` attaches `elixos-link --side big` to it in
  an unprivileged user and network namespace, as `Elixos.Test.RingLink` does
  for M31, and returns a `%Elixos.Test.RingLink{}` whose `cmd/3` runs programs
  in that namespace.

  The firmware, `atomvmlib.avm` and `mkpayload.py` come from
  `scripts/build-coproc-firmware.sh` (`build/coproc/`). Missing artifacts or
  tools fail the test with the reason; nothing is skipped. Timeouts scale
  with `ELIXOS_QEMU_SLOWDOWN`.
  """

  use GenServer

  @ram_size "256M"
  @load_payload "0x80400000"
  @ring_offset 0x1000000
  @ring_size 0x21000

  @enforce_keys [:pid, :os_pid, :dir]
  defstruct [:pid, :os_pid, :dir]

  @type t :: %__MODULE__{pid: pid(), os_pid: pos_integer(), dir: Path.t()}

  @doc "The firmware's ring region size S (`COPROC_RING_SIZE`)."
  def ring_size, do: @ring_size

  @doc """
  Boots the firmware in `dir`. Options: `cookie:` (required), `node:`
  (default `coproc@10.0.3.9`), `address:` (default `10.0.3.9/24`), `port:`
  (default 4370). Stopped when the test exits.
  """
  @spec boot(Path.t(), keyword()) :: t()
  def boot(dir, opts) do
    File.mkdir_p!(dir)
    payload = payload!(dir, opts)
    region = Path.join(dir, "ram.img")
    File.rm(region)
    {_, 0} = System.cmd("truncate", ["-s", @ram_size, region])

    qemu = executable!("qemu-system-riscv64")

    args = [
      "-M", "virt", "-bios", "none", "-m", @ram_size,
      "-object", "memory-backend-file,id=ram,size=#{@ram_size},mem-path=#{qemu_escape(region)},share=on",
      "-machine", "memory-backend=ram",
      "-kernel", artifact("coproc-qemu-virt.elf"),
      "-device", "loader,file=#{qemu_escape(payload)},addr=#{@load_payload}",
      "-nographic", "-monitor", "none", "-serial", "stdio"
    ]

    start_process(qemu, args, dir, Path.join(dir, "console.log"))
  end

  # QEMU option values double a literal comma (ExUnit's tmp_dir has them).
  defp qemu_escape(path), do: String.replace(path, ",", ",,")

  @doc """
  Starts `elixos-link --side big` on the firmware's ring, with `address:`
  (default `10.0.3.15/24`) on TUN `ring0`, in a new user and network
  namespace whose loopback is up. Waits for its `up` line.
  """
  @spec link(t(), keyword()) :: Elixos.Test.RingLink.t()
  def link(%__MODULE__{dir: dir}, opts \\ []) do
    address = Keyword.get(opts, :address, "10.0.3.15/24")
    unshare = executable!("unshare")

    script =
      "echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 && " <>
        "echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 && " <>
        "ip link set lo up && exec \"$0\" \"$@\""

    argv =
      ["--user", "--map-root-user", "--net", "sh", "-c", script, Elixos.Test.RingLink.binary()] ++
        ["--side", "big", "--region", Path.join(dir, "ram.img"), "--offset", "#{@ring_offset}"] ++
        ["--size", "#{@ring_size}", "--tun", "ring0", "--address", address]

    process = start_process(unshare, argv, dir, Path.join(dir, "link.log"))
    await(process, ~r/elixos-link: up ring0 region #{@ring_size} bytes\n/, 15_000)
    %Elixos.Test.RingLink{pid: process.pid, os_pid: process.os_pid, tun: "ring0"}
  end

  @doc "Waits until the process's output matches `pattern`; returns the output."
  def await(%{pid: pid}, pattern, timeout \\ 30_000) do
    timeout = scaled(timeout)

    case GenServer.call(pid, {:await, pattern}, :infinity) |> receive_ref(timeout) do
      {:ok, output} ->
        output

      {:exited, status, output} ->
        ExUnit.Assertions.flunk("exited #{status} before #{inspect(pattern)}:\n" <> output)

      :timeout ->
        ExUnit.Assertions.flunk("no #{inspect(pattern)} in #{timeout} ms:\n" <> output(%{pid: pid}))
    end
  end

  @doc "Everything the process printed so far."
  def output(%{pid: pid}), do: GenServer.call(pid, :output)

  defp receive_ref(ref, timeout) do
    receive do
      {^ref, result} -> result
    after
      timeout -> :timeout
    end
  end

  defp scaled(timeout), do: timeout * String.to_integer(System.get_env("ELIXOS_QEMU_SLOWDOWN", "1"))

  defp payload!(dir, opts) do
    cookie = Keyword.fetch!(opts, :cookie)
    {:ok, runtime} = Elixos.Coproc.runtime()
    runtime_file = Path.join(dir, "runtime.avm")
    cookie_file = Path.join(dir, "cookie")
    payload = Path.join(dir, "payload.bin")
    File.write!(runtime_file, runtime)
    File.write!(cookie_file, cookie <> "\n")
    seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    env = [
      "ELIXOS_COPROC_NODE=" <> Keyword.get(opts, :node, "coproc@10.0.3.9"),
      "ELIXOS_COPROC_PORT=#{Keyword.get(opts, :port, 4370)}",
      "ELIXOS_COPROC_COOKIE_FILE=cookie",
      "ELIXOS_COPROC_BUNDLE=bundle.avm",
      "ELIXOS_COPROC_DRIVERS=sim",
      "ELIXOS_COPROC_ADDRESS=" <> Keyword.get(opts, :address, "10.0.3.9/24"),
      "ELIXOS_COPROC_SEED=" <> seed
    ]

    args =
      [artifact("mkpayload.py"), "-o", payload] ++
        Enum.flat_map(env, &["--env", &1]) ++
        ["--avm", runtime_file, "--avm", artifact("atomvmlib.avm"), "--file", "cookie=" <> cookie_file]

    {output, status} = System.cmd(executable!("python3"), args, stderr_to_stdout: true)
    status == 0 || ExUnit.Assertions.flunk("mkpayload failed:\n" <> output)
    payload
  end

  @doc "A firmware build artifact under `build/coproc/`."
  def artifact(name) do
    path = Elixos.Test.Paths.build(Path.join("coproc", name))

    File.exists?(path) ||
      ExUnit.Assertions.flunk("missing #{path}; run scripts/build-coproc-firmware.sh first")

    path
  end

  defp executable!(name) do
    System.find_executable(name) || ExUnit.Assertions.flunk("#{name} is not on PATH")
  end

  defp start_process(program, args, dir, log) do
    {:ok, pid} = GenServer.start(__MODULE__, {program, args, log})
    ExUnit.Callbacks.on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %__MODULE__{pid: pid, os_pid: GenServer.call(pid, :os_pid), dir: dir}
  end

  ## GenServer: one external process, its output and the callers waiting on it

  @impl true
  def init({program, args, log}) do
    Process.flag(:trap_exit, true)

    port =
      Port.open({:spawn_executable, program}, [:binary, :exit_status, :stderr_to_stdout, args: args])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    {:ok, %{port: port, os_pid: os_pid, log: log, output: "", status: nil, waiting: []}}
  end

  @impl true
  def handle_call(:os_pid, _from, state), do: {:reply, state.os_pid, state}
  def handle_call(:output, _from, state), do: {:reply, state.output, state}

  def handle_call({:await, pattern}, {caller, _}, state) do
    ref = make_ref()
    {:reply, ref, answer(%{state | waiting: [{pattern, caller, ref} | state.waiting]})}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    File.write!(state.log, data, [:append])
    {:noreply, answer(%{state | output: state.output <> data})}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state),
    do: {:noreply, answer(%{state | status: status})}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{status: nil, os_pid: os_pid}) do
    System.cmd("kill", ["-KILL", Integer.to_string(os_pid)])
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp answer(state) do
    {ready, waiting} =
      Enum.split_with(state.waiting, fn {pattern, _, _} ->
        Regex.match?(pattern, state.output) or state.status != nil
      end)

    for {pattern, caller, ref} <- ready do
      result =
        if Regex.match?(pattern, state.output),
          do: {:ok, state.output},
          else: {:exited, state.status, state.output}

      send(caller, {ref, result})
    end

    %{state | waiting: waiting}
  end
end
