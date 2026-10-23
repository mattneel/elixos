defmodule Elixos.Integration.M27RamLiveTest do
  @moduledoc """
  RAM-backed normal Live boots use the packaged services without mounting even
  an explicitly selected valid data disk. Files, code generations and database
  changes disappear on a cold boot; the attached disk stays byte-identical.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 27
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, Paths, QEMU}

  test "normal Live services and saved code stay in RAM across cold boots", ctx do
    initramfs = Path.join(ctx.tmp_dir, "live.cpio.gz")

    {output, status} =
      System.cmd(
        Path.join(Paths.repo_root(), "scripts/mkinitramfs.sh"),
        ["--live", Paths.build("initramfs.cpio.gz"), initramfs, "x86_64"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    disk = Disk.fresh!(ctx.tmp_dir)
    before = digest(disk)

    opts = [
      disk: disk,
      initramfs: initramfs,
      memory_mb: 4096,
      gpu: true,
      append: ["elixos.live=1", "elixos.data=/dev/vda", "elixos.data_wait=600000"]
    ]

    vm = QEMU.boot_to_iex(ctx, opts)
    {out, vm} = QEMU.iex(vm, "Elixos.info()")
    assert out =~ "mode: :normal", out

    {out, vm} =
      QEMU.iex(vm, """
      mounts = File.read!("/proc/mounts") |> String.split("\\n")
      %{
        physical_mount: Enum.any?(mounts, &Regex.match?(~r{^/dev/(?:vd|sd|nvme)}, &1)),
        system_mount: Enum.find(mounts, &String.contains?(&1, " /system ")),
        gui: Process.whereis(Elixos.GUI),
        framebuffer: File.exists?("/dev/fb0")
      }
      """)

    assert out =~ "physical_mount: false", out
    assert out =~ ~r{/system\s+\S+\s+ro[, ]}, out
    assert out =~ "gui: nil", out
    assert out =~ "framebuffer: true", out

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|Elixos.Postgres.query("create table ram_live_probe (n integer); insert into ram_live_probe values (42); select n from ram_live_probe")|,
        120_000
      )

    assert out =~ ~r/^\s*42\s*$/m, out

    {out, vm} =
      QEMU.iex(vm, """
      File.write!("/priv/home/ram-live-marker", "disposable")
      defmodule RamLiveScratch, do: def(answer, do: 42)
      Elixos.save()
      """)

    assert out =~ "{:ok, 1}", out
    power_off(vm)
    assert digest(disk) == before

    vm = QEMU.boot_to_iex(ctx, opts)

    {out, vm} =
      QEMU.iex(vm, """
      %{
        boot: Elixos.info(),
        marker: File.exists?("/priv/home/ram-live-marker"),
        scratch: Code.ensure_loaded?(RamLiveScratch),
        generations: Elixos.generations()
      }
      """)

    assert out =~ "mode: :normal", out
    assert out =~ "generation: 0", out
    assert out =~ "marker: false", out
    assert out =~ "scratch: false", out
    assert out =~ "generations: []", out

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|Elixos.Postgres.query("select to_regclass('public.ram_live_probe') is null")|,
        120_000
      )

    assert out =~ ~r/^\s*t\s*$/m, out
    power_off(vm)
    assert digest(disk) == before
  end

  defp power_off(vm) do
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end

  defp digest(path) do
    {output, 0} = System.cmd("sha256sum", [path])
    output |> String.split() |> hd()
  end
end
