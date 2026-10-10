defmodule Elixos.Integration.M21AskTest do
  @moduledoc """
  M21: an agent asks the human through the Jido action, the console shows the
  notice line, and the answer is typed at the prompt - the same queue every
  front-end shares (the GUI is M22).
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 21
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  defp modules do
    """
    defmodule Demo.AskAgent do
      use Jido.Agent,
        name: "asker",
        schema: [answer: [type: :string, default: ""]],
        signal_routes: [{"ask_human", Elixos.Ask.Action}]
    end
    """
  end

  test "an agent's question is answered at the prompt", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk)

    {out, vm} = QEMU.iex(vm, "(" <> modules() <> ")", 120_000)
    assert out =~ "{:module, Demo.AskAgent"

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Agents.start(Demo.AskAgent, id: "asker", jido: Jido)|)
    assert out =~ "{:ok, #PID<"

    # The action blocks its own process, not the prompt: ask from a spawn.
    {out, vm} =
      QEMU.iex(
        vm,
        ~s|spawn(fn -> Jido.AgentServer.call(Elixos.Agents.whereis("asker"), Jido.Signal.new!("ask_human", %{kind: "text", prompt: "your name?"})) end)|,
        120_000
      )

    assert out =~ "#PID<"

    # The REPL front-end prints one notice line per question (PROTOCOL.md §6),
    # and the question is open in the queue.
    {_notice, vm} = QEMU.expect(vm, ~r/elixos-ask: question \S+ \(text\): your name\?/, 120_000)
    {out, vm} = QEMU.iex(vm, "Elixos.Ask.pending() |> Enum.map(& &1.prompt)")
    assert out =~ "your name?"

    # Answering is any front-end's job, and this one is the prompt's.
    {out, vm} =
      QEMU.iex(
        vm,
        """
        Elixos.Ask.answer(Elixos.Ask.pending() |> hd() |> Map.fetch!(:id), "matt")
        """
      )

    assert out =~ ":ok"

    # The action returned the answer into the agent's state, and the queue is
    # empty again.
    vm = await_state(vm, "matt")
    {out, vm} = QEMU.iex(vm, "Elixos.Ask.pending()")
    assert out =~ "[]"

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  # The answer lands in the agent's state when the action returns; that trip
  # is asynchronous, so the test polls for it rather than sleeping.
  defp await_state(vm, value, tries \\ 120) do
    Enum.reduce_while(1..tries, vm, fn _, vm ->
      {out, vm} =
        QEMU.iex(
          vm,
          """
          Jido.AgentServer.state(Elixos.Agents.whereis("asker")).agent.state
          |> inspect()
          |> String.contains?(#{inspect(value)})
          """
        )

      if out =~ ~r/^true$/m do
        {:halt, vm}
      else
        Process.sleep(250)
        {:cont, vm}
      end
    end)
  end
end
