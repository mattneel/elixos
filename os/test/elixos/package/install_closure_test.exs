defmodule Elixos.Package.InstallClosureTest do
  @moduledoc """
  Installing by name pulls the dependency closure (ADR-015, M15): the same one
  version per package rule the resolver has tested since M10, now applied to
  what a repository says a release requires. Dependencies come before what
  needs them, and a name in two trusted repositories is still an error.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 15
  @moduletag :tmp_dir

  alias Elixos.Package
  alias Elixos.Package.Hex

  setup %{tmp_dir: tmp_dir} do
    hex_dir = Path.join(tmp_dir, "hex")
    previous = Application.get_env(:elixos, :hex_dir)
    Application.put_env(:elixos, :hex_dir, hex_dir)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:elixos, :hex_dir, previous),
        else: Application.delete_env(:elixos, :hex_dir)
    end)

    fixture = Elixos.Test.Paths.fixture("hex_repo")
    key = File.read!(Path.join(fixture, "public/public_key"))
    :ok = Package.add_repo(:fixture, Path.join(fixture, "public"), key: key)

    %{fixture: fixture, key: key, tmp_dir: tmp_dir}
  end

  test "a name with a dependency closes over it, dependencies first" do
    assert {:ok, closure} = Hex.closure("hello_app")

    assert Enum.map(closure, &{&1.name, &1.version}) ==
             [{"hello_dep", "0.1.0"}, {"hello_app", "0.1.0"}]

    assert hd(closure).deps == %{}
    assert List.last(closure).deps == %{"hello_dep" => "~> 0.1"}
    assert Enum.all?(closure, &(&1.repo.name == :fixture))
  end

  test "a name without dependencies is a closure of one" do
    assert {:ok, [%{name: "hello_pkg", version: "0.1.0", deps: %{}}]} = Hex.closure("hello_pkg")
  end

  test "a name that is not in any trusted repository has no closure" do
    assert Hex.closure("no_such_package") == {:error, :no_such_package}
  end

  test "a name offered by two trusted repositories is still an error", %{
    fixture: fixture,
    key: key,
    tmp_dir: tmp_dir
  } do
    mirror = Path.join(tmp_dir, "mirror")
    File.cp_r!(Path.join(fixture, "public"), mirror)
    :ok = Package.add_repo(:mirror, mirror, key: key)

    assert {:error, {:name_in_multiple_repos, "hello_app", repo_a, repo_b}} =
             Hex.closure("hello_app")

    assert Enum.sort([repo_a, repo_b]) == [:fixture, :mirror]
  end

  test "the closure is what the resolver plans over (ADR-015)" do
    assert {:ok, closure} = Hex.closure("hello_app")

    incoming =
      for entry <- closure do
        %{
          app: String.to_atom(entry.name),
          version: entry.version,
          deps:
            Map.new(entry.deps, fn {name, requirement} -> {String.to_atom(name), requirement} end)
        }
      end

    assert Elixos.Package.Resolver.plan([], incoming, "0.1.0") ==
             {:ok, %{install: [:hello_app, :hello_dep], upgrade: [], unchanged: []}}

    # A version the requirement does not allow is the resolver's refusal:
    # `~> 0.1` stops below 1.0.0.
    app = Enum.find(incoming, &(&1.app == :hello_app))
    dep = Enum.find(incoming, &(&1.app == :hello_dep))
    broken = [app, %{dep | version: "1.0.0"}]

    assert Elixos.Package.Resolver.plan([], broken, "0.1.0") ==
             {:error, [{:unsatisfied, :hello_app, :hello_dep, "~> 0.1", "1.0.0"}]}
  end
end
