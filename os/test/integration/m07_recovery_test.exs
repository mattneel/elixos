defmodule Elixos.Integration.M07RecoveryTest do
  @moduledoc "M7: recovery is IEx too. Bad generations fall back; nothing typed is lost."
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 7
  @moduletag timeout: 1_200_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  defp power_off(vm) do
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end

  test "a generation whose boot spec crashes falls back to last_good", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {_, vm} = QEMU.iex(vm, ~s|defmodule Bad do\n  def boot, do: raise("boom")\nend|)
    {out, vm} = QEMU.iex(vm, "Elixos.save(boot: [{Bad, :boot, []}])")
    assert out =~ "{:ok, 1}"
    power_off(vm)

    vm = QEMU.boot(ctx, disk: disk, append: ["elixos.max_attempts=2"])
    {_, vm} = QEMU.expect(vm, ~r/plan generation=1 mode=normal attempt=1/, 180_000)
    {_, vm} = QEMU.expect(vm, ~r/plan generation=1 mode=normal attempt=2/, 180_000)

    {_, vm} =
      QEMU.expect(
        vm,
        ~r/elixos-shim: fallback to last_good=0 after 2 attempts of generation=1/,
        180_000
      )

    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)

    {out, vm} = QEMU.iex(vm, "Elixos.info()")
    assert out =~ "generation: 0"
    power_off(vm)
  end

  test "unsaved changes are recoverable after a power cycle", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {_, vm} = QEMU.iex(vm, "defmodule Unsaved do\n  def hi, do: :recovered\nend")
    power_off(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {out, vm} = QEMU.iex(vm, "Code.ensure_loaded?(Unsaved)")
    assert out =~ ~r/^false$/m
    {out, vm} = QEMU.iex(vm, "Elixos.unsaved(0)")
    assert out =~ "[Unsaved]"
    {_, vm} = QEMU.iex(vm, "Elixos.recover([Unsaved])")
    {out, vm} = QEMU.iex(vm, "Unsaved.hi()")
    assert out =~ ":recovered"
    power_off(vm)
  end

  test "elixos.safe boots the factory in rescue mode without user code", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {_, vm} = QEMU.iex(vm, "defmodule Hello, do: def(hi, do: :hi)")
    {_, vm} = QEMU.iex(vm, "Elixos.save()")
    power_off(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk, append: ["elixos.safe"])
    {out, vm} = QEMU.iex(vm, "Elixos.info()")
    assert out =~ "mode: :rescue"
    assert out =~ "generation: 0"
    {out, vm} = QEMU.iex(vm, "Code.ensure_loaded?(Hello)")
    assert out =~ ~r/^false$/m
    power_off(vm)
  end

  test "the base system is sticky: a REPL slip cannot replace Enum", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    {out, vm} = QEMU.iex(vm, "defmodule Enum do\n  def map(_, _), do: :hijacked\nend")
    assert out =~ ~r/sticky|error/i
    {out, vm} = QEMU.iex(vm, "Enum.map([1, 2], &(&1 * 2))")
    assert out =~ "[2, 4]"
    QEMU.stop(vm)
  end
end
