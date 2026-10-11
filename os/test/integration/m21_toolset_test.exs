defmodule Elixos.Integration.M21ToolsetTest do
  @moduledoc """
  M21: tool calls see their session workspace, run in a peer rather than the
  main VM, and recover after a peer killed mid-call without restarting the
  BEAM, losing the prompt or missing the shim heartbeat (ADR-047).

  Reference note: none of these session-isolation or peer-recovery acceptance
  tests has been checked against a reference implementation yet.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 21
  @moduletag :deferred
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "tools are workspace-scoped and a lost peer costs one call, not the VM", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk, append: ["elixos.hb_timeout=5"])
    {_, vm} = QEMU.iex(vm, "alias Elixos.Toolset, as: T")
    {_, vm} = QEMU.iex(vm, "alias Elixos.Toolset.Peer, as: P")
    {_, vm} = QEMU.iex(vm, ~s|w = "/priv/work/m21-toolset"|)
    {out, vm} = QEMU.iex(vm, "File.mkdir_p(w)")
    assert out =~ ~r/^:ok$/m
    {out, vm} = QEMU.iex(vm, ~s|File.write(Path.join(w, "hello.txt"), "m21-peer-read")|)
    assert out =~ ~r/^:ok$/m

    {out, vm} = QEMU.iex(vm, "Elixos.Session.cd(w)")
    assert out =~ ~s|{:ok, "/priv/work/m21-toolset"}|
    {_, vm} = QEMU.iex(vm, "s = T.Session.new(workspace: w)")
    {_, vm} = QEMU.iex(vm, "main = self(); vm_cwd = File.cwd!(); vm_env = System.get_env()")
    {out, vm} = QEMU.iex(vm, "s.workspace == w and s.session_dir == w")
    assert out =~ ~r/^true$/m

    # OMP 18.8.7 src/tools/read.ts:778-780 defines readSchema's path input.
    {_, vm} = QEMU.iex(vm, ~s|params = %{"path" => "hello.txt"}|)
    {out, vm} = QEMU.iex(vm, ~s|result = T.call("read", params, session: s)|)
    assert out =~ ~r/^\{:ok,/m
    {out, vm} = QEMU.iex(vm, ~s|String.contains?(inspect(elem(result, 1)), "m21-peer-read")|)
    assert out =~ ~r/^true$/m
    {_, vm} = QEMU.iex(vm, ~s|old_peer = T.last_run("read").node|)
    {out, vm} = QEMU.iex(vm, "old_peer != node() and old_peer == P.node()")
    assert out =~ ~r/^true$/m

    # This file exists and the prompt can read it, but it is outside both
    # the tool workspace and the M9 session directory.
    {_, vm} = QEMU.iex(vm, ~s|outside = "/priv/work/m21-outside.txt"|)
    {out, vm} = QEMU.iex(vm, ~s|File.write(outside, "not-for-this-session")|)
    assert out =~ ~r/^:ok$/m
    {out, vm} = QEMU.iex(vm, "File.read(outside)")
    assert out =~ ~s|{:ok, "not-for-this-session"}|
    {_, vm} = QEMU.iex(vm, ~s|denied = %{"path" => outside}|)
    {out, vm} = QEMU.iex(vm, ~s|T.call("read", denied, session: s)|)
    assert out =~ "{:error,"
    refute out =~ "not-for-this-session"

    # The shell appends a marker before blocking, so peer loss is tested only
    # after a real call is in progress. SDK timeout is seconds; ours is ms.
    {_, vm} = QEMU.iex(vm, ~s|cmd = %{"command" => "echo started >> started; sleep 180"}|)
    {_, vm} = QEMU.iex(vm, ~s|cmd = Map.merge(cmd, %{"timeout" => 240, "pty" => false})|)
    {_, vm} = QEMU.iex(vm, "opts = [session: s, timeout: 240_000]")
    {_, vm} = QEMU.iex(vm, ~s|pending = Task.async(fn -> T.call("bash", cmd, opts) end)|)
    vm = await_started!(vm, System.monotonic_time(:millisecond) + 30_000)

    {out, vm} = QEMU.iex(vm, "1 + 1")
    assert out =~ ~r/^2$/m

    # Observe more than two configured heartbeat deadlines while bash is
    # still blocked. This delay observes liveness; it does not guess start-up.
    Process.sleep(12_000)
    {out, vm} = QEMU.iex(vm, "Task.yield(pending, 0) == nil")
    assert out =~ ~r/^true$/m, "bash must still be in flight before killing its peer"
    {out, vm} = QEMU.iex(vm, "P.kill()")
    assert out =~ ~r/^:ok$/m
    {out, vm} = QEMU.iex(vm, "Task.await(pending, 20_000)", 30_000)
    assert out =~ ~r/^\{:error, :tool_host_down\}$/m

    {out, vm} = QEMU.iex(vm, "self() == main and File.cwd!() == vm_cwd")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, "System.get_env() == vm_env")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, ~s|File.read(Path.join(w, "started")) == {:ok, "started\\n"}|)
    assert out =~ ~r/^true$/m, "the interrupted call must not replay its append effect"
    {out, vm} = QEMU.iex(vm, ~s|again = T.call("read", params, session: s)|)
    assert out =~ ~r/^\{:ok,/m
    {out, vm} = QEMU.iex(vm, ~s|String.contains?(inspect(elem(again, 1)), "m21-peer-read")|)
    assert out =~ ~r/^true$/m
    {_, vm} = QEMU.iex(vm, ~s|new_peer = T.last_run("read").node|)
    {out, vm} = QEMU.iex(vm, "new_peer != node() and new_peer != old_peer")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, "new_peer == P.node()")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, ~s|File.read(Path.join(w, "started")) == {:ok, "started\\n"}|)
    assert out =~ ~r/^true$/m, "host recovery must not retry the interrupted bash call"

    # Drain the serial stream through shutdown before counting the complete
    # shim log, so a delayed heartbeat complaint cannot escape the assertion.
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    transcript = QEMU.transcript(vm)

    assert Regex.scan(
             ~r/^elixos-shim: launching generation=\d+ mode=(?:normal|rescue)$/m,
             transcript
           )
           |> length() == 1

    refute transcript =~ ~r/^elixos-shim: heartbeat timeout after \d+s, killing beam$/m
    QEMU.refute_kernel_panic(vm)
  end

  # Thread every returned VM through polling: QEMU.iex/3 consumes and advances
  # the prompt counter. A deadline and per-expression timeout bound failures.
  defp await_started!(vm, deadline) do
    assert System.monotonic_time(:millisecond) < deadline,
           "bash did not create its workspace start marker within 30 seconds"

    {out, vm} =
      QEMU.iex(vm, ~s|File.read(Path.join(w, "started")) == {:ok, "started\\n"}|, 10_000)

    if out =~ ~r/^true$/m do
      vm
    else
      Process.sleep(100)
      await_started!(vm, deadline)
    end
  end
end
