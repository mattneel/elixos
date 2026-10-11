defmodule Elixos.Integration.M17EscapeHatchTest do
  @moduledoc """
  M17: the BEAM is unprivileged, committed recovery state is sealed, named
  helpers are refused safely, and NEXT/COMMIT and fallback retain their meaning
  (docs/ROADMAP.md, ADR-046).

  Reference note: none of these acceptance tests has been validated against a
  reference implementation yet; the M17 implementation does not exist yet.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 17
  @moduletag timeout: 1_200_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "the BEAM's real, effective, saved and filesystem uids are non-root", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    {out, vm} = QEMU.iex(vm, ~s{File.read!("/proc/self/status") |> IO.puts()})

    assert [_, real, effective, saved, filesystem] =
             Regex.run(~r/^Uid:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/m, out)

    assert Enum.all?([real, effective, saved, filesystem], &(String.to_integer(&1) > 0))
    assert Enum.uniq([real, effective, saved, filesystem]) == [real]
    assert out =~ ~r/^CapEff:\s+0000000000000400$/m

    {out, vm} = QEMU.iex(vm, "Elixos.Privileges.uid()")
    assert out =~ Regex.compile!("^" <> real <> "$", "m")
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "sealed recovery files and the factory reject writes, chmod and replacement from IEx",
       ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {out, vm} = QEMU.iex(vm, ~s|File.write("/priv/boot.state", "x")|)
    assert out =~ "{:error, :eacces}"
    {out, vm} = QEMU.iex(vm, ~s|File.chmod("/priv/boot.state", 0o666)|)
    assert out =~ ~r/\{:error, :(?:eacces|eperm)\}/
    {out, vm} = QEMU.iex(vm, ~s|File.rm("/priv/boot.state")|)
    assert out =~ ~r/\{:error, :(?:eacces|eperm)\}/
    {out, vm} = QEMU.iex(vm, ~s|File.rename("/priv/boot.state", "/priv/stolen-state")|)
    assert out =~ ~r/\{:error, :(?:eacces|eperm)\}/
    {out, vm} = QEMU.iex(vm, ~s|File.write("/etc/elixos/helpers", "anything 0:0 /anything")|)
    assert out =~ "{:error, :eacces}"

    {_, vm} =
      QEMU.iex(vm, ~s|factory = Path.join(to_string(:code.root_dir()), "erts/bin/erlexec")|)

    {out, vm} = QEMU.iex(vm, ~s|File.write(factory, "x")|)
    assert out =~ "{:error, :eacces}"

    {_, vm} = QEMU.iex(vm, "defmodule Sealed do\n  def value, do: :sealed\nend")
    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ "{:ok, 1}"
    vm = QEMU.await_log(vm, ~r/elixos-shim: next generation=1/)
    vm = power_off(vm)
    QEMU.stop(vm)

    vm = QEMU.boot(ctx, disk: disk, append: ["elixos.commit_after=2"])
    {_, vm} = QEMU.expect(vm, ~r/plan generation=1 mode=normal attempt=1/, 180_000)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)
    vm = QEMU.await_log(vm, ~r/elixos-shim: commit generation=1/, 60_000)
    {out, vm} = QEMU.iex(vm, ~s|File.write("/priv/generations/1.gen", "x")|)
    assert out =~ "{:error, :eacces}"
    {out, vm} = QEMU.iex(vm, ~s|File.chmod("/priv/generations/1.gen", 0o644)|)
    assert out =~ ~r/\{:error, :(?:eacces|eperm)\}/
    {out, vm} = QEMU.iex(vm, ~s|File.rm("/priv/generations/1.gen")|)
    assert out =~ ~r/\{:error, :(?:eacces|eperm)\}/
    {_, vm} = QEMU.iex(vm, ~s|{:ok, g} = Elixos.Image.Generation.read("/priv/generations", 1)|)
    {_, vm} = QEMU.iex(vm, ~s|{:ok, store} = Elixos.Image.Store.open("/priv/store")|)
    {_, vm} = QEMU.iex(vm, ~s|blob = Elixos.Image.Store.path_for(store, g.modules[Sealed])|)
    {out, vm} = QEMU.iex(vm, "File.write(blob, \"x\")")
    assert out =~ "{:error, :eacces}"
    {out, vm} = QEMU.iex(vm, "File.chmod(blob, 0o644)")
    assert out =~ ~r/\{:error, :(?:eacces|eperm)\}/
    {out, vm} = QEMU.iex(vm, "File.rm(blob)")
    assert out =~ ~r/\{:error, :(?:eacces|eperm)\}/
    {_, vm} = QEMU.iex(vm, ~s|File.write!("/priv/replacement", "wrong bytes")|)
    {out, vm} = QEMU.iex(vm, ~s|File.rename("/priv/replacement", blob)|)
    assert out =~ ~r/\{:error, :(?:eacces|eperm)\}/
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "descriptors opened before COMMIT cannot alter the sealed recovery bytes", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {_, vm} = QEMU.iex(vm, "defmodule HeldSeal do\n  def value, do: :held_safe\nend")
    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ "{:ok, 1}"
    vm = QEMU.await_log(vm, ~r/elixos-shim: next generation=1/)
    vm = power_off(vm)
    QEMU.refute_kernel_panic(vm)

    # Arrange handles before sealing, not a slower acceptance deadline. The
    # explicit control request below commits immediately once setup is complete.
    vm = QEMU.boot_to_iex(ctx, disk: disk, append: ["elixos.commit_after=600"])
    {_, vm} = QEMU.iex(vm, ~s|mp = "/priv/generations/1.gen"|)
    {_, vm} = QEMU.iex(vm, ~s|{:ok, g} = Elixos.Image.Generation.read("/priv/generations", 1)|)
    {_, vm} = QEMU.iex(vm, ~s|{:ok, store} = Elixos.Image.Store.open("/priv/store")|)
    {_, vm} = QEMU.iex(vm, "blob = Elixos.Image.Store.path_for(store, g.modules[HeldSeal])")
    {_, vm} = QEMU.iex(vm, "old = Enum.map([mp, blob], &File.read!/1)")
    {_, vm} = QEMU.iex(vm, "fopts = [:raw, :binary, :read, :write]")
    {_, vm} = QEMU.iex(vm, "opened = Enum.map([mp, blob], &:file.open(&1, fopts))")
    {_, vm} = QEMU.iex(vm, "valid = fn v -> match?({:ok, _}, v) or v == {:error, :eacces} end")
    {out, vm} = QEMU.iex(vm, "Enum.all?(opened, valid)")
    assert out =~ ~r/^true$/m
    refute QEMU.transcript(vm) =~ "elixos-shim: commit generation=1"
    {out, vm} = QEMU.iex(vm, "Elixos.Shim.Control.commit(1)")
    assert out =~ ~r/^:ok$/m
    vm = QEMU.await_log(vm, ~r/elixos-shim: commit generation=1/, 60_000)

    # Earlier sealing may already deny open; otherwise writes to the retained
    # old inode must not reach the committed paths. chmod/chown alone fails this.
    {_, vm} =
      QEMU.iex(
        vm,
        "smash = fn {:ok, fd} -> :file.pwrite(fd, 0, \"broken\"); :file.close(fd); {:error, :eacces} -> :blocked end"
      )

    {_, vm} = QEMU.iex(vm, "Enum.each(opened, smash)")
    {out, vm} = QEMU.iex(vm, "Enum.map([mp, blob], &File.read!/1) == old")
    assert out =~ ~r/^true$/m
    vm = power_off(vm)
    QEMU.refute_kernel_panic(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {out, vm} = QEMU.iex(vm, "HeldSeal.value()")
    assert out =~ ~r/^:held_safe$/m
    vm = power_off(vm)
    QEMU.refute_kernel_panic(vm)
  end

  test "a prompt module survives NEXT, COMMIT and another power cycle", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {_, vm} = QEMU.iex(vm, "defmodule EscapeHello do\n  def hi, do: :persisted\nend")
    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ "{:ok, 1}"
    vm = QEMU.await_log(vm, ~r/elixos-shim: next generation=1/)
    vm = power_off(vm)
    QEMU.stop(vm)

    vm = QEMU.boot(ctx, disk: disk, append: ["elixos.commit_after=2"])
    {_, vm} = QEMU.expect(vm, ~r/plan generation=1 mode=normal attempt=1/, 180_000)
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 180_000)
    {out, vm} = QEMU.iex(vm, "EscapeHello.hi()")
    assert out =~ ~r/^:persisted$/m
    vm = QEMU.await_log(vm, ~r/elixos-shim: commit generation=1/, 60_000)
    vm = power_off(vm)
    QEMU.stop(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {out, vm} = QEMU.iex(vm, "Elixos.info()")
    assert out =~ "generation: 1"
    {out, vm} = QEMU.iex(vm, "EscapeHello.hi()")
    assert out =~ ~r/^:persisted$/m
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "a candidate with a crashing boot spec still falls back to last_good", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {_, vm} = QEMU.iex(vm, ~s|defmodule Bad do\n  def boot, do: raise("boom")\nend|)
    {out, vm} = QEMU.iex(vm, "Elixos.save(boot: [{Bad, :boot, []}])")
    assert out =~ "{:ok, 1}"
    vm = power_off(vm)
    QEMU.stop(vm)

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
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "an unknown helper is refused and logged by the shim", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Privileges.request("no-such-helper")|)
    assert out =~ "{:error, :refused}"

    vm =
      QEMU.await_log(vm, ~r/^elixos-shim: helper refused name=no-such-helper$/m, 60_000)

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  defp power_off(vm) do
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end
end
