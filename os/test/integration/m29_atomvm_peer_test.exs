defmodule Elixos.Integration.M29AtomVMPeerTest do
  @moduledoc """
  M29: AtomVM's Unix build on the host and Elixos in QEMU form one BEAM
  cluster over a virtual link. Distribution is internal-only: the listener is
  bound to the coprocessor link, the cookie lives in /priv, and nothing else
  can reach it. Coprocessor `.avm` bundles are generation content.

  The link is a second, restricted user-mode NIC (`QEMU.boot/2` `:coproc`):
  the guest is 10.0.3.15 on eth1 (`elixos.coproc_link`), and 10.0.3.9:4370 is
  relayed to the host AtomVM (`Elixos.Test.AtomVM`), whose node is therefore
  `coproc@10.0.3.9`. eth0 is the ordinary user-mode network.
  """
  use ExUnit.Case, async: false

  alias Elixos.Test.{AtomVM, Disk, QEMU}

  @moduletag :qemu
  @moduletag milestone: 29
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  @peer ~s|:"coproc@10.0.3.9"|

  setup ctx do
    %{disk: Disk.fresh!(ctx.tmp_dir), host_port: AtomVM.free_port()}
  end

  test "AtomVM and Elixos connect over the virtual link and spawn, send, receive, monitor and link across nodes",
       ctx do
    {vm, atomvm} = boot_and_link(ctx)

    {out, vm} = QEMU.iex(vm, "Node.list()")
    assert out =~ "[#{@peer}]"

    {_, vm} =
      QEMU.iex(vm, """
      defmodule Echo do
        def loop do
          receive do
            {from, message} -> send(from, {:echo, node(), message}); loop()
            :stop -> :ok
          end
        end
      end
      """)

    # The code AtomVM runs is the generation's: saved, deployed, restarted.
    {out, vm} = QEMU.iex(vm, "Elixos.Coproc.put_bundle([Echo])")
    assert out =~ ~r/\{:ok, "[0-9a-f]{64}"\}/
    {out, vm} = QEMU.iex(vm, "Elixos.save()", 120_000)
    assert out =~ "{:ok, 1}"
    AtomVM.await_up(atomvm, 2)
    vm = await_connected(vm)

    {out, vm} =
      QEMU.iex(
        vm,
        "pid = Node.spawn(#{@peer}, Echo, :loop, []); send(pid, {self(), :ping}); " <>
          "receive do m -> {node(pid), m} after 10_000 -> :timeout end"
      )

    assert out =~ "{#{@peer}, {:echo, #{@peer}, :ping}}"

    {out, vm} =
      QEMU.iex(
        vm,
        "ref = Process.monitor(pid); send(pid, :stop); " <>
          "receive do {:DOWN, ^ref, :process, ^pid, r} -> {:down, r} after 10_000 -> :timeout end"
      )

    assert out =~ "{:down, :normal}"

    {out, vm} =
      QEMU.iex(
        vm,
        "Process.flag(:trap_exit, true); linked = Node.spawn(#{@peer}, Echo, :loop, []); " <>
          "Process.link(linked); send(linked, :stop); " <>
          "receive do {:EXIT, ^linked, r} -> {:exit, r} after 10_000 -> :timeout end"
      )

    assert out =~ "{:exit, :normal}"
    power_off(vm)
  end

  test "killing AtomVM raises nodedown and Elixos.Coproc reconnects", ctx do
    {vm, atomvm} = boot_and_link(ctx)

    {_, vm} = QEMU.iex(vm, ":net_kernel.monitor_nodes(true)")
    AtomVM.kill(atomvm)

    {out, vm} =
      QEMU.iex(vm, "receive do {:nodedown, n} -> {:nodedown, n} after 30_000 -> :timeout end", 60_000)

    assert out =~ "{:nodedown, #{@peer}}"

    # Nothing is asked of IEx: the stand-in restarts and Elixos.Coproc redials.
    AtomVM.await_up(atomvm, 2)

    {out, vm} =
      QEMU.iex(vm, "receive do {:nodeup, n} -> {:nodeup, n} after 60_000 -> :timeout end", 90_000)

    assert out =~ "{:nodeup, #{@peer}}"
    {out, vm} = QEMU.iex(vm, "Elixos.Coproc.call(:erlang, :node, [])")
    assert out =~ "{:ok, #{@peer}}"
    power_off(vm)
  end

  test "a new coprocessor bundle deploys and runs, and fallback restores the old one", ctx do
    {vm, atomvm} = boot_and_link(ctx)

    # Generation 1 carries bundle v1, and becomes last_good.
    {_, vm} = QEMU.iex(vm, "defmodule Value do\n  def get, do: 1\nend")
    {_, vm} = QEMU.iex(vm, "Elixos.Coproc.put_bundle([Value])")
    {out, vm} = QEMU.iex(vm, "Elixos.save()", 120_000)
    assert out =~ "{:ok, 1}"
    v1 = AtomVM.await_up(atomvm, 2)
    vm = await_connected(vm)
    {out, vm} = QEMU.iex(vm, "Elixos.Coproc.call(Value, :get, [])")
    assert out =~ "{:ok, 1}"
    power_off(vm)

    vm = boot(ctx, ["elixos.commit_after=2"])
    vm = QEMU.await_log(vm, ~r/elixos-shim: commit generation=1/, 120_000)
    vm = await_connected(vm)

    # Generation 2: bundle v2, deployed by the save; its boot will fail.
    {_, vm} = QEMU.iex(vm, "defmodule Value do\n  def get, do: 2\nend")
    {_, vm} = QEMU.iex(vm, ~s|defmodule Bad do\n  def boot, do: raise("boom")\nend|)
    {_, vm} = QEMU.iex(vm, "Elixos.Coproc.put_bundle([Value])")
    {out, vm} = QEMU.iex(vm, "Elixos.save(boot: [{Bad, :boot, []}])", 120_000)
    assert out =~ "{:ok, 2}"
    v2 = AtomVM.await_up(atomvm, 3)
    refute v2 == v1
    vm = await_connected(vm)
    {out, vm} = QEMU.iex(vm, "Elixos.Coproc.call(Value, :get, [])")
    assert out =~ "{:ok, 2}"
    power_off(vm)

    # Generation 2 cannot boot: the shim falls back to generation 1, which
    # puts bundle v1 back on the coprocessor.
    vm = boot(ctx, ["elixos.max_attempts=2"], wait: false)

    {_, vm} =
      QEMU.expect(vm, ~r/elixos-shim: fallback to last_good=1 after 2 attempts of generation=2/, 300_000)

    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)
    assert AtomVM.await_up(atomvm, 4, 120_000) == v1
    assert AtomVM.bundle_digest(atomvm) == v1

    {out, vm} =
      QEMU.iex(
        vm,
        "Enum.find_value(1..600, fn _ -> case Elixos.Coproc.call(Value, :get, [], 1_000) do " <>
          "{:ok, value} -> value; _ -> Process.sleep(100); nil end end)",
        90_000
      )

    assert out =~ ~r/^1$/m
    power_off(vm)
  end

  test "distribution is not reachable from any interface but the coprocessor link", ctx do
    external = AtomVM.free_port()
    {vm, _atomvm} = boot_and_link(ctx, hostfwd: [{external, 4370}])

    {out, vm} = QEMU.iex(vm, "{Node.self(), Node.list()}")
    assert out =~ ~s|{:"elixos@10.0.3.15", [#{@peer}]}|

    # Inside the guest: the listener is on the link's address and nowhere
    # else, and there is no epmd at all.
    {out, vm} =
      QEMU.iex(
        vm,
        "for {ip, port} <- [{{10, 0, 3, 15}, 4370}, {{10, 0, 2, 15}, 4370}, {{127, 0, 0, 1}, 4370}, " <>
          "{{10, 0, 3, 15}, 4369}, {{10, 0, 2, 15}, 4369}, {{127, 0, 0, 1}, 4369}], " <>
          "do: {ip, port, elem(:gen_tcp.connect(ip, port, [], 2_000), 0)}"
      )

    assert out =~ "{{10, 0, 3, 15}, 4370, :ok}"

    for refused <- ["{{10, 0, 2, 15}, 4370, :error}", "{{127, 0, 0, 1}, 4370, :error}",
                    "{{10, 0, 3, 15}, 4369, :error}", "{{10, 0, 2, 15}, 4369, :error}",
                    "{{127, 0, 0, 1}, 4369, :error}"] do
      assert out =~ refused
    end

    # From the user-mode network's external side: the forwarded connection
    # reaches the guest's eth0, where nothing listens, and is closed without
    # a byte of handshake.
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", external, [:binary, active: false], 10_000)
    _ = :gen_tcp.send(socket, <<0, 15, ?N, 0::64, 0::32, 6::16, "nobody">>)
    assert :gen_tcp.recv(socket, 0, 10_000) == {:error, :closed}
    :gen_tcp.close(socket)
    power_off(vm)
  end

  # Boots a fresh guest with the link, configures Elixos.Coproc, reads the
  # cookie it created in /priv and starts the host AtomVM with it.
  defp boot_and_link(ctx, opts \\ []) do
    vm = boot(ctx, [], opts)
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Coproc.configure(node: #{@peer}, port: 4370)|)
    assert out =~ ~r/\{:ok, "[0-9a-f]{48}"\}/

    {out, vm} = QEMU.iex(vm, ~s|File.read!("/priv/coproc/cookie")|)
    [cookie] = Regex.run(~r/"([0-9a-f]{48})\\n"/, out, capture: :all_but_first)

    atomvm =
      AtomVM.start(Path.join(ctx.tmp_dir, "atomvm"),
        node: :"coproc@10.0.3.9",
        port: ctx.host_port,
        cookie: cookie
      )

    AtomVM.await_up(atomvm)
    {await_connected(vm), atomvm}
  end

  defp boot(ctx, append, opts \\ []) do
    boot_opts = [
      disk: ctx.disk,
      coproc: {4370, ctx.host_port},
      hostfwd: Keyword.get(opts, :hostfwd, []),
      append: ["ip=:::::eth0:dhcp", "elixos.coproc_link=eth1,10.0.3.15/24" | append]
    ]

    if Keyword.get(opts, :wait, true) do
      vm = QEMU.boot_to_iex(ctx, boot_opts)
      QEMU.await_log(vm, ~r/elixos-shim: coproc link eth1 10\.0\.3\.15\/24/)
    else
      QEMU.boot(ctx, boot_opts)
    end
  end

  defp await_connected(vm) do
    {out, vm} =
      QEMU.iex(
        vm,
        "Enum.find_value(1..600, fn _ -> if Elixos.Coproc.status().connected, " <>
          "do: Node.list(), else: (Process.sleep(100); nil) end)",
        90_000
      )

    assert out =~ "[#{@peer}]"
    vm
  end

  defp power_off(vm) do
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end
end
