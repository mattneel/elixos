defmodule Elixos.Integration.M09REPLLoginTest do
  @moduledoc "M9: REPLs are the login shells, and they all share one running world (ADR-012)."
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 9
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  @erl_prompt ~r/(^|\n)\d+> /

  test "the user can make erl the login REPL", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)

    vm = QEMU.boot_to_iex(ctx, disk: disk)
    {out, vm} = QEMU.iex(vm, ~s|Elixos.User.put("/priv/user.exs", :repl, :erl)|)
    assert out =~ ":ok"
    vm = QEMU.send_line(vm, "Elixos.reboot()")
    {0, _} = QEMU.expect_exit(vm)

    vm = QEMU.boot(ctx, disk: disk)
    {_, vm} = QEMU.expect(vm, @erl_prompt, 180_000)
    vm = QEMU.send_line(vm, "erlang:system_info(otp_release).")
    {_, vm} = QEMU.expect(vm, ~r/"29"/)
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "Ctrl-G starts another REPL on the same VM, sharing its processes", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    {_, vm} = QEMU.iex(vm, "Agent.start(fn -> 42 end, name: :shared)")

    vm = QEMU.send_raw(vm, <<7, ?\r>>)
    {_, vm} = QEMU.expect(vm, ~r/-->/)
    vm = QEMU.send_line(vm, "s shell")
    {_, vm} = QEMU.expect(vm, ~r/-->/)
    vm = QEMU.send_line(vm, "c")
    {_, vm} = QEMU.expect(vm, @erl_prompt)

    vm = QEMU.send_line(vm, "'Elixir.Agent':get(shared, fun(X) -> X end).")
    {_, vm} = QEMU.expect(vm, ~r/(^|\n)42\n/)
    QEMU.stop(vm)
  end

  test "only installed REPLs are offered", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir))
    {out, vm} = QEMU.iex(vm, "Elixos.REPL.available()")
    assert out =~ "[:erl, :iex]"
    QEMU.stop(vm)
  end
end
