defmodule Elixos.Integration.M28Riscv64Test do
  @moduledoc """
  M28: the image is built for riscv64, the third architecture, and boots on
  `qemu-system-riscv64 -machine virt` - the smoke set M16 runs for aarch64.
  The BEAM's JIT does not cover RISC-V, so OTP runs the interpreter.
  Elixos.Test.QEMU gains `arch: :riscv64` as part of this milestone.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag :riscv64
  @moduletag milestone: 28
  @moduletag timeout: 1_800_000
  @moduletag :tmp_dir

  test "the riscv64 image boots to IEx, reports its architecture, keeps a module and powers off" do
    # Behaviour: on a fresh disk, QEMU.boot_to_iex(ctx, disk: disk, arch: :riscv64)
    # reaches iex(1)>; Elixos.info() reports riscv64; a module defined at the
    # prompt survives Elixos.save(), Elixos.poweroff() (exit 0) and a second
    # boot of the same disk; the second boot powers off cleanly with no kernel
    # panic.
    Elixos.NotImplemented.raise!(
      28,
      "riscv64 virt smoke set: boot to iex(1)>, Elixos.info reports riscv64, save, reboot, still there, poweroff"
    )
  end

  test "the riscv64 BEAM runs the interpreter" do
    # Behaviour: at the riscv64 prompt, :erlang.system_info(:emu_flavor)
    # answers :emu (no JIT on RISC-V).
    Elixos.NotImplemented.raise!(28, "riscv64 BEAM reports emu_flavor :emu")
  end
end
