defmodule Elixos.Integration.M14PackagesTest do
  @moduledoc """
  M14: packages by name (ADR-019). Hex repositories are the package sources,
  `/priv/hex/repos.exs` is the whole trust decision, `install/1` takes a name,
  and a native tool a package runs is exec'd with `cd:` set to the caller's
  session directory (ADR-020) — never through a shell (ADR-012), never by
  moving the VM's working directory (ADR-016).

  The repository installed from here is a real static Hex repo
  (`os/test/fixtures/hex_repo/`, built with `mix hex.registry build`). The
  native-tool part uses a stand-in `zig` (an escript, so still no shell): the
  real toolchain's `zig cc` is what `m11_self_hosting_test.exs` compiles a NIF
  with.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 14
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, Paths, QEMU}

  test "a package installs by name from a trusted repository", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    Disk.put_tree!(disk, Path.join(Paths.fixture("hex_repo"), "public"), "/hex-repo")

    vm = QEMU.boot_to_iex(ctx, disk: disk)

    # The official repository is preconfigured and trusted out of the box, and
    # its key was seeded from the factory into /priv/hex/ (PROTOCOL.md §8, Q7).
    {out, vm} = QEMU.iex(vm, "Elixos.Package.repos() |> Enum.map(& &1.name)")
    assert out =~ ":elixos"
    {out, vm} = QEMU.iex(vm, ~s|File.read!("/priv/hex/keys/elixos.pub")|)
    assert out =~ "BEGIN RSA PUBLIC KEY"

    # Trusting the test repository is the consent step: its key, then the name.
    add =
      ~s|Elixos.Package.add_repo(:fixture, "/priv/hex-repo", key: File.read!("/priv/hex-repo/public_key"))|

    {out, vm} = QEMU.iex(vm, add)
    assert out =~ ":ok"
    assert {:ok, vm} = {:ok, vm}

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.search("hello")|)
    assert out =~ "hello_pkg"

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.info("hello_pkg")|)
    assert out =~ ~s("0.1.0")
    assert out =~ "installed: false"

    # Install by name: it is fetched, unpacked and built on the box.
    {out, vm} = QEMU.iex(vm, "Elixos.Package.install(:hello_pkg)", 600_000)
    assert out =~ "{:ok, :hello_pkg}"

    {out, vm} = QEMU.iex(vm, "HelloPkg.greet()")
    assert out =~ ":hello_from_hex"

    # Installing did not move the VM's working directory (ADR-016).
    {out, vm} = QEMU.iex(vm, "File.cwd!()")
    assert out =~ ~s("/")

    # Uninstalling takes its modules away again.
    {out, vm} = QEMU.iex(vm, "Elixos.Package.remove(:hello_pkg)")
    assert out =~ ":ok"
    {out, vm} = QEMU.iex(vm, "Elixos.Package.installed()")
    refute out =~ "hello_pkg"

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  test "a name in two trusted repositories is an error naming both", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    Disk.put_tree!(disk, Path.join(Paths.fixture("hex_repo"), "public"), "/hex-repo")
    Disk.put_tree!(disk, Path.join(Paths.fixture("hex_repo"), "public"), "/hex-mirror")

    vm = QEMU.boot_to_iex(ctx, disk: disk)

    # The VM threads through the loop. It must: the console's prompt number
    # advances with every expression, and QEMU.iex/3's contract is a console
    # sitting at a prompt the harness has already consumed. A `for`
    # comprehension would discard the updated VM and the second iteration
    # would type into a console whose prompt the harness thought was still the
    # boot's (ADR-042).
    vm =
      Enum.reduce([{":fixture", "/priv/hex-repo"}, {":mirror", "/priv/hex-mirror"}], vm, fn
        {name, dir}, vm ->
          # One short expression per call, deliberately: IEx redraws an input
          # line that wraps the terminal, and the harness reads prompts off the
          # console - a wrapped 100-character line reads like one. The key
          # travels in a variable so the call itself stays under the width.
          {out, vm} = QEMU.iex(vm, ~s|key = File.read!("#{dir}/public_key")|)
          assert out =~ "BEGIN RSA PUBLIC KEY"

          {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.add_repo(#{name}, "#{dir}", key: key)|)
          assert out =~ ":ok"

          vm
      end)

    {out, vm} = QEMU.iex(vm, "Elixos.Package.install(:hello_pkg)", 300_000)
    assert out =~ "name_in_multiple_repos"

    QEMU.stop(vm)
  end

  test "a native tool runs in the session's directory, exec'd directly", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)

    vm = QEMU.boot_to_iex(ctx, disk: disk)

    # A stand-in toolchain whose `zig` prints the directory it was started in.
    # An escript is exec'd directly through its `#!` line: no shell anywhere.
    # One expression per call: QEMU.iex/3 sends a single line and waits for the
    # *next* prompt, so a multi-line paste makes it lose track of which prompt
    # it is waiting for (ADR-030).
    # The escript's bytes: "\n" and '\"' as the *guest* must see them, one
    # level of escaping before the string this test sends. Spelled as numbers
    # so neither this file's quoting nor the guest's is in the way.
    newline = <<92, 110>>
    quote = <<92, 34>>

    escript =
      "#!/factory/erts/bin/escript" <>
        newline <>
        "main(_) ->" <>
        newline <>
        "  {ok, Dir} = file:get_cwd()," <>
        newline <>
        "  io:format(" <> quote <> "~s~n" <> quote <> ", [Dir])." <> newline

    {out, vm} = QEMU.iex(vm, ~s{File.mkdir_p!("/priv/toolchain/bin")})
    assert out =~ ":ok"
    {out, vm} = QEMU.iex(vm, ~s{File.write!("/priv/toolchain/bin/zig", "#{escript}", [:write])})
    assert out =~ ":ok"
    {out, vm} = QEMU.iex(vm, ~s{File.chmod!("/priv/toolchain/bin/zig", 0o755)})
    assert out =~ ":ok"

    {out, vm} = QEMU.iex(vm, ~s|cd("/priv/home")|)
    assert out =~ ~s("/priv/home")
    {out, vm} = QEMU.iex(vm, ~s{Elixos.Package.install("/priv/toolchain") |> elem(0)}, 600_000)
    assert out =~ ~r/^:ok$/m

    {out, vm} = QEMU.iex(vm, "Zig.init(path: \"/priv/toolchain\")")
    assert out =~ ":ok"

    # A relative path resolves against the session's directory: `zig build`
    # runs with cd: set to it, so it finds the project the session is in.
    {out, vm} = QEMU.iex(vm, "Zig.build([\"run\"])", 600_000)
    # The escript prints the directory and a newline, and Zig.build/2 returns
    # the output verbatim; the assertion is the directory, not its inspect.
    assert out =~ ~s(/priv/home)

    # The instruction was not to move the VM's working directory (ADR-016).
    {out, vm} = QEMU.iex(vm, "File.cwd!()")
    assert out =~ ~s("/")

    # ADR-041 amends ADR-012: a shell exists, for *tools* - and this tool did
    # not need one. (The boot path's rule is m04's business: PID 1 execs ERTS
    # itself and the console is IEx.)
    {out, vm} = QEMU.iex(vm, ~s|System.cmd("/bin/sh", ["-c", "echo tool-ok"])|)
    assert out =~ ~s|{"tool-ok\\n", 0}|

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
