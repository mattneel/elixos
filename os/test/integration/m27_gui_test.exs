defmodule Elixos.Integration.M27GuiTest do
  @moduledoc """
  M27: the dialog on the machine's own screen. A pending question appears on
  the framebuffer, an injected key answers it, the asker gets the answer, and
  the console is IEx's again once the GUI exits.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 27
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "a question on the framebuffer is answered with a key", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    # The harness boots a virtio-gpu when asked; the guest's /dev/fb0 is the
    # panel the GUI draws on.
    vm = QEMU.boot_to_iex(ctx, disk: disk, gpu: true)

    {out, vm} = QEMU.iex(vm, "Elixos.GUI.status()")
    assert out =~ "{:ok, "

    # What the panel shows before the question.
    {before, vm} = QEMU.iex(vm, ~s|:crypto.hash(:sha256, File.read!("/dev/fb0"))|)

    # A question for the GUI to show, asked from a process so the prompt stays
    # free; the answer is written where the test can read it.
    {out, vm} =
      QEMU.iex(
        vm,
        ~s|spawn(fn -> File.write!("/priv/answer.txt", inspect(Elixos.Ask.ask(:confirm, prompt: "really?"))) end)|,
        120_000
      )

    assert out =~ "#PID<"

    {out, vm} = QEMU.iex(vm, "length(Elixos.Ask.pending())")
    assert out =~ ~r/^1$/m

    # The dialog reached the panel: the framebuffer changed.
    {after_draw, vm} = QEMU.iex(vm, ~s|:crypto.hash(:sha256, File.read!("/dev/fb0"))|)
    refute after_draw == before

    # A key answers the question - y confirms.
    {out, vm} = QEMU.iex(vm, ~s|Elixos.GUI.input({:key, "y", :press})|)
    assert out =~ ":ok"

    vm = await_answer(vm)
    {out, vm} = QEMU.iex(vm, ~s|File.read!("/priv/answer.txt")|)
    assert out =~ "{:ok, true}"

    # Stop the GUI: the console is IEx's again (fbcon is rebound), and rescue
    # was never part of this.
    {out, vm} = QEMU.iex(vm, "Elixos.GUI.stop()")
    assert out =~ ":ok"
    {out, vm} = QEMU.iex(vm, "40 + 2")
    assert out =~ ~r/^42$/m

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  defp await_answer(vm, tries \\ 120) do
    Enum.reduce_while(1..tries, vm, fn _, vm ->
      {out, vm} = QEMU.iex(vm, ~s|File.exists?("/priv/answer.txt")|)

      if out =~ ~r/^true$/m do
        {:halt, vm}
      else
        Process.sleep(250)
        {:cont, vm}
      end
    end)
  end
end
