defmodule Elixos.Integration.M27GuiTest do
  @moduledoc """
  M27 with ADR-093: the framebuffer GUI is an optional front-end for
  Oh-My-Jido approvals. The machine boots to IEx with the console untouched;
  with nothing pending the GUI refuses to take the screen. A real Oh-My-Jido
  question opens it, injected keys answer it, the waiting tool gets the
  answer, and the console is IEx's again because nothing is pending. Escape
  hands the screen back while the question stays pending.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 27
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  @question ~s|%{question: "proceed?", options: [%{label: "yes"}, %{label: "no"}]}|

  test "an Oh-My-Jido question is answered on the framebuffer with keys", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    # The harness boots a virtio-gpu when asked; the guest's /dev/fb0 is the
    # panel the GUI draws on.
    vm = QEMU.boot_to_iex(ctx, disk: disk, gpu: true)

    # Boot never hands the screen to the GUI, and nothing pending keeps it so.
    {out, vm} = QEMU.iex(vm, "Elixos.GUI.status()")
    assert out =~ "{:error, :not_running}"
    {out, vm} = QEMU.iex(vm, "Elixos.GUI.start()")
    assert out =~ "{:error, :nothing_pending}"
    {out, vm} = QEMU.iex(vm, "Elixos.GUI.status()")
    assert out =~ "{:error, :not_running}"

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|{:ok, session} = OhMyJido.start_session(Elixos.Approvals.runtime(), workspace: "/priv/home", tools: [OhMyJido.Tools.Question], permissions: [:ask])|,
        120_000
      )

    assert out =~ "{:ok, "

    # A question asked from a process so the prompt stays free; the tool's
    # result is written where the test can read it.
    vm = ask(vm, "/priv/answer.txt")
    vm = await_true(vm, "length(Elixos.Approvals.pending()) == 1")

    # What the panel shows before the GUI opens.
    {before, vm} = QEMU.iex(vm, ~s|:crypto.hash(:sha256, File.read!("/dev/fb0"))|)

    {out, vm} = QEMU.iex(vm, "Elixos.GUI.start()", 120_000)
    assert out =~ "{:ok, "

    # The dialog reached the panel: the framebuffer changed.
    {after_draw, vm} = QEMU.iex(vm, ~s|:crypto.hash(:sha256, File.read!("/dev/fb0"))|)
    refute after_draw == before

    # Keys select the first option and accept it.
    vm =
      Enum.reduce(["ArrowDown", "ArrowUp"], vm, fn key, vm ->
        {out, vm} = QEMU.iex(vm, ~s|Elixos.GUI.input({:key, "#{key}", :press})|)
        assert out =~ ":ok"
        vm
      end)

    {out, vm} = QEMU.iex(vm, ~s|Elixos.GUI.input({:key, "Enter", :press})|)
    assert out =~ ":ok"

    vm = await_true(vm, ~s|File.exists?("/priv/answer.txt")|)
    vm = await_true(vm, answered?("/priv/answer.txt", "yes"))

    # Nothing is pending, so the GUI handed the console back (fbcon rebound).
    vm = await_true(vm, "Elixos.GUI.status() == {:error, :not_running}")
    {out, vm} = QEMU.iex(vm, "Elixos.Approvals.pending()")
    assert out =~ ~r/^\[\]$/m
    {out, vm} = QEMU.iex(vm, "40 + 2")
    assert out =~ ~r/^42$/m

    # Escape hands the screen back and decides nothing.
    vm = ask(vm, "/priv/answer2.txt")
    vm = await_true(vm, "length(Elixos.Approvals.pending()) == 1")

    {out, vm} = QEMU.iex(vm, "Elixos.GUI.start()", 120_000)
    assert out =~ "{:ok, "
    {out, vm} = QEMU.iex(vm, ~s|Elixos.GUI.input({:key, "Escape", :press})|)
    assert out =~ ":ok"

    {out, vm} = QEMU.iex(vm, "Elixos.GUI.status()")
    assert out =~ "{:error, :not_running}"

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|match?([%Elixos.Approvals.Request{prompt: "proceed?"}], Elixos.Approvals.pending())|
      )

    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, ~s|File.exists?("/priv/answer2.txt")|)
    assert out =~ ~r/^false$/m
    {out, vm} = QEMU.iex(vm, "40 + 2")
    assert out =~ ~r/^42$/m

    # The question is still answerable from IEx.
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Approvals.answer(hd(Elixos.Approvals.pending()).id, "no")|)
    assert out =~ ":ok"
    vm = await_true(vm, ~s|File.exists?("/priv/answer2.txt")|)
    vm = await_true(vm, answered?("/priv/answer2.txt", "no"))

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  defp ask(vm, path) do
    {out, vm} =
      QEMU.iex(
        vm,
        ~s|spawn(fn -> File.write!("#{path}", :erlang.term_to_binary(OhMyJido.execute_tool(session, "question", #{@question}))) end)|,
        120_000
      )

    assert out =~ "#PID<"
    vm
  end

  defp answered?(path, label),
    do:
      ~s|match?({:ok, %{answer: %{label: "#{label}"}}}, :erlang.binary_to_term(File.read!("#{path}")))|

  defp await_true(vm, expr, tries \\ 120) do
    Enum.reduce_while(1..tries, {vm, false}, fn _, {vm, _} ->
      {out, vm} = QEMU.iex(vm, expr)

      if out =~ ~r/^true$/m do
        {:halt, {vm, true}}
      else
        Process.sleep(250)
        {:cont, {vm, false}}
      end
    end)
    |> case do
      {vm, true} -> vm
      {_vm, false} -> flunk("never true in the guest: #{expr}")
    end
  end
end
