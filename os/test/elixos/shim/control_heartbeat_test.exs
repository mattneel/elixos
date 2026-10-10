defmodule Elixos.Shim.ControlHeartbeatTest do
  @moduledoc """
  The heartbeat loop's failure modes (added while implementing M2).

  The shipped suite checks the ordinary pause/resume sequence. These tests pin
  down what a superseded schedule may do: nothing. An expired timer message
  that is still in flight when `pause_heartbeat/1` and `resume_heartbeat/1`
  run must not re-arm (or that would leave two loops sending `HB`).
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 2

  alias Elixos.Shim.Control

  defp start_control(opts \\ []) do
    opts =
      Keyword.merge([sink: {Elixos.Test.ProcessSink, self()}, heartbeat_ms: 20, name: nil], opts)

    start_supervised!({Control, opts})
  end

  test "a stale timer message never revives the heartbeat" do
    control = start_control()
    assert_receive {:shim_write, "HB\n"}, 100

    assert :ok = Control.pause_heartbeat(control)
    flush_heartbeats()

    # What an expired timer looks like when pause did not manage to cancel it.
    stale = make_ref()
    send(control, {:heartbeat, stale})
    refute_receive {:shim_write, "HB\n"}, 100

    assert :ok = Control.resume_heartbeat(control)
    assert_receive {:shim_write, "HB\n"}, 100

    # Still one loop: pausing again plus another stale message stays silent.
    assert :ok = Control.pause_heartbeat(control)
    flush_heartbeats()
    send(control, {:heartbeat, stale})
    send(control, {:heartbeat, make_ref()})
    refute_receive {:shim_write, "HB\n"}, 100

    assert :ok = Control.resume_heartbeat(control)
    assert_receive {:shim_write, "HB\n"}, 100
  end

  test "pause, resume and a superseded schedule leave exactly one loop" do
    control = start_control()
    assert_receive {:shim_write, "HB\n"}, 100

    # A stall long enough for the timer to expire between the two calls is what
    # makes the ordering reachable in production; the mailbox cannot be
    # reordered from a test, so this covers the invariant instead.
    assert :ok = Control.pause_heartbeat(control)
    flush_heartbeats()
    assert :ok = Control.resume_heartbeat(control)

    # One loop at 20ms sends about 10 heartbeats in 200ms; two would send 20.
    count = count_heartbeats(200)
    assert count in 5..15, "expected one heartbeat loop, got #{count} beats in 200ms"
  end

  test "a request is still written while the heartbeat is paused" do
    control = start_control()
    assert_receive {:shim_write, "HB\n"}, 100

    assert :ok = Control.pause_heartbeat(control)
    flush_heartbeats()

    assert :ok = Control.commit(control, 4)
    assert_receive {:shim_write, "COMMIT 4\n"}, 100
  end

  defp count_heartbeats(timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_count(0, deadline)
  end

  defp do_count(count, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:shim_write, "HB\n"} -> do_count(count + 1, deadline)
    after
      remaining -> count
    end
  end

  defp flush_heartbeats do
    receive do
      {:shim_write, "HB\n"} -> flush_heartbeats()
    after
      30 -> :ok
    end
  end
end
