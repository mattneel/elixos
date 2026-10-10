defmodule Elixos.Integration.M13UEFIBootTest do
  @moduledoc """
  M13: the real-hardware path, under OVMF firmware. UEFI runs the mainline
  kernel directly through its EFI stub (ADR-014); no bootloader is involved.

  Needs `make uefi-image` (build/esp.img, an ESP holding EFI/BOOT/BOOTX64.EFI:
  the kernel with the initramfs and a serial command line built in) and OVMF.
  Physical hardware still gets the manual checklist in docs/ROADMAP.md.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 13
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, Paths, QEMU}

  @ovmf_dirs ["/usr/share/OVMF", "/usr/share/ovmf", "/usr/share/edk2/x64"]

  defp ovmf(tmp_dir) do
    dir =
      Enum.find(@ovmf_dirs, &File.exists?(Path.join(&1, "OVMF_CODE_4M.fd"))) ||
        flunk("OVMF not found")

    vars = Path.join(tmp_dir, "OVMF_VARS.fd")
    File.cp!(Path.join(dir, "OVMF_VARS_4M.fd"), vars)
    {Path.join(dir, "OVMF_CODE_4M.fd"), vars}
  end

  test "UEFI firmware boots the kernel's EFI stub straight to IEx", ctx do
    esp = Paths.build("esp.img")
    File.exists?(esp) || flunk("missing #{esp}; run `make uefi-image`")

    {code, vars} = ovmf(ctx.tmp_dir)
    vm = QEMU.boot(ctx, disk: Disk.fresh!(ctx.tmp_dir), uefi: {esp, code, vars})
    {_, vm} = QEMU.expect(vm, ~r/elixos-shim: pid 1, version \S+/, 300_000)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 300_000)

    {out, vm} = QEMU.iex(vm, ~s|File.dir?("/sys/firmware/efi")|)
    assert out =~ ~r/^true$/m, "booted through UEFI, not -kernel"
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
