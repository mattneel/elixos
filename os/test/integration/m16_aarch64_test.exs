defmodule Elixos.Integration.M16Aarch64Test do
  @moduledoc """
  M16: the image is built for aarch64 as well as x86_64. Under TCG emulation
  this is slow, so this is the smoke set only - boot to a prompt on
  qemu-system-aarch64's `virt` machine, see the architecture, save a module,
  reboot, find it again, power off. `make test-qemu-aarch64` runs it; a plain
  x86_64 run never picks it up (:aarch64 is excluded unless that target asks).
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag :aarch64
  @moduletag milestone: 16
  @moduletag timeout: 1_800_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "the aarch64 image boots, reports its architecture, and keeps a module", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk, arch: :aarch64)

    # The machine knows what it is.
    {out, vm} = QEMU.iex(vm, "Elixos.info()")
    assert out =~ "aarch64", "Elixos.info must report the architecture: #{out}"

    # A module defined at the prompt is the live image's promise, on any
    # architecture.
    {out, vm} = QEMU.iex(vm, ~s|defmodule ArmProbe do\n  def value, do: :arm_ok\nend|, 120_000)
    assert out =~ "{:module, ArmProbe"

    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ ~r/\{:ok, \d+\}/

    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk, arch: :aarch64)

    {out, vm} = QEMU.iex(vm, "ArmProbe.value()")
    assert out =~ ~r/^:arm_ok$/m

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
