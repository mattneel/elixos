defmodule Elixos.Integration.M24NativeTest do
  @moduledoc """
  M24 (ADR-050): a native edit runs through the on-box dispatcher in its
  session's workspace. Content-addressed x86_64 musl libraries hash their
  actual file bytes, identify the bundled Zig toolchain, and persist as exact
  `Elixos.Image` manifest pins across a committed generation's power cycle.

  Reference note: the read and hashline edit request shapes come from pinned
  OMP 18.8.7, not an Elixos reference. None of these native dispatch, toolchain
  or generation-persistence acceptance tests has been checked against a
  reference M24 implementation yet.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 24
  @moduletag timeout: 1_200_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "native edit and bundled Zig pins survive a committed generation power cycle", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk)

    {_, vm} = QEMU.iex(vm, "vm_cwd = File.cwd!()")
    {_, vm} = QEMU.iex(vm, "vm_env = System.get_env()")
    {_, vm} = QEMU.iex(vm, ~s|work = "/priv/work/m24-native"|)
    {_, vm} = QEMU.iex(vm, "File.mkdir_p!(work)")
    {_, vm} = QEMU.iex(vm, ~s|File.write!(work <> "/note.txt", "before\\n")|)
    {_, vm} = QEMU.iex(vm, "s = Elixos.Toolset.Session.new(workspace: work, session_dir: work)")

    vm = native_edit(vm, "native edit")

    {_, vm} = QEMU.iex(vm, ~s|zc = "/priv/toolchain/zigler/zig"|)
    {_, vm} = QEMU.iex(vm, ~s|{zv, 0} = System.cmd(zc, ["version"], cd: s.session_dir)|, 120_000)
    {out, vm} = QEMU.iex(vm, "IO.puts(\"ZIG=\" <> String.trim(zv))")
    assert [_, zig_version] = Regex.run(~r/^ZIG=(\S+)$/m, out)
    {out, vm} = QEMU.iex(vm, "{File.cwd!(), System.get_env()} == {vm_cwd, vm_env}")
    assert out =~ ~r/^true$/m

    {pins, vm} = pins(vm)
    assert pins != []

    Enum.each(pins, fn pin ->
      assert pin.target == "x86_64-linux-musl"
      # The display format is unspecified: accept "zig@<version>" as well as
      # a bare version, but never accept a prefix of a different Zig version.
      version_token = ~r/(?<![0-9A-Za-z.+-])#{Regex.escape(zig_version)}(?![0-9A-Za-z.+-])/
      assert Regex.match?(version_token, pin.toolchain)
    end)

    {out, vm} = QEMU.iex(vm, "Elixos.save()", 120_000)
    assert [_, generation] = Regex.run(~r/\{:ok, (\d+)\}/, out)
    {saved_pins, vm} = manifest_pins(vm, generation)
    assert saved_pins == pins
    vm = QEMU.await_log(vm, ~r/elixos-shim: next generation=#{generation}\b/)
    vm = power_off(vm)
    QEMU.refute_kernel_panic(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk, append: ["elixos.commit_after=2"])
    vm = QEMU.await_log(vm, ~r/elixos-shim: commit generation=#{generation}\b/, 60_000)
    {out, vm} = QEMU.iex(vm, "Elixos.info().generation")
    assert out =~ ~r/^#{generation}$/m
    {committed_pins, vm} = pins(vm)
    assert committed_pins == pins
    {committed_manifest_pins, vm} = manifest_pins(vm, generation)
    assert committed_manifest_pins == saved_pins
    vm = power_off(vm)
    QEMU.refute_kernel_panic(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {out, vm} = QEMU.iex(vm, "Elixos.info().generation")
    assert out =~ ~r/^#{generation}$/m
    {after_cycle, vm} = pins(vm)
    assert after_cycle == committed_pins
    {cycled_manifest_pins, vm} = manifest_pins(vm, generation)
    assert cycled_manifest_pins == saved_pins

    # Restored pins must remain usable, not merely survive as a copied list.
    {_, vm} = QEMU.iex(vm, ~s|work = "/priv/work/m24-native"|)
    {out, vm} = QEMU.iex(vm, ~s|File.read!(work <> "/note.txt") == "native edit\\n"|)
    assert out =~ ~r/^true$/m
    {_, vm} = QEMU.iex(vm, "s = Elixos.Toolset.Session.new(workspace: work, session_dir: work)")
    vm = native_edit(vm, "after power cycle")
    {after_call_pins, vm} = pins(vm)
    assert after_call_pins == after_cycle
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  defp native_edit(vm, replacement) do
    # Pinned OMP read supplies the current TAG for its hashline edit schema.
    {out, vm} =
      QEMU.iex(vm, ~s|Elixos.Toolset.call("read", %{"path" => "note.txt"}, session: s)|, 120_000)

    assert out =~ "{:ok,"
    assert [_, tag] = Regex.run(~r/\[[^\]\r\n]*note\.txt#([0-9A-Fa-f]{4})\]/, out)

    patch = "*** Begin Patch\n[note.txt##{tag}]\nPUT 1.=1:\n+#{replacement}\n*** End Patch\n"
    {_, vm} = QEMU.iex(vm, "ep = %{\"input\" => #{inspect(patch)}}")
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Native.promote("edit")|, 120_000)
    assert out =~ ~r/^:ok$/m
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Toolset.call("edit", ep, session: s)|, 120_000)
    assert out =~ "{:ok,"

    {out, vm} =
      QEMU.iex(vm, "File.read!(work <> \"/note.txt\") == #{inspect(replacement <> "\n")}")

    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Toolset.last_run("edit").implementation|)
    assert out =~ ~r/^:native$/m
    vm
  end

  defp pins(vm) do
    expression =
      "Enum.map(Elixos.Native.library_pins(), fn pin -> " <>
        "{pin, :crypto.hash(:sha256, File.read!(pin.file)) |> Base.encode16(case: :lower)} end)"

    {verified, vm} = guest_term(vm, "PINS", expression)
    assert [_ | _] = verified

    pins =
      Enum.map(verified, fn {pin, actual_sha256} ->
        assert %{file: file, sha256: sha256, target: target, toolchain: toolchain} = pin
        assert sha256 == actual_sha256
        assert String.contains?(Path.basename(file), actual_sha256)
        assert target == "x86_64-linux-musl"
        assert is_binary(toolchain) and String.trim(toolchain) != ""
        pin
      end)

    assert length(Enum.uniq_by(pins, & &1.file)) == length(pins)
    {pins, vm}
  end

  defp manifest_pins(vm, generation) do
    expression =
      "(case Elixos.Image.generation(Process.whereis(Elixos.Image), #{generation}) do " <>
        "{:ok, manifest} -> manifest.native_libraries; error -> raise inspect(error) end)"

    guest_term(vm, "MANIFEST_PINS", expression)
  end

  defp guest_term(vm, marker, expression) do
    command =
      ~s|IO.puts("#{marker}=" <> Base.encode64(:erlang.term_to_binary(#{expression})))|

    {out, vm} = QEMU.iex(vm, command)
    assert [_, encoded] = Regex.run(~r/^#{marker}=([A-Za-z0-9+\/=]+)$/m, out)
    {encoded |> Base.decode64!() |> :erlang.binary_to_term([:safe]), vm}
  end

  defp power_off(vm) do
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    vm
  end
end
