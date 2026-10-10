defmodule Elixos.Integration.M06LiveImageTest do
  @moduledoc """
  M6: the live image. Code typed at the prompt persists across power cycles
  once saved, like a Lisp machine or a Smalltalk image (ADR-005).
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 6
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "a module defined at the prompt survives a power cycle once saved", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {_, vm} = QEMU.iex(vm, "defmodule Hello do\n  def hi, do: :persisted\nend")
    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ "{:ok, 1}"
    vm = QEMU.await_log(vm, ~r/elixos-shim: next generation=1/)
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)

    vm = QEMU.boot(ctx, disk: disk, append: ["elixos.commit_after=2"])
    {_, vm} = QEMU.expect(vm, ~r/plan generation=1 mode=normal attempt=1/, 180_000)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)
    {out, vm} = QEMU.iex(vm, "Hello.hi()")
    assert out =~ ":persisted"

    vm = QEMU.await_log(vm, ~r/elixos-shim: commit generation=1/, 60_000)
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "generations accumulate and can be listed", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    {_, vm} = QEMU.iex(vm, "defmodule A1, do: def(v, do: 1)")
    {_, vm} = QEMU.iex(vm, "Elixos.save()")
    {_, vm} = QEMU.iex(vm, "defmodule A2, do: def(v, do: 2)")
    {_, vm} = QEMU.iex(vm, "Elixos.save()")
    {out, vm} = QEMU.iex(vm, "Elixos.generations()")
    assert out =~ "[1, 2]"
    QEMU.stop(vm)
  end
end
