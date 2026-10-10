defmodule Elixos.Integration.M03FirstBootTest do
  @moduledoc """
  M3: the unmodified mainline kernel hands off to the Zig shim as PID 1.

  These boots use `elixos.test.stop_before_launch`: the shim does everything up
  to launching ERTS (mounts, cmdline, boot.state, plan, persist), logs the plan
  and powers off. That keeps these tests meaningful in every later milestone.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 3
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  @stop "elixos.test.stop_before_launch"

  test "the shim runs as PID 1, plans the factory and powers off cleanly", ctx do
    vm = QEMU.boot(ctx, disk: Disk.fresh!(ctx.tmp_dir), append: [@stop])
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: pid 1, version \S+/, 180_000)
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: plan generation=0 mode=normal attempt=1/)
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: test hook stop_before_launch/)
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: shutdown poweroff/)
    {_, vm} = QEMU.expect(vm, ~r/reboot: Power down/)
    assert {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end

  test "a blank data disk gets a canonical boot.state", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    assert Disk.read(disk, "/boot.state") == {:error, :enoent}

    vm = QEMU.boot(ctx, disk: disk, append: [@stop])
    {_, vm} = QEMU.expect_exit(vm, 180_000)
    QEMU.refute_kernel_panic(vm)

    assert Disk.read(disk, "/boot.state") == {:ok, "current=0\nlast_good=0\nattempts=1\n"}
  end

  test "every boot counts an attempt until something commits", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)

    for attempt <- 1..2 do
      vm = QEMU.boot(ctx, disk: disk, append: [@stop])
      {_, vm} = QEMU.expect(vm, ~r/plan generation=0 mode=normal attempt=#{attempt}/, 180_000)
      {0, _} = QEMU.expect_exit(vm)
    end

    assert Disk.read(disk, "/boot.state") == {:ok, "current=0\nlast_good=0\nattempts=2\n"}
  end

  test "invalid elixos.* parameters are reported, never fatal", ctx do
    append = [@stop, "elixos.bogus=1", "elixos.max_attempts=0"]
    vm = QEMU.boot(ctx, disk: Disk.fresh!(ctx.tmp_dir), append: append)
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: ignored 2 invalid elixos\.\* parameters/, 180_000)
    assert {0, _} = QEMU.expect_exit(vm)
  end

  test "a corrupt boot.state boots rescue and is kept as evidence", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    Disk.write!(disk, "/boot.state", "garbage\n")

    vm = QEMU.boot(ctx, disk: disk, append: [@stop])

    {_, vm} =
      QEMU.expect(vm, ~r/elixos-shim: state file unreadable \(\w+\), entering rescue/, 180_000)

    {_, vm} = QEMU.expect(vm, ~r/plan generation=0 mode=rescue/)
    {0, _} = QEMU.expect_exit(vm)

    assert Disk.read(disk, "/boot.state") == {:ok, "garbage\n"}
  end

  test "a missing data device boots rescue instead of panicking", ctx do
    append = [@stop, "elixos.data=/dev/vdz"]
    vm = QEMU.boot(ctx, disk: Disk.fresh!(ctx.tmp_dir), append: append)

    {_, vm} =
      QEMU.expect(vm, ~r/elixos-shim: cannot mount \/dev\/vdz \(\w+\), entering rescue/, 180_000)

    {_, vm} = QEMU.expect(vm, ~r/plan generation=0 mode=rescue/)
    assert {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end
end
