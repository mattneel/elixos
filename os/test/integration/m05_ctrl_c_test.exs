defmodule Elixos.Integration.M05CtrlCTest do
  @moduledoc """
  Ctrl+C interrupts the running expression at the console (M5).

  The console is a tty that is not the shell's controlling terminal, so OTP's
  default leaves Ctrl+C doing nothing: a runaway expression can only be stopped
  with Ctrl+G, `i`. The shim launches the BEAM with `+Bc` (PROTOCOL.md §3), so
  Ctrl+C is the interrupt it should be and the prompt stays usable.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 5
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "Ctrl+C interrupts a runaway expression and leaves the prompt usable", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))

    # Type the expression, wait for it to be echoed (so it is the expression
    # being evaluated, not a half-typed line), then interrupt it.
    vm = QEMU.send_line(vm, "Process.sleep(:infinity)")
    {_, vm} = QEMU.expect(vm, ~r/Process\.sleep\(:infinity\)/, 60_000)
    Process.sleep(500)
    # Ctrl+C then Enter, as a keyboard sends it: the console's tty is cooked,
    # so the kernel holds the ^C until a newline, and user_drv drops the rest
    # of whatever chunk carries the ^C (ADR-024).
    vm = QEMU.send_raw(vm, "\x03\r")

    # The interrupt aborts the expression and IEx starts a fresh session
    # (banner and all): wait for both before typing anything else, or the line
    # lands in a session that is still being replaced.
    {_, vm} = QEMU.expect(vm, ~r/\*\* \(EXIT\) interrupted/, 90_000)
    {_, vm} = QEMU.expect(vm, ~r/iex\(\d+\)> /, 60_000)

    # The session still works.
    {out, vm} = QEMU.iex(vm, "40 + 2", 120_000)
    assert out =~ ~r/^42$/m

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
