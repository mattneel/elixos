defmodule Elixos.CoprocDisplayLeaseTest do
  @moduledoc """
  M33: while the big core's BEAM is away, the coprocessor keeps the panel
  alive with its own status. Elixos renews a lease on the display driver
  (`Elixos.Coproc.Display.lease/2`, kept by `Elixos.Deck.Lease`); when the
  lease lapses, the driver shows `Elixos restarting, was <text>` over the last
  frame, and the next renewal clears it. Tested on the host against AtomVM's
  Unix build with the simulated display backend, which records the status
  it is asked to show (os/src/coproc_display_sim.erl).
  """
  use ExUnit.Case, async: false

  alias Elixos.Coproc
  alias Elixos.Coproc.Display
  alias Elixos.Test.AtomVM

  @moduletag milestone: 33
  @moduletag :tmp_dir

  setup ctx do
    cookie = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    vm = AtomVM.start(ctx.tmp_dir, cookie: cookie)
    AtomVM.await_up(vm)

    start_supervised!(
      {Coproc,
       [
         node: vm.node,
         port: vm.port,
         listen: {{127, 0, 0, 1}, AtomVM.free_port()},
         cookie: cookie,
         reconnect_ms: 200
       ]}
    )

    assert eventually(fn -> Coproc.status().connected end),
           "never connected: #{inspect(Coproc.status())}"

    %{vm: vm}
  end

  test "a lapsed lease shows the coprocessor's status; renewal clears it", %{vm: vm} do
    assert %{status: ""} = Display.info()
    assert Display.lease(300, "gen 3 attempt 1") == :ok
    assert %{status: "", lease: %{lapsed: false, text: "gen 3 attempt 1"}} = Display.info()

    # Renewed in time: nothing changes.
    Process.sleep(150)
    assert Display.lease(300, "gen 3 attempt 1") == :ok
    Process.sleep(200)
    assert %{status: "", lease: %{lapsed: false}} = Display.info()

    # Not renewed: the driver shows its own status, the last known attempt
    # included, and says so on its console.
    assert eventually(fn -> match?(%{lease: %{lapsed: true}}, Display.info()) end)
    assert %{status: "Elixos restarting, was gen 3 attempt 1"} = Display.info()

    assert eventually(fn ->
             AtomVM.output(vm) =~ "display: status Elixos restarting, was gen 3 attempt 1\n"
           end)

    # Elixos is back: the first renewal clears the status.
    assert Display.lease(300, "gen 3 attempt 2") == :ok
    assert %{status: "", lease: %{lapsed: false, text: "gen 3 attempt 2"}} = Display.info()

    # A malformed lease is refused and changes nothing.
    assert Coproc.driver_call(:coproc_display, :lease, [0, "x"]) == {:error, :badarg}
    assert Coproc.driver_call(:coproc_display, :lease, [100, ~c"x"]) == {:error, :badarg}
  end

  test "Elixos.Deck.Lease keeps the lease while its owner lives" do
    # The owner stands for the deck: the renewer lives as long as it does.
    parent = self()

    owner =
      spawn(fn ->
        send(
          parent,
          {:renewer,
           Elixos.Deck.Lease.start_link(text: "gen 7 attempt 1", renew_ms: 100, ttl_ms: 400)}
        )

        receive do: (:stop -> :ok)
      end)

    assert_receive {:renewer, renewer}, 5_000

    assert eventually(fn ->
             match?(%{status: "", lease: %{text: "gen 7 attempt 1"}}, Display.info())
           end)

    Process.sleep(1_200)
    assert %{status: "", lease: %{lapsed: false}} = Display.info()

    # The owner goes away normally: the renewer stops by itself and the lease
    # lapses within its TTL.
    ref = Process.monitor(renewer)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^renewer, _}, 2_000

    assert eventually(fn ->
             match?(%{status: "Elixos restarting, was gen 7 attempt 1"}, Display.info())
           end)

    # A new owner's renewer clears it.
    Elixos.Deck.Lease.start_link(text: "gen 7 attempt 2", renew_ms: 100, ttl_ms: 400)

    assert eventually(fn ->
             match?(%{status: "", lease: %{text: "gen 7 attempt 2"}}, Display.info())
           end)
  end

  defp eventually(fun, deadline \\ System.monotonic_time(:millisecond) + 15_000) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) > deadline -> false
      true -> Process.sleep(50) && eventually(fun, deadline)
    end
  end
end
