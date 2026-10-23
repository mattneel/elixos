defmodule Elixos.CoprocDriversTest do
  @moduledoc """
  M32: the coprocessor exposes the subsystems the M30 gate assigned it as
  Erlang processes. Tested on the host against AtomVM's Unix build with
  simulated drivers in place of the K230's vendor RTOS drivers.

  The drivers are the runtime's (os/src/coproc_*.erl), started by
  `:elixos_coproc` before distribution; `Elixos.Coproc.simulate/2` plays the
  hardware (a touch, a packet from the air, a key press), and AtomVM's
  standard output stands in for UART3.
  """
  use ExUnit.Case, async: false

  alias Elixos.Coproc
  alias Elixos.Coproc.{Console, Display, LoRa, Power, Touch}
  alias Elixos.Test.AtomVM

  @moduletag milestone: 32
  @moduletag :tmp_dir

  @subsystems [:console, :display, :lora, :power, :touch]

  setup ctx do
    %{cookie: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower), dir: ctx.tmp_dir}
  end

  test "each coprocessor-owned subsystem is an Erlang process reachable from Elixos", ctx do
    vm = AtomVM.start(ctx.dir, cookie: ctx.cookie)
    AtomVM.await_up(vm)
    start_link!(vm, ctx.cookie)
    assert_connected()

    {:ok, drivers} = Coproc.drivers()
    assert drivers |> Map.keys() |> Enum.sort() == @subsystems

    for {subsystem, pid} <- drivers do
      assert is_pid(pid) and node(pid) == vm.node
      assert %{pid: ^pid, backend: backend} = Coproc.driver_call(:coproc_driver, :info, [:"coproc_#{subsystem}"])
      assert backend == :"coproc_#{subsystem}_sim"
    end

    # The display unit records what it was asked to show.
    assert Display.status("restarting, attempt 2") == :ok
    assert Display.update({0, 0, 568, 1232}) == :ok
    assert Display.update({0, 0, 569, 1}) == {:error, :out_of_bounds}

    assert %{width: 568, height: 1232, status: "restarting, attempt 2", frames: 1,
             last_region: {0, 0, 568, 1232}, hdmi: :disconnected} = Display.info()

    assert eventually(fn -> AtomVM.output(vm) =~ "display: status restarting, attempt 2" end)
    assert Display.subscribe() == :ok
    assert Coproc.simulate(:display, {:hdmi, :connected}) == :ok
    assert_receive {:display, {:hdmi, :connected}}, 5_000

    # A touch on the panel arrives as a message.
    assert Touch.subscribe() == :ok
    assert Coproc.simulate(:touch, {:down, 100, 200}) == :ok
    assert Coproc.simulate(:touch, {:up, 100, 200}) == :ok
    assert_receive {:touch, :down, 100, 200}, 5_000
    assert_receive {:touch, :up, 100, 200}, 5_000
    assert Coproc.simulate(:touch, {:down, 568, 0}) == {:error, :badarg}

    # LoRa: a sent packet loops back as a received one; so does one from the air.
    assert LoRa.subscribe() == :ok
    assert LoRa.send("ping") == :ok
    assert_receive {:lora, "ping", %{loopback: true, rssi: _, snr: _}}, 5_000
    assert Coproc.simulate(:lora, {:receive, "from the air", %{rssi: -101}}) == :ok
    assert_receive {:lora, "from the air", %{rssi: -101, snr: _}}, 5_000
    assert LoRa.send(:binary.copy("x", 256)) == {:error, :badarg}
    # Both were acknowledged, so nothing waits in the driver.
    assert eventually(fn -> match?(%{sent: 1, received: 2, pending: 0}, LoRa.info()) end)

    # The power key, and a power-off the simulated PMU records.
    assert Power.subscribe() == :ok
    assert Coproc.simulate(:power, {:key, :pressed}) == :ok
    assert_receive {:power_key, :pressed}, 5_000
    assert %{poweroff: false} = Power.info()
    assert Power.poweroff() == :ok
    assert %{poweroff: true} = Power.info()
    assert eventually(fn -> AtomVM.output(vm) =~ "power: poweroff requested" end)

    # UART3: written lines go out on it, typed lines come back as messages.
    assert Console.subscribe() == :ok
    assert Console.write("hello from Elixos") == :ok
    assert eventually(fn -> AtomVM.output(vm) =~ "uart3: hello from Elixos\n" end)
    assert Coproc.simulate(:console, {:input, "help"}) == :ok
    assert_receive {:console, "help"}, 5_000
    assert %{lines: 1} = Console.info()

    refute_received _
  end

  # The Elixos BEAM is a peer node here, killed and started again; this node
  # stays linked to the coprocessor as its hardware, so things can happen
  # while Elixos is away.
  test "the coprocessor's drivers keep running while the Elixos BEAM restarts", ctx do
    vm = AtomVM.start(ctx.dir, cookie: ctx.cookie)
    AtomVM.await_up(vm)
    start_link!(vm, ctx.cookie, name: :"hardware@127.0.0.1")
    assert_connected()
    {:ok, drivers} = Coproc.drivers()

    elixos = start_elixos!(vm, ctx.cookie)
    collect!(elixos, [:lora, :touch, :power])
    assert eval!(elixos, ~s|Elixos.Coproc.Display.status("Elixos up")|) == :ok
    assert eval!(elixos, ~s|Elixos.Coproc.LoRa.send("before")|) == :ok
    assert eventually(fn -> match?([{:lora, "before", _}], collected(elixos)) end)
    assert eventually(fn -> match?(%{pending: 0}, LoRa.info()) end)

    # The Elixos BEAM dies. The coprocessor carries on: the same processes,
    # the display keeps its status, and what happens meanwhile is queued.
    kill!(elixos)
    assert Coproc.simulate(:touch, {:down, 10, 20}) == :ok
    assert Coproc.simulate(:lora, {:receive, "while away", %{rssi: -97}}) == :ok
    assert Coproc.simulate(:power, {:key, :pressed}) == :ok
    assert Coproc.drivers() == {:ok, drivers}
    assert %{status: "Elixos up"} = Display.info()
    assert %{pending: 1} = LoRa.info()
    assert %{pending: 1} = Touch.info()

    # A new Elixos BEAM, same node name: its subscribers get what was queued,
    # and nothing they had already been sent.
    elixos = start_elixos!(vm, ctx.cookie)
    assert eval!(elixos, "Elixos.Coproc.Display.info().status") == "Elixos up"
    collect!(elixos, [:lora, :touch, :power])

    assert eventually(fn -> length(collected(elixos)) == 3 end)
    assert Enum.sort(collected(elixos)) ==
             Enum.sort([{:touch, :down, 10, 20}, {:lora, "while away", %{rssi: -97, snr: 5}}, {:power_key, :pressed}])

    assert eventually(fn -> match?(%{pending: 0}, LoRa.info()) end)

    # The link drops and comes back under the same Elixos BEAM: Elixos.Coproc
    # renews the subscriptions on nodeup, and the event in between arrives.
    assert eval!(elixos, "Node.disconnect(#{inspect(vm.node)})") == true
    assert Coproc.simulate(:lora, {:receive, "across a reconnect", %{}}) == :ok
    assert eventually(fn -> {:lora, "across a reconnect", %{rssi: -90, snr: 5}} in collected(elixos) end)
    assert length(collected(elixos)) == 4

    assert Coproc.drivers() == {:ok, drivers}
    assert AtomVM.starts(vm) == 1
  end

  test "the coprocessor's drivers keep running while Elixos switches generations", ctx do
    {:ok, image} = Elixos.Image.open(Path.join(ctx.dir, "image"))
    a = bundle(1)
    {:ok, _} = Elixos.Image.record_coproc(image, a)
    {:ok, 1} = Elixos.Image.save(image)

    # Generation 1 boots and puts its bundle on a fresh coprocessor.
    vm = AtomVM.start(Path.join(ctx.dir, "atomvm"), cookie: ctx.cookie)
    AtomVM.await_up(vm)
    boot_generation!(vm, ctx.cookie, image, 1)
    assert AtomVM.await_up(vm, 2) == Coproc.Bundle.digest(a)
    assert_connected()
    assert eventually(fn -> Coproc.status().digest == Coproc.Bundle.digest(a) end)

    {:ok, drivers} = Coproc.drivers()
    assert Display.status("generation 1") == :ok

    # Saving generation 2 - new code here, the same coprocessor bundle - runs
    # Elixos.save/1's coprocessor step, which leaves the drivers alone.
    [{module, beam}] = Code.compile_string("defmodule Elixos.CoprocDriversTest.Gen2, do: def(hi, do: 2)")
    {:ok, _} = Elixos.Image.record(image, module, beam)
    {:ok, 2} = Elixos.Image.save(image)
    assert Coproc.generation_saved(image, 2) == :ok
    assert Coproc.drivers() == {:ok, drivers}

    # Booting generation 2, then falling back to generation 1: the Elixos
    # BEAM restarts on each, and the coprocessor runs on untouched.
    for generation <- [2, 1] do
      stop_supervised!(Coproc)
      boot_generation!(vm, ctx.cookie, image, generation)
      assert_connected()
      assert eventually(fn -> Coproc.status().digest == Coproc.Bundle.digest(a) end)
      assert Coproc.drivers() == {:ok, drivers}
      assert %{status: "generation 1"} = Display.info()
    end

    assert AtomVM.starts(vm) == 2
    assert Coproc.call(Elixos.CoprocDriversTest.Version, :value, []) == {:ok, 1}

    # The limit (ADR-099): a generation with another bundle restarts the
    # coprocessor's VM, and its drivers with it. Their state is handed over:
    # the display's status, and a packet nobody had taken yet.
    assert Coproc.simulate(:lora, {:receive, "queued across the deploy", %{}}) == :ok
    assert %{pending: 1} = LoRa.info()
    b = bundle(2)
    {:ok, _} = Elixos.Image.record_coproc(image, b)
    {:ok, 3} = Elixos.Image.save(image)
    assert Coproc.generation_saved(image, 3) == :ok
    assert AtomVM.await_up(vm, 3) == Coproc.Bundle.digest(b)
    assert Coproc.call(Elixos.CoprocDriversTest.Version, :value, []) == {:ok, 2}

    {:ok, restarted} = Coproc.drivers()
    assert Enum.all?(restarted, fn {subsystem, pid} -> pid != drivers[subsystem] and node(pid) == vm.node end)
    assert %{status: "generation 1"} = Display.info()
    assert LoRa.subscribe() == :ok
    assert_receive {:lora, "queued across the deploy", _meta}, 5_000
  end

  defp boot_generation!(vm, cookie, image, generation) do
    {:ok, bundle} = Elixos.Image.coproc_bundle(image, generation)
    start_link!(vm, cookie, bundle: bundle)
  end

  defp bundle(value) do
    [{module, beam}] =
      Code.compile_string("""
      defmodule Elixos.CoprocDriversTest.Version do
        def value, do: #{value}
      end
      """)

    :code.purge(module)
    :code.delete(module)
    {:ok, bundle} = Coproc.Bundle.pack([{module, beam}])
    bundle
  end

  # An Elixos BEAM: a peer node, not distributed until its Elixos.Coproc
  # starts distribution, controlled over its standard I/O.
  defp start_elixos!(vm, cookie) do
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
    {:ok, peer, _nonode} = :peer.start(%{connection: :standard_io, args: paths})
    on_exit(fn -> stop_peer(peer) end)
    {:ok, _} = :peer.call(peer, :application, :ensure_all_started, [:logger])

    opts = [node: vm.node, port: vm.port, listen: {{127, 0, 0, 1}, AtomVM.free_port()}, cookie: cookie,
            reconnect_ms: 200]

    eval!(peer, """
    spawn(fn ->
      {:ok, _} = Elixos.Coproc.start_link(#{inspect(opts)})
      Process.sleep(:infinity)
    end)
    """)

    assert eventually(fn -> eval!(peer, "Process.whereis(Elixos.Coproc) && Elixos.Coproc.status().connected") end)
    peer
  end

  # A process on the Elixos BEAM that subscribes to `subsystems` and keeps
  # every event in its mailbox.
  defp collect!(peer, subsystems) do
    eval!(peer, """
    pid = spawn(fn -> Process.sleep(:infinity) end)
    Process.register(pid, :collector)
    for subsystem <- #{inspect(subsystems)}, do: :ok = Elixos.Coproc.subscribe(subsystem, pid)
    """)
  end

  defp collected(peer) do
    {:messages, messages} = eval!(peer, "Process.info(Process.whereis(:collector), :messages)")
    messages
  end

  defp eval!(peer, code) do
    {result, _binding} = :peer.call(peer, Code, :eval_string, [code], 10_000)
    result
  end

  defp kill!(peer) do
    os_pid = :peer.call(peer, :os, :getpid, [])
    {_, 0} = System.cmd("kill", ["-KILL", List.to_string(os_pid)])
  end

  defp stop_peer(peer) do
    if Process.alive?(peer), do: :peer.stop(peer)
  catch
    :exit, _ -> :ok
  end

  defp start_link!(vm, cookie, opts \\ []) do
    start_supervised!(
      {Coproc,
       [node: vm.node, port: vm.port, listen: {{127, 0, 0, 1}, AtomVM.free_port()},
        cookie: cookie, reconnect_ms: 200] ++ opts}
    )
  end

  defp assert_connected do
    assert eventually(fn -> Coproc.status().connected end), "never connected: #{inspect(Coproc.status())}"
  end

  defp eventually(fun, deadline \\ System.monotonic_time(:millisecond) + 15_000) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) > deadline -> false
      true -> Process.sleep(50) && eventually(fun, deadline)
    end
  end
end
