defmodule Elixos.Integration.M11SelfHostingTest do
  @moduledoc """
  M11: self-hosting. Regular Mix projects build and install on the box itself
  with MIX_TARGET=elixos, and NIFs compile with the bundled zig cc (ADR-009)
  and dlopen into the dynamic musl ERTS (ADR-008).
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 11
  @moduletag timeout: 2_400_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, Paths, QEMU}

  @big_vm [memory_mb: 2048]

  defp disk_with_fixtures(tmp_dir) do
    disk = Disk.fresh!(tmp_dir)
    Disk.put_tree!(disk, Paths.fixture("sample_app"), "/src/sample_app")
    Disk.put_tree!(disk, Paths.fixture("sample_nif"), "/src/sample_nif")
    disk
  end

  test "a regular Mix app installs from source and its services start", ctx do
    vm = QEMU.boot_to_iex(ctx, [disk: disk_with_fixtures(ctx.tmp_dir)] ++ @big_vm)

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.install("/priv/src/sample_app")|, 600_000)
    assert out =~ "{:ok, :sample_app}"

    {out, vm} = QEMU.iex(vm, "SampleApp.where()")
    assert out =~ ":elixos", "built with MIX_TARGET=elixos, so config/elixos.exs applied"

    {out, vm} = QEMU.iex(vm, "SampleApp.Worker.ping()")
    assert out =~ ":pong", "services from the elixos: key are started"
    QEMU.stop(vm)
  end

  test "a C NIF compiles on the box with zig cc and loads", ctx do
    vm = QEMU.boot_to_iex(ctx, [disk: disk_with_fixtures(ctx.tmp_dir)] ++ @big_vm)

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.install("/priv/src/sample_nif")|, 900_000)
    assert out =~ "{:ok, :sample_nif}"

    {out, vm} = QEMU.iex(vm, "SampleNif.add(40, 2)")
    assert out =~ ~r/^42$/m
    QEMU.stop(vm)
  end

  test "installed apps are part of the image and survive a power cycle", ctx do
    disk = disk_with_fixtures(ctx.tmp_dir)

    vm = QEMU.boot_to_iex(ctx, [disk: disk] ++ @big_vm)
    {_, vm} = QEMU.iex(vm, ~s|Elixos.Package.install("/priv/src/sample_app")|, 600_000)
    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ ~r/\{:ok, \d+\}/
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)

    vm = QEMU.boot_to_iex(ctx, [disk: disk] ++ @big_vm)
    {out, vm} = QEMU.iex(vm, "SampleApp.Worker.ping()")
    assert out =~ ":pong"
    QEMU.stop(vm)
  end
end
