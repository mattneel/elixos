defmodule Elixos.Package.NativeContractTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :tmp_dir

  alias Elixos.Image
  alias Elixos.Package
  alias Elixos.Package.Spec

  setup %{tmp_dir: tmp_dir} do
    previous = Application.fetch_env(:elixos, :priv_dir)
    Application.put_env(:elixos, :priv_dir, Path.join(tmp_dir, "priv"))
    {:ok, image} = Image.open(Path.join(tmp_dir, "image"))
    Process.register(image, Image)

    on_exit(fn ->
      if Process.alive?(image), do: Image.close(image)

      case previous do
        {:ok, value} -> Application.put_env(:elixos, :priv_dir, value)
        :error -> Application.delete_env(:elixos, :priv_dir)
      end
    end)

    %{image: image}
  end

  test "metadata selects the exact target and environment without changing OS globals", %{
    tmp_dir: tmp_dir
  } do
    root =
      project(tmp_dir, """
      if Mix.target() == :elixos and Mix.env() == :prod do
        [app: :native_consumer, version: "2.3.4", deps: [
          {:elixos, "~> 0.1", targets: :elixos},
          {:shared_dep, "~> 2.0", only: [:prod], targets: [:elixos]},
          {:path_dep, path: "../path_dep"},
          {:dev_only, "~> 9.0", only: :dev},
          {:host_only, "~> 9.0", targets: :host}
        ], elixos: [boot: :manual, persist: ["state"]]]
      else
        [app: :wrong_host_branch, version: "9.0.0", elixos: [boot: :auto]]
      end
      """)

    before = {Mix.Project.get(), Mix.env(), Mix.target(), File.cwd!(), System.get_env()}
    test = self()
    watcher = spawn_link(fn -> watch_globals(test, File.cwd!(), System.get_env(), 0) end)

    try do
      for _ <- 1..3 do
        assert {:ok, %{app: :native_consumer, version: "2.3.4", deps: deps, spec: spec}} =
                 Spec.read_project(root)

        assert deps == %{elixos: "~> 0.1", shared_dep: "~> 2.0", path_dep: ">= 0.0.0"}
        assert spec == %Spec{boot: :manual, persist: ["state"]}
      end

      assert {Mix.Project.get(), Mix.env(), Mix.target(), File.cwd!(), System.get_env()} == before
    after
      send(watcher, :stop)
    end

    assert_receive {:global_changes, 0}, 1_000
    refute :code.is_loaded(Elixos.NativeContractFixture.MixProject)
  end

  test "failed project evaluation restores Mix state and unloads its definitions", %{
    tmp_dir: tmp_dir
  } do
    root = Path.join(tmp_dir, "broken")
    File.mkdir_p!(root)

    File.write!(Path.join(root, "mix.exs"), """
    defmodule Elixos.NativeContractFixture.BeforeFailure do
      def value, do: :defined
    end
    raise "project evaluation failed"
    """)

    before = {Mix.Project.get(), Mix.env(), Mix.target()}

    assert {:error, %RuntimeError{message: "project evaluation failed"}} = Spec.read_project(root)
    assert {Mix.Project.get(), Mix.env(), Mix.target()} == before
    refute :code.is_loaded(Elixos.NativeContractFixture.BeforeFailure)
  end

  test "concurrent project readers retain their own metadata and the caller stack", %{
    tmp_dir: tmp_dir
  } do
    roots =
      for index <- 1..4 do
        app = "concurrent_consumer_#{index}"
        root = Path.join(tmp_dir, app)
        File.mkdir_p!(root)

        File.write!(Path.join(root, "mix.exs"), """
        defmodule Elixos.NativeContractFixture.Project#{index} do
          use Mix.Project
          def project do
            Process.sleep(10)
            [app: :#{app}, version: "1.0.#{index}"]
          end
        end
        """)

        {root, String.to_atom(app), "1.0.#{index}"}
      end

    before = {Mix.Project.get(), Mix.env(), Mix.target()}
    tasks = for {root, _app, _version} <- roots, do: Task.async(fn -> Spec.read_project(root) end)

    for {task, {_root, app, version}} <- Enum.zip(tasks, roots) do
      assert {:ok, %{app: ^app, version: ^version}} = Task.await(task)
    end

    assert {Mix.Project.get(), Mix.env(), Mix.target()} == before
  end

  test "incompatible source refuses before build or installed-tree effects", %{
    tmp_dir: tmp_dir,
    image: image
  } do
    root =
      project(
        tmp_dir,
        "[app: :native_consumer, version: \"1.0.0\", elixos: [min_os: \">= 999.0.0\"]]"
      )

    installed = Package.installed_dir(:native_consumer)
    File.mkdir_p!(installed)
    File.write!(Path.join(installed, "keep"), "installed version")

    assert {:error, {:incompatible_os, ">= 999.0.0", _}} = Package.install(root)
    assert File.read!(Path.join(installed, "keep")) == "installed version"
    assert Image.apps(image) == %{}
    refute File.exists?(Path.join(root, "_build"))
    refute File.exists?(Package.data_dir(:native_consumer))
  end

  test "source cannot bundle the OS even when it declares no dependencies", %{
    tmp_dir: tmp_dir,
    image: image
  } do
    root = project(tmp_dir, "[app: :elixos, version: \"0.1.0\"]")
    assert Package.install(root) == {:error, {:conflicts, [{:bundled_os, :elixos}]}}
    assert Image.apps(image) == %{}
    refute File.exists?(Path.join(root, "_build"))
  end

  test "an OS dependency requirement is checked before any alternate source could be built", %{
    tmp_dir: tmp_dir,
    image: image
  } do
    root =
      project(
        tmp_dir,
        "[app: :native_consumer, version: \"1.0.0\", deps: [{:elixos, \">= 999.0.0\", path: \"/alternate/os\"}]]"
      )

    version = Application.spec(:elixos, :vsn) |> to_string()

    assert Package.install(root) ==
             {:error, {:conflicts, [{:os_version, :native_consumer, ">= 999.0.0", version}]}}

    assert Image.apps(image) == %{}
    refute File.exists?(Path.join(root, "_build"))
    refute File.exists?(Package.installed_dir(:elixos))
  end

  test "source dependency conflicts and reverse-dependency conflicts reject before compilation",
       %{tmp_dir: tmp_dir, image: image} do
    :ok = Image.record_app(image, :shared_dep, "2.0.0", %Spec{}, %{}, [])
    :ok = Image.record_app(image, :existing_client, "1.0.0", %Spec{}, %{shared_dep: "~> 2.0"}, [])

    root =
      project(
        tmp_dir,
        "[app: :native_consumer, version: \"1.0.0\", deps: [{:shared_dep, \"~> 1.0\"}]]"
      )

    assert Package.install(root) ==
             {:error,
              {:conflicts, [{:unsatisfied, :native_consumer, :shared_dep, "~> 1.0", "2.0.0"}]}}

    refute File.exists?(Path.join(root, "_build"))

    File.write!(
      Path.join(root, "mix.exs"),
      project_source("[app: :shared_dep, version: \"3.0.0\"]")
    )

    assert Package.install(root) ==
             {:error,
              {:conflicts, [{:unsatisfied, :existing_client, :shared_dep, "~> 2.0", "3.0.0"}]}}

    refute File.exists?(Path.join(root, "_build"))
    assert Image.apps(image) == %{shared_dep: "2.0.0", existing_client: "1.0.0"}
  end

  test "artifact identity comes from the declared app and its exact application resource", %{
    tmp_dir: tmp_dir
  } do
    root = Path.join(tmp_dir, "source")
    ebin = Path.join([root, "_build", "elixos_prod", "lib", "native_consumer", "ebin"])
    decoy = Path.join([root, "_build", "elixos_prod", "lib", "aaa_decoy-8.0.0", "ebin"])
    File.mkdir_p!(ebin)
    File.mkdir_p!(decoy)
    app_file(ebin, :native_consumer, "2.3.4-rc.7+native")
    app_file(decoy, :aaa_decoy, "8.0.0")

    assert Package.build_output(root, :native_consumer) ==
             {:ok, :native_consumer, "2.3.4-rc.7+native", ebin}

    assert {:error, {:no_build_output, :missing_consumer, _}} =
             Package.build_output(root, :missing_consumer)

    app_file(ebin, :wrong_app, "2.3.4", "native_consumer")

    assert {:error, {:invalid_build_output, :native_consumer, _, _}} =
             Package.build_output(root, :native_consumer)

    app_file(ebin, :native_consumer, "not-a-version")

    assert {:error, {:invalid_build_output, :native_consumer, _, _}} =
             Package.build_output(root, :native_consumer)
  end

  defp project(tmp_dir, body) do
    root = Path.join(tmp_dir, "consumer")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "mix.exs"), project_source(body))
    root
  end

  defp project_source(body) do
    """
    defmodule Elixos.NativeContractFixture.MixProject do
      use Mix.Project
      def project do
        #{body}
      end
    end
    """
  end

  defp app_file(ebin, app, version, filename \\ nil) do
    resource =
      {:application, app, [vsn: String.to_charlist(version), modules: [], applications: []]}

    File.write!(Path.join(ebin, "#{filename || app}.app"), :io_lib.format(~c"~tp.~n", [resource]))
  end

  defp watch_globals(test, cwd, env, changes) do
    receive do
      :stop -> send(test, {:global_changes, changes})
    after
      0 ->
        changed = File.cwd!() != cwd or System.get_env() != env
        watch_globals(test, cwd, env, changes + if(changed, do: 1, else: 0))
    end
  end
end
