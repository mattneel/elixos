defmodule Elixos.Integration.M28Riscv64Test do
  @moduledoc """
  M28: the image is built for riscv64, the third architecture, and boots on
  `qemu-system-riscv64 -machine virt` - the smoke set M16 runs for aarch64.
  The BEAM's JIT does not cover RISC-V, so OTP runs the interpreter.
  `make test-qemu-riscv64` runs it; a plain x86_64 run never picks it up
  (:riscv64 is excluded unless that target asks).

  Reference limitation: no riscv64 Elixos existed before this milestone, so
  these assertions are checked only against this build's own boots.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag :riscv64
  @moduletag milestone: 28
  @moduletag timeout: 1_800_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "the riscv64 image boots to IEx, reports its architecture, keeps a module and powers off",
       ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    started = System.monotonic_time(:millisecond)
    vm = QEMU.boot_to_iex(ctx, disk: disk, arch: :riscv64)
    boot_ms = System.monotonic_time(:millisecond) - started

    {out, vm} = QEMU.iex(vm, "Elixos.info()")
    assert out =~ ~s(arch: "riscv64"), "Elixos.info must report the architecture: #{out}"

    # Recorded in docs/ROADMAP.md (M28 notes): boot-to-IEx time under TCG and
    # the memory the guest is using once the prompt is up.
    {meminfo, vm} =
      QEMU.iex(
        vm,
        ~S'File.read!("/proc/meminfo") |> String.split("\n") |> Enum.take(3) |> Enum.join(" ")'
      )

    IO.puts("\nm28: boot to iex(1)> in #{boot_ms} ms (TCG); #{meminfo}")

    {out, vm} = QEMU.iex(vm, ~s|defmodule RiscProbe do\n  def value, do: :riscv_ok\nend|, 300_000)
    assert out =~ "{:module, RiscProbe"

    {out, vm} = QEMU.iex(vm, "Elixos.save()", 300_000)
    assert out =~ ~r/\{:ok, \d+\}/

    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm, 300_000)

    vm = QEMU.boot_to_iex(ctx, disk: disk, arch: :riscv64)

    {out, vm} = QEMU.iex(vm, "RiscProbe.value()")
    assert out =~ ~r/^:riscv_ok$/m

    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm, 300_000)
    QEMU.refute_kernel_panic(vm)
  end

  test "the riscv64 BEAM runs the interpreter", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir), arch: :riscv64)

    {out, vm} = QEMU.iex(vm, ":erlang.system_info(:emu_flavor)")
    assert out =~ ~r/^:emu$/m

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
