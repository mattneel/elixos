defmodule Elixos.Integration.M08ShimSelfRecoveryTest do
  @moduledoc """
  M8: the shim survives its own panics (ADR-004). Its panic handler re-execs
  /init; execve keeps PID 1, the BEAM stays its child, and the session goes on.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 8
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "a shim panic re-execs the shim and the IEx session carries on", ctx do
    append = ["elixos.test.shim_panic_after=20", "elixos.commit_after=3600"]
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir), append: append)
    {_, vm} = QEMU.iex(vm, "x = 41")

    vm = QEMU.await_log(vm, ~r/elixos-shim: re-exec after panic/, 120_000)

    # Same VM, same session: the binding survives and the prompt keeps counting
    # (QEMU.iex/3 waits for a prompt numbered above the last one).
    {out, vm} = QEMU.iex(vm, "x + 1", 60_000)
    assert out =~ ~r/^42$/m
    assert vm.iex_prompt > 2

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "after a re-exec the shim still supervises the BEAM", ctx do
    append = [
      "elixos.test.shim_panic_after=20",
      "elixos.hb_timeout=3",
      "elixos.commit_after=3600"
    ]

    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir), append: append)
    vm = QEMU.await_log(vm, ~r/elixos-shim: re-exec after panic/, 120_000)

    vm = QEMU.send_line(vm, "Elixos.Shim.Control.pause_heartbeat()")
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: heartbeat timeout after 3s, killing beam/, 60_000)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
