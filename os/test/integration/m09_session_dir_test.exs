defmodule Elixos.Integration.M09SessionDirTest do
  @moduledoc """
  M9: every REPL session has its own working directory (ADR-020), and the VM's
  working directory never moves (ADR-016).

  Two console sessions means two console jobs: Ctrl-G starts a second local
  shell (an erl shell, whose `cd/1`, `pwd/0` and `ls/0,1` come from
  `user_default`), and `c <n>` connects to it.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 9
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  @ctrl_g "\a"

  test "two console sessions sit in different directories, and the VM stays at /", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))

    # The first session starts in the user's home, and the VM is at /.
    {out, vm} = QEMU.iex(vm, "pwd()")
    assert out =~ ~s("/priv/home")
    {out, vm} = QEMU.iex(vm, "File.cwd!()")
    assert out =~ ~s("/")

    # cd moves the session, not the VM.
    {out, vm} = QEMU.iex(vm, ~s|cd("/tmp")|)
    assert out =~ ~s("/tmp")
    {out, vm} = QEMU.iex(vm, "pwd()")
    assert out =~ ~s("/tmp")
    {out, vm} = QEMU.iex(vm, "File.cwd!()")
    assert out =~ ~s("/")

    # A second console job: Ctrl-G, start a local shell, connect to it. It is
    # an erl shell, and it starts in /priv/home too.
    vm = QEMU.send_raw(vm, @ctrl_g)
    {_, vm} = QEMU.expect(vm, ~r/User switch command/)
    vm = QEMU.send_line(vm, "s")
    vm = QEMU.send_line(vm, "c 2")
    {_, vm} = QEMU.expect(vm, ~r/Eshell V/, 60_000)
    {_, vm} = QEMU.expect(vm, ~r/1> /, 60_000)

    vm = QEMU.send_line(vm, "pwd().")
    {out, vm} = QEMU.expect_with_before(vm, ~r/2> /, 60_000)
    assert out =~ ~s("/priv/home")
    # Even in the second session the VM's directory is still /.
    vm = QEMU.send_line(vm, "file:get_cwd().")
    {out, vm} = QEMU.expect_with_before(vm, ~r/3> /, 60_000)
    assert out =~ ~s({ok,"/"})
    # and the second session has its own directory: cd here must not be seen
    # by the first one.
    vm = QEMU.send_line(vm, ~s|cd("/var").|)
    {_, vm} = QEMU.expect_with_before(vm, ~r/4> /, 60_000)

    # Back to the first session: its directory is what it was.
    vm = QEMU.send_raw(vm, @ctrl_g)
    {_, vm} = QEMU.expect(vm, ~r/User switch command/)
    vm = QEMU.send_line(vm, "c 1")
    {out, vm} = QEMU.iex(vm, "pwd()")
    assert out =~ ~s("/tmp")
    {out, vm} = QEMU.iex(vm, "File.cwd!()")
    assert out =~ ~s("/")

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
