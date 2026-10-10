defmodule Elixos.Integration.M20SystemDepsTest do
  @moduledoc """
  M20: an installed package is a Mix dependency. Installing hello_app by name
  installs its closure first (`hello_dep`, M15), and the build that follows
  resolves `hello_dep` from the installed tree: the box has no network, so a
  fetch could not have happened, and the code that ends up loaded is the
  installed copy - one version per package (M10), not two.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 20
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, Paths, QEMU}

  test "a package with a dependency builds against the installed dependency", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    Disk.put_tree!(disk, Path.join(Paths.fixture("hex_repo"), "public"), "/hex-repo")

    vm = QEMU.boot_to_iex(ctx, disk: disk)

    add =
      ~s|Elixos.Package.add_repo(:fixture, "/priv/hex-repo", key: File.read!("/priv/hex-repo/public_key"))|

    {out, vm} = QEMU.iex(vm, add)
    assert out =~ ":ok"

    # The closure installs first: hello_dep is a system package before
    # hello_app is built.
    {out, vm} = QEMU.iex(vm, "Elixos.Package.install(:hello_app)", 600_000)
    assert out =~ "{:ok, :hello_app}"

    {out, vm} = QEMU.iex(vm, "Elixos.Package.installed() |> Map.keys() |> Enum.sort()")
    assert out =~ ~s([:hello_app, :hello_dep])

    # The build resolved hello_dep where it lives (the box has no network).
    {out, vm} = QEMU.iex(vm, "HelloApp.greet()")
    assert out =~ "{:hello_app, :from_hello_dep}"

    # And the running module is that copy, not a second one.
    {out, vm} = QEMU.iex(vm, ":code.which(HelloDep) |> List.to_string()")
    assert out =~ ~r{/priv/apps/hello_dep/}

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
