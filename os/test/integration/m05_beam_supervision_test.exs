defmodule Elixos.Integration.M05BeamSupervisionTest do
  @moduledoc """
  M5: the shim supervises the BEAM. Crashes and hangs look the same to it,
  attempts are counted, and a healthy boot commits itself.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 5
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  # Keep auto-commit out of the way unless a test is about it.
  @no_commit "elixos.commit_after=3600"

  test "a healthy BEAM is never killed: its heartbeats arrive", ctx do
    append = [@no_commit, "elixos.hb_timeout=5"]
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir), append: append)
    # More than twice the timeout without a kill means heartbeats are arriving.
    Process.sleep(12_000)
    {out, vm} = QEMU.iex(vm, "1 + 1")
    assert out =~ ~r/^2$/m
    refute QEMU.transcript(vm) =~ "heartbeat timeout"
    QEMU.stop(vm)
  end

  test "a crashed BEAM is relaunched and the attempt is counted", ctx do
    append = [@no_commit, "elixos.max_attempts=5"]
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir), append: append)

    vm = QEMU.send_line(vm, ":erlang.halt(3)")
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: beam exited status=3/)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)

    {out, vm} = QEMU.iex(vm, "Elixos.info()")
    assert out =~ "attempt: 2"
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "a hung BEAM (no heartbeats) is killed and relaunched", ctx do
    append = [@no_commit, "elixos.hb_timeout=3", "elixos.max_attempts=5"]
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir), append: append)

    vm = QEMU.send_line(vm, "Elixos.Shim.Control.pause_heartbeat()")
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: heartbeat timeout after 3s, killing beam/, 60_000)
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: beam killed by signal 9/)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "a crash loop of the factory ends in rescue mode, not a boot loop", ctx do
    append = [@no_commit, "elixos.max_attempts=2"]
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir), append: append)

    vm = QEMU.send_line(vm, ":erlang.halt(1)")
    {_, vm} = QEMU.expect(vm, ~r/plan generation=0 mode=normal attempt=2/, 180_000)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)

    vm = QEMU.send_line(vm, ":erlang.halt(1)")
    {_, vm} = QEMU.expect(vm, ~r/plan generation=0 mode=rescue/, 180_000)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)

    {out, vm} = QEMU.iex(vm, "Elixos.info()")
    assert out =~ "mode: :rescue"
    QEMU.stop(vm)
  end

  test "a healthy boot commits itself, which resets the attempt count", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk, append: ["elixos.commit_after=2"])
    vm = QEMU.await_log(vm, ~r/elixos-shim: commit generation=0/, 60_000)

    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)

    assert Disk.read(disk, "/boot.state") == {:ok, "current=0\nlast_good=0\nattempts=0\n"}
  end
end
