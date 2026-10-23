defmodule Elixos.Integration.PackageAssetsTest do
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 27
  @moduletag timeout: 600_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "installed assets survive removal of their source and a cold boot", ctx do
    source = Path.join(ctx.tmp_dir, "native_assets")
    File.mkdir_p!(Path.join(source, "lib"))
    File.mkdir_p!(Path.join(source, "priv"))
    File.write!(Path.join(source, "priv/asset"), "standalone deployed asset")

    File.write!(Path.join(source, "mix.exs"), """
    defmodule NativeAssets.MixProject do
      use Mix.Project
      def project do
        [app: :native_assets, version: "1.0.0", elixir: "~> 1.20",
         deps: [{:elixos, "~> 0.1", targets: :elixos}], elixos: [boot: :auto]]
      end
      def application, do: [extra_applications: [:logger]]
    end
    """)

    File.write!(Path.join(source, "lib/native_assets.ex"), """
    defmodule NativeAssets do
      def read, do: File.read(Application.app_dir(:native_assets, "priv/asset"))
    end
    """)

    disk = Disk.fresh!(ctx.tmp_dir)
    Disk.put_tree!(disk, source, "/src/native_assets")
    vm = QEMU.boot_to_iex(ctx, disk: disk, memory_mb: 2048)

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.install("/priv/src/native_assets")|, 120_000)
    assert out =~ "{:ok, :native_assets}"

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|:ok = File.rename("/priv/src/native_assets", "/priv/src/native_assets-removed"); NativeAssets.read()|
      )

    assert out =~ ~s|{:ok, "standalone deployed asset"}|
    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ ~r/\{:ok, \d+\}/
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk, memory_mb: 2048)
    {out, vm} = QEMU.iex(vm, "NativeAssets.read()")
    assert out =~ ~s|{:ok, "standalone deployed asset"}|
    QEMU.stop(vm)
  end
end
