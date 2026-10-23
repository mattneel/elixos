defmodule Elixos.CoprocTest do
  @moduledoc """
  M29: Elixos.Coproc supervises the link to the coprocessor node - connect,
  monitor, reconnect, and run calls - against AtomVM's Unix build on the host.

  The host test VM itself becomes the Elixos node: Elixos.Coproc starts
  distribution on 127.0.0.1 and stops it when the test ends. AtomVM is the
  stand-in from `Elixos.Test.AtomVM` (`make atomvm`).
  """
  use ExUnit.Case, async: false

  alias Elixos.Test.AtomVM

  @moduletag milestone: 29
  @moduletag :tmp_dir

  setup ctx do
    [{module, beam}] =
      Code.compile_string("""
      defmodule Elixos.CoprocTest.Probe do
        def answer, do: {:answer, 6 * 7}
      end
      """)

    {:ok, bundle} = Elixos.Coproc.Bundle.pack([{module, beam}])
    :code.purge(module)
    :code.delete(module)
    %{bundle: bundle, cookie: random_cookie(), dir: ctx.tmp_dir}
  end

  test "Elixos.Coproc connects to a host AtomVM node with the cookie and runs a call on it", ctx do
    vm = AtomVM.start(ctx.dir, cookie: ctx.cookie, bundle: ctx.bundle)
    AtomVM.await_up(vm)
    start_link!(vm, ctx.cookie)

    assert_connected(vm.node)
    assert vm.node in Node.list()

    # Code from the bundle, run on the coprocessor: the module is not loaded here.
    refute Code.loaded?(Elixos.CoprocTest.Probe)
    assert Elixos.Coproc.call(Elixos.CoprocTest.Probe, :answer, []) == {:ok, {:answer, 42}}
    assert Elixos.Coproc.call(:erlang, :node, []) == {:ok, vm.node}
  end

  test "Elixos.Coproc reconnects after the AtomVM node restarts", ctx do
    vm = AtomVM.start(ctx.dir, cookie: ctx.cookie, bundle: ctx.bundle)
    AtomVM.await_up(vm)
    start_link!(vm, ctx.cookie)
    assert_connected(vm.node)

    :ok = :net_kernel.monitor_nodes(true)
    AtomVM.kill(vm)
    assert_receive {:nodedown, node}, 10_000
    assert node == vm.node

    # Nobody asks: the launcher restarts AtomVM and Elixos.Coproc dials again.
    AtomVM.await_up(vm, 2)
    assert_receive {:nodeup, ^node}, 15_000
    assert_connected(vm.node)
    assert Elixos.Coproc.call(Elixos.CoprocTest.Probe, :answer, []) == {:ok, {:answer, 42}}
  end

  test "Elixos.Coproc refuses a wrong cookie", ctx do
    vm = AtomVM.start(ctx.dir, cookie: random_cookie(), bundle: ctx.bundle)
    AtomVM.await_up(vm)
    start_link!(vm, ctx.cookie)

    # Several attempts (one every 200 ms): each handshake is rejected.
    Process.sleep(1_500)
    refute Elixos.Coproc.status().connected
    refute vm.node in Node.list()
    assert {:error, _} = Elixos.Coproc.call(Elixos.CoprocTest.Probe, :answer, [], 1_000)
    assert AtomVM.output(vm) =~ "invalid_challenge"
  end

  defp start_link!(vm, cookie) do
    start_supervised!(
      {Elixos.Coproc,
       node: vm.node,
       port: vm.port,
       listen: {{127, 0, 0, 1}, AtomVM.free_port()},
       cookie: cookie,
       reconnect_ms: 200}
    )
  end

  defp assert_connected(node, deadline \\ System.monotonic_time(:millisecond) + 15_000) do
    cond do
      Elixos.Coproc.status().connected ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("#{node} never connected: #{inspect(Elixos.Coproc.status())}")

      true ->
        Process.sleep(50)
        assert_connected(node, deadline)
    end
  end

  defp random_cookie, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
