defmodule Elixos.Integration.M17ObanTest do
  @moduledoc """
  M17: Oban is the machine's scheduler. A worker defined at the prompt runs; a
  job scheduled for later is a row in Postgres and survives a power cycle
  (the worker module comes back from the image), running on the next boot;
  rescue mode runs no Oban.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 17
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  # A worker a prompt defines: it appends its line to a file on /priv, so the
  # test can see it from the outside.
  defp worker do
    """
    defmodule Demo.Job do
      use Oban.Worker, queue: :default

      @impl Oban.Worker
      def perform(%Oban.Job{args: %{"line" => line}}) do
        File.write!("/priv/jobs.log", line <> "\\n", [:append])
        :ok
      end
    end
    """
  end

  defp power_off(vm) do
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end

  # Waits for `line` to show up in /priv/jobs.log, by asking the guest.
  defp await_line(vm, line, tries) do
    Enum.reduce_while(1..tries, vm, fn _, vm ->
      {out, vm} =
        QEMU.iex(
          vm,
          ~s|File.exists?("/priv/jobs.log") and File.read!("/priv/jobs.log") =~ "#{line}"|
        )

      if out =~ ~r/^true$/m do
        {:halt, vm}
      else
        Process.sleep(500)
        {:cont, vm}
      end
    end)
  end

  test "a job scheduled for later survives a power cycle", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk)

    {out, vm} = QEMU.iex(vm, "Elixos.Oban.status()")
    assert out =~ "{:ok, "

    {out, vm} = QEMU.iex(vm, "(" <> worker() <> ")", 120_000)
    assert out =~ "{:module, Demo.Job"

    # Enqueued now: it runs now.
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Oban.enqueue(Demo.Job, %{"line" => "before"})|)
    assert out =~ "{:ok, "

    vm = await_line(vm, "before", 60)
    {out, vm} = QEMU.iex(vm, ~s|File.read!("/priv/jobs.log")|)
    assert out =~ "before", "the enqueued job ran"

    # Scheduled for later: a row in Postgres, and the worker module in the
    # image. Neither has run it yet.
    {out, vm} =
      QEMU.iex(vm, ~s|Elixos.Oban.enqueue(Demo.Job, %{"line" => "after"}, schedule_in: 45)|)

    assert out =~ "{:ok, "

    {out, vm} = QEMU.iex(vm, ~s|File.read!("/priv/jobs.log")|)
    refute out =~ "after"

    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ ~r/\{:ok, \d+\}/

    power_off(vm)

    # Next boot: the module is back (the image), the job is back (Postgres),
    # and it runs when it is due.
    vm = QEMU.boot_to_iex(ctx, disk: disk)

    {out, vm} = QEMU.iex(vm, "Code.ensure_loaded?(Demo.Job)")
    assert out =~ ~r/^true$/m

    vm = await_line(vm, "after", 180)
    {out, _vm} = QEMU.iex(vm, ~s|File.read!("/priv/jobs.log")|)
    assert out =~ "after", "the scheduled job ran after the power cycle"

    # Rescue runs no Oban.
    vm = QEMU.boot(ctx, disk: disk, append: ["elixos.safe"])
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 300_000)

    {out, vm} = QEMU.iex(vm, "Elixos.Oban.status()")
    assert out =~ "{:error, :not_running}"

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
