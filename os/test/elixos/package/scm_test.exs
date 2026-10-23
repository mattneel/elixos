defmodule Elixos.Package.SCMTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :tmp_dir

  alias Elixos.Package
  alias Elixos.Package.SCM

  setup %{tmp_dir: tmp_dir} do
    previous = Application.fetch_env(:elixos, :priv_dir)
    Application.put_env(:elixos, :priv_dir, Path.join(tmp_dir, "priv"))

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:elixos, :priv_dir, value)
        :error -> Application.delete_env(:elixos, :priv_dir)
      end
    end)
  end

  test "the OS always resolves to its actual application resource, never an alternate source" do
    root = Application.app_dir(:elixos)
    resource = Path.join(root, "ebin/elixos.app")
    version = Application.spec(:elixos, :vsn) |> to_string()
    before = {File.cwd!(), System.get_env(), Application.started_applications()}

    for source <- [
          [],
          [path: "/not/the/os"],
          [git: "https://invalid.example/another-os.git"],
          [github: "invalid/another-os"]
        ] do
      opts = SCM.accepts_options(:elixos, source ++ [requirement: "== #{version}"])
      assert opts[:dest] == root
      assert opts[:app] == resource
      assert opts[:compile] == false
      refute Keyword.has_key?(opts, :path)
      refute Keyword.has_key?(opts, :git)
      refute Keyword.has_key?(opts, :github)
      assert SCM.checked_out?(opts)
      assert SCM.checkout(opts) == :ok
    end

    assert {File.cwd!(), System.get_env(), Application.started_applications()} == before
    refute File.exists?(Package.installed_dir(:elixos))
  end

  test "an incompatible explicit OS requirement refuses rather than falling through to another SCM" do
    assert_raise Mix.Error, ~r/running Elixos.*does not satisfy/s, fn ->
      SCM.accepts_options(:elixos, requirement: ">= 999.0.0", path: "/alternate/os")
    end
  end

  test "Mix validates its real tuple requirement against the running OS .app", %{tmp_dir: tmp_dir} do
    version = Application.spec(:elixos, :vsn) |> to_string()
    matching = load_os_dependency(tmp_dir, "== #{version}")
    assert matching.scm == SCM
    assert matching.status == {:ok, version}
    assert matching.opts[:app] == Application.app_dir(:elixos, "ebin/elixos.app")
    assert matching.opts[:compile] == false

    incompatible = load_os_dependency(tmp_dir, ">= 999.0.0")
    assert incompatible.scm == SCM
    assert match?({:nomatchvsn, _}, incompatible.status)
    refute File.exists?(Path.join(tmp_dir, "_build"))
    refute File.exists?(Path.join(tmp_dir, "deps"))
  end

  test "ordinary dependencies still honor their explicit source and installed version requirements" do
    app = :scm_shared_dependency
    root = Package.installed_dir(app)
    File.mkdir_p!(Path.join(root, "ebin"))
    resource = {:application, app, [vsn: ~c"2.3.4", modules: [], applications: []]}
    File.write!(Path.join(root, "ebin/#{app}.app"), :io_lib.format(~c"~tp.~n", [resource]))

    for source <- [
          [path: "/explicit/dependency"],
          [git: "https://invalid.example/dependency.git"]
        ] do
      assert SCM.accepts_options(app, source) == nil
    end

    assert SCM.accepts_options(app, requirement: "~> 1.0") == nil
    assert SCM.accepts_options(app, requirement: "~> 2.0")[:dest] == root
  end

  defp load_os_dependency(tmp_dir, requirement) do
    path = Path.join(tmp_dir, "mix.exs")

    File.write!(path, """
    defmodule Elixos.SCMFixture.MixProject do
      use Mix.Project
      def project do
        [app: :os_scm_consumer, version: "1.0.0", build_path: #{inspect(Path.join(tmp_dir, "_build"))},
         deps_path: #{inspect(Path.join(tmp_dir, "deps"))},
         deps: [{:elixos, #{inspect(requirement)}, path: "/alternate/os"}]]
      end
    end
    """)

    registry = Mix.SCM.available()

    try do
      Mix.SCM.prepend(SCM)

      Mix.ProjectStack.on_clean_slate(fn ->
        Code.compile_file(path)
        [dependency] = Mix.Dep.Loader.children(false)
        Mix.Dep.Loader.load(dependency, nil, false)
      end)
    after
      Mix.State.put(:scm, registry)
      :code.purge(Elixos.SCMFixture.MixProject)
      :code.delete(Elixos.SCMFixture.MixProject)
      :code.purge(Elixos.SCMFixture.MixProject)
    end
  end
end
