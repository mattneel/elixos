defmodule Elixos.Integration.M08CrashDumpTest do
  @moduledoc """
  M8: a crash leaves its dump where the next boot can read it (ADR-025).

  ERTS writes erl_crash.dump wherever `ERL_CRASH_DUMP` points; the shim points
  it at `/priv/crash/gen<generation>-attempt<attempt>.dump`, so the factory -
  the boot the shim falls back to - can still say why the generation it
  abandoned died, instead of the dump dying with the initramfs.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 8
  @moduletag timeout: 1_200_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "a crashed generation's dump is readable from the fallback boot", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)

    # Generation 1 has a boot spec that raises: booting it kills the VM.
    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {_, vm} = QEMU.iex(vm, ~s|defmodule Bad do\n  def boot, do: raise("boom")\nend|)
    {out, vm} = QEMU.iex(vm, "Elixos.save(boot: [{Bad, :boot, []}])")
    assert out =~ "{:ok, 1}"
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)

    # Both attempts crash, and the shim falls back to the factory.
    vm =
      QEMU.boot(ctx, disk: disk, append: ["elixos.max_attempts=2", "elixos.commit_after=3600"])

    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: fallback to last_good=0/, 300_000)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)

    # Both dumps are on the disk, named for the generation and the attempt.
    {out, vm} = QEMU.iex(vm, ~s|Enum.sort(File.ls!("/priv/crash"))|)

    assert out =~ ~s|["gen1-attempt1.dump", "gen1-attempt2.dump"]|

    {out, vm} = QEMU.iex(vm, ~s|File.read!("/priv/crash/gen1-attempt1.dump")|)
    assert out =~ "=erl_crash_dump"
    assert out =~ "Slogan"
    # The dump says why: the boot spec this generation saved raised.
    assert out =~ "boot_spec_failed"
    assert out =~ "boom"

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "the newest five dumps are kept, whatever a crash loop does", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    # Seven dumps, oldest first, written the way a crash loop would.
    {_, vm} =
      QEMU.iex(
        vm,
        ~s|for i <- 1..7, do: File.write!("/priv/crash/gen9-attempt\#{i}.dump", "\#{i}")|
      )

    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)

    # The next boot prunes before launching: only the newest five survive.
    vm = QEMU.boot_to_iex(ctx, disk: disk, append: ["elixos.commit_after=3600"])
    {out, vm} = QEMU.iex(vm, ~s|Enum.sort(File.ls!("/priv/crash"))|)

    # Asserted element-wise: the console wraps a long inspected list.
    for kept <- 3..7 do
      assert out =~ "gen9-attempt#{kept}.dump"
    end

    refute out =~ "gen9-attempt1.dump"
    refute out =~ "gen9-attempt2.dump"
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
