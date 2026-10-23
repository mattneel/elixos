defmodule Elixos.Integration.NativePackageContractTest do
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 27
  @moduletag timeout: 2_400_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "target-effective consumers retain data and restore only automatic services after cold boot",
       ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    auto = consumer(ctx.tmp_dir, :native_auto, NativeAuto, :auto)
    manual = consumer(ctx.tmp_dir, :native_manual, NativeManual, :manual)
    Disk.put_tree!(disk, auto, "/src/native_auto")
    Disk.put_tree!(disk, manual, "/src/native_manual")
    vm = QEMU.boot_to_iex(ctx, disk: disk, memory_mb: 2048)

    {_, vm} =
      QEMU.iex(
        vm,
        ":persistent_term.put(:native_install_globals, {File.cwd!(), System.get_env(), Mix.env(), Mix.target(), Mix.Project.get()})"
      )

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.install("/priv/src/native_auto")|, 600_000)
    assert out =~ "{:ok, :native_auto}"
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.install("/priv/src/native_manual")|, 600_000)
    assert out =~ "{:ok, :native_manual}"
    {out, vm} = QEMU.iex(vm, "{NativeAuto.Service.state(), NativeManual.Service.state()}")
    assert out =~ "{:elixos, :prod}"
    assert length(Regex.scan(~r/\{:elixos,\s*:prod\}/, out)) == 2
    assert out =~ "/priv/data/native_auto/state"
    assert out =~ "/priv/data/native_manual/state"

    {out, vm} =
      QEMU.iex(
        vm,
        "{Elixos.Package.installed_version(:native_auto), Enum.find(Elixos.Image.packages(Elixos.Image), &(&1.app == :native_auto)).deps}"
      )

    assert out =~ ~s|"1.2.3"|
    assert out =~ ~s|elixos: "~> 0.1"|

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|{File.exists?("/priv/src/native_auto/deps/elixos"), File.exists?("/priv/src/native_auto/_build/elixos_prod/lib/elixos"), File.exists?("/priv/src/native_manual/deps/elixos"), File.exists?("/priv/src/native_manual/_build/elixos_prod/lib/elixos") }|
      )

    assert out =~ "{false, false, false, false}"

    {_, vm} =
      QEMU.iex(
        vm,
        ~s|File.write!(Path.join(Elixos.Package.data_dir(:native_auto), "state/kept"), "consumer state")|
      )

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.install("/priv/src/native_auto")|, 600_000)
    assert out =~ "{:ok, :native_auto}"
    {_, vm} = QEMU.iex(vm, ~s|File.write!("/priv/src/native_auto/VERSION", "1.2.4")|)
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.install("/priv/src/native_auto")|, 600_000)
    assert out =~ "{:ok, :native_auto}"

    {out, vm} =
      QEMU.iex(
        vm,
        "{Elixos.Package.installed_version(:native_auto), File.read!(Path.join(Elixos.Package.data_dir(:native_auto), \"state/kept\")), :persistent_term.get(:native_install_globals) == {File.cwd!(), System.get_env(), Mix.env(), Mix.target(), Mix.Project.get()}}"
      )

    assert out =~ ~s|{"1.2.4", "consumer state", true}|

    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ ~r/\{:ok, \d+\}/
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk, memory_mb: 2048)

    {out, vm} =
      QEMU.iex(
        vm,
        "{NativeAuto.Service.state(), Process.whereis(NativeManual.Service), Application.fetch_env!(:native_manual, :where)}"
      )

    assert out =~ "{:elixos, :prod}"
    assert length(Regex.scan(~r/\{:elixos,\s*:prod\}/, out)) == 2
    assert out =~ "/priv/data/native_auto/state"
    assert out =~ "nil"

    {out, vm} =
      QEMU.iex(vm, "{:ok, _} = Elixos.Oban.status(); Keyword.keys(Oban.config().queues)", 120_000)

    assert out =~ ":native_auto_jobs"
    refute out =~ ":native_manual_jobs"

    {out, vm} =
      QEMU.iex(vm, ~s|File.read!(Path.join(Elixos.Package.data_dir(:native_auto), "state/kept"))|)

    assert out =~ ~s|"consumer state"|

    {out, vm} = QEMU.iex(vm, "Elixos.Package.remove(:native_auto)")
    assert out =~ ":ok"

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|{File.exists?(Elixos.Package.installed_dir(:native_auto)), File.read!(Path.join(Elixos.Package.data_dir(:native_auto), "state/kept"))}|
      )

    assert out =~ ~s|{false, "consumer state"}|
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Package.install("/priv/src/native_auto")|, 600_000)
    assert out =~ "{:ok, :native_auto}"

    {out, vm} =
      QEMU.iex(vm, ~s|File.read!(Path.join(Elixos.Package.data_dir(:native_auto), "state/kept"))|)

    assert out =~ ~s|"consumer state"|
    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end

  defp consumer(tmp_dir, app, module, boot) do
    root = Path.join(tmp_dir, Atom.to_string(app))
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "config"))
    File.write!(Path.join(root, "VERSION"), "1.2.3")

    dependency =
      if boot == :manual,
        do: ~s|{:elixos, "~> 0.1", path: "/must-not-build-another-os", targets: :elixos}|,
        else: ~s|{:elixos, "~> 0.1", targets: :elixos}|

    File.write!(Path.join(root, "mix.exs"), """
    defmodule #{inspect(module)}.MixProject do
      use Mix.Project
      def project do
        if Mix.target() == :elixos and Mix.env() == :prod do
          [app: :#{app}, version: File.read!(Path.join(__DIR__, "VERSION")),
           deps: [#{dependency}], elixos: os()]
        else
          [app: :#{app}_wrong_branch, version: "9.0.0", deps: []]
        end
      end
      def application, do: [extra_applications: [:logger], env: [where: :wrong_resource_default]]
      defp os do
        [services: [#{inspect(module)}.Service], persist: ["state"], boot: :#{boot},
         min_os: "~> 0.1", oban: [queues: [#{app}_jobs: 1]]]
      end
    end
    """)

    File.write!(Path.join(root, "config/config.exs"), """
    import Config
    config :#{app}, where: {config_target(), config_env()},
      state_dir: Path.join(Elixos.Package.data_dir(:#{app}), "state")
    """)

    File.write!(Path.join(root, "lib/service.ex"), """
    defmodule #{inspect(module)}.Service do
      use GenServer
      if List.keymember?(Application.started_applications(), :elixos, 0),
        do: raise("compilation started another OS application")
      unless Code.ensure_loaded?(Mix) and Code.ensure_loaded?(Elixos.Package) and
               Application.spec(:elixos, :vsn) != nil,
        do: raise("native compiler cannot see the real OS and Mix")

      def start_link(arg), do: GenServer.start_link(__MODULE__, arg, name: __MODULE__)
      def state, do: GenServer.call(__MODULE__, :state)
      def init(_) do
        state = Application.fetch_env!(:#{app}, :state_dir)
        if File.dir?(state),
          do: {:ok, {Application.fetch_env!(:#{app}, :where), state}},
          else: {:stop, :required_data_directory_missing}
      end
      def handle_call(:state, _from, state), do: {:reply, state, state}
    end
    """)

    # A different app's build tree must never supply this install's identity.
    File.mkdir_p!(Path.join([root, "_build", "elixos_prod", "lib", "aaa_decoy-8.0.0", "ebin"]))
    root
  end
end
