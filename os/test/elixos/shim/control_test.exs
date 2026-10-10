defmodule Elixos.Shim.ControlTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 2

  alias Elixos.Shim.Control

  defp start_control(opts \\ []) do
    opts =
      Keyword.merge([sink: {Elixos.Test.ProcessSink, self()}, heartbeat_ms: 20, name: nil], opts)

    start_supervised!({Control, opts})
  end

  test "writes a heartbeat at once and then every interval" do
    start_control()
    assert_receive {:shim_write, "HB\n"}, 100
    assert_receive {:shim_write, "HB\n"}, 200
    assert_receive {:shim_write, "HB\n"}, 200
  end

  test "requests are written before the call returns" do
    control = start_control(heartbeat_ms: 60_000)
    assert_receive {:shim_write, "HB\n"}

    assert :ok = Control.commit(control, 7)
    assert_received {:shim_write, "COMMIT 7\n"}

    assert :ok = Control.next(control, 12)
    assert_received {:shim_write, "NEXT 12\n"}

    assert :ok = Control.reboot(control)
    assert_received {:shim_write, "REBOOT\n"}

    assert :ok = Control.poweroff(control)
    assert_received {:shim_write, "POWEROFF\n"}

    assert :ok = Control.halt(control)
    assert_received {:shim_write, "HALT\n"}
  end

  test "a paused heartbeat looks like a hang to the shim, until resumed" do
    control = start_control()
    assert_receive {:shim_write, "HB\n"}, 100

    assert :ok = Control.pause_heartbeat(control)
    flush_heartbeats()
    refute_receive {:shim_write, "HB\n"}, 150

    assert :ok = Control.resume_heartbeat(control)
    assert_receive {:shim_write, "HB\n"}, 100
  end

  test "invalid generations raise in the caller and leave the server alone" do
    control = start_control(heartbeat_ms: 60_000)

    for bad <- [-1, 4_294_967_296, 1.5, "7", nil] do
      assert_raise ArgumentError, fn -> Control.commit(control, bad) end
      assert_raise ArgumentError, fn -> Control.next(control, bad) end
    end

    assert Process.alive?(control)
  end

  test "a failing sink is reported, and the server keeps running" do
    control = start_control(sink: {Elixos.Test.BrokenSink, nil}, heartbeat_ms: 60_000)
    assert {:error, :epipe} = Control.commit(control, 1)
    assert Process.alive?(control)
  end

  test "registers under its module name by default" do
    pid =
      start_supervised!({Control, sink: {Elixos.Test.ProcessSink, self()}, heartbeat_ms: 60_000})

    assert Process.whereis(Control) == pid
    assert :ok = Control.commit(3)
    assert_receive {:shim_write, "COMMIT 3\n"}
  end

  defp flush_heartbeats do
    receive do
      {:shim_write, "HB\n"} -> flush_heartbeats()
    after
      30 -> :ok
    end
  end
end
