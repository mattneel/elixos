defmodule Elixos.Integration.M04BootToIExTest do
  @moduledoc "M4: boots straight to IEx, with nothing but the kernel and the BEAM."
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 4
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "boots to an IEx prompt that evaluates Elixir", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    {out, vm} = QEMU.iex(vm, "1 + 1")
    assert out =~ ~r/^2$/m
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "Elixos.info/0 describes the factory boot", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    {out, vm} = QEMU.iex(vm, "Elixos.info()")
    assert out =~ "generation: 0"
    assert out =~ "mode: :normal"
    assert out =~ "attempt: 1"
    QEMU.stop(vm)
  end

  test "PID 1 is the shim, the BEAM is its child, and shells are only tools", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))

    {out, vm} = QEMU.iex(vm, ~s|File.read!("/proc/1/comm")|)
    assert out =~ ~s|"init\\n"|

    {out, vm} = QEMU.iex(vm, ~s{File.read!("/proc/self/stat") |> String.split() |> Enum.at(3)})
    assert out =~ ~s|"1"|, "the BEAM's parent must be PID 1 (the shim)"

    # ADR-041 amends ADR-012: Alpine's BusyBox sh exists, for *tooling*, and a
    # tool runs it directly. No shell is in the boot path - PID 1 execs ERTS
    # itself (the parent check above) and the console is IEx (the first test).
    {out, vm} = QEMU.iex(vm, ~s|System.cmd("/bin/sh", ["-c", "echo tool-ok"])|)
    assert out =~ ~s|{"tool-ok\\n", 0}|

    QEMU.stop(vm)
  end

  test "Elixos.poweroff/0 is a clean power down", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: shutdown poweroff/)
    {_, vm} = QEMU.expect(vm, ~r/reboot: Power down/)
    assert {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end

  test "Elixos.reboot/0 restarts the machine", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    vm = QEMU.send_line(vm, "Elixos.reboot()")
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: shutdown reboot/)
    {_, vm} = QEMU.expect(vm, ~r/reboot: Restarting system/)
    assert {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end
end
