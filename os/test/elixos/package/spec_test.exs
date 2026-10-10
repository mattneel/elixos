defmodule Elixos.Package.SpecTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 10

  alias Elixos.Package.Spec

  test "a project without an elixos: key installs as a plain library" do
    assert Spec.from_project(app: :plain, version: "1.0.0") == {:ok, :none}
  end

  test "an empty elixos: key means the defaults" do
    assert Spec.from_project(app: :x, elixos: []) == {:ok, %Spec{}}
    assert %Spec{services: [], persist: [], min_os: nil, boot: :auto} = %Spec{}
  end

  test "a full spec" do
    elixos = [
      services: [MyApp.Worker, {MyApp.Server, port: 4000}],
      persist: ["db", "uploads/images"],
      min_os: "~> 0.1",
      boot: :manual
    ]

    assert Spec.from_project(app: :my_app, elixos: elixos) ==
             {:ok,
              %Spec{
                services: [MyApp.Worker, {MyApp.Server, port: 4000}],
                persist: ["db", "uploads/images"],
                min_os: "~> 0.1",
                boot: :manual
              }}
  end

  test "each invalid value is reported against its key" do
    cases = [
      {[services: "MyApp.Worker"], [services: :invalid]},
      {[services: [MyApp.Worker, 42]], [services: :invalid]},
      {[persist: "db"], [persist: :invalid]},
      {[persist: ["/etc"]], [persist: :absolute_path]},
      {[persist: ["data/../../etc"]], [persist: :parent_path]},
      {[min_os: "soon"], [min_os: :invalid_requirement]},
      {[boot: :sometimes], [boot: :invalid]},
      {[colour: :amber], [colour: :unknown_key]}
    ]

    for {elixos, errors} <- cases do
      assert Spec.from_project(app: :x, elixos: elixos) == {:error, errors},
             "elixos: #{inspect(elixos)}"
    end
  end

  test "all problems are collected, sorted by key" do
    elixos = [zzz: 1, boot: :never, persist: ["/abs"], services: :nope]

    assert Spec.from_project(app: :x, elixos: elixos) ==
             {:error,
              [boot: :invalid, persist: :absolute_path, services: :invalid, zzz: :unknown_key]}
  end

  test "the key must hold a keyword list" do
    assert Spec.from_project(app: :x, elixos: %{boot: :auto}) ==
             {:error, [elixos: :not_a_keyword_list]}

    assert Spec.from_project(app: :x, elixos: true) == {:error, [elixos: :not_a_keyword_list]}
  end

  test "min_os is checked against the running OS" do
    {:ok, spec} = Spec.from_project(app: :x, elixos: [min_os: "~> 0.1"])
    assert Spec.check_os(spec, "0.1.7") == :ok
    # "~> 0.1" means >= 0.1.0 and < 1.0.0 (Elixir's Version semantics).
    assert Spec.check_os(spec, "0.9.0") == :ok
    assert Spec.check_os(spec, "1.0.0") == {:error, {:incompatible_os, "~> 0.1", "1.0.0"}}
    assert Spec.check_os(%Spec{}, "9.9.9") == :ok
  end

  test "reads the elixos: key from a real Mix project without compiling it" do
    dir = Elixos.Test.Paths.fixture("sample_app")

    assert Spec.read_project(dir) ==
             {:ok,
              %Spec{
                services: [SampleApp.Worker],
                persist: ["data"],
                min_os: "~> 0.1",
                boot: :auto
              }}
  end

  # ADR-016: on Elixos every program shares one VM, so the VM's working
  # directory is global state. Mix.Project.in_project/4 cd's the whole VM.
  test "read_project/1 never changes the VM's working directory, even briefly" do
    cwd = File.cwd!()
    test = self()
    watcher = spawn_link(fn -> watch_cwd(cwd, test, 0) end)

    for _ <- 1..5, do: {:ok, %Spec{}} = Spec.read_project(Elixos.Test.Paths.fixture("sample_app"))

    send(watcher, :stop)
    assert_receive {:cwd_changes, 0}, 1_000
  end

  test "read_project/1 leaves Mix's project stack as it found it" do
    before = Mix.Project.get()
    {:ok, _} = Spec.read_project(Elixos.Test.Paths.fixture("sample_app"))
    assert Mix.Project.get() == before
  end

  defp watch_cwd(cwd, test, changes) do
    receive do
      :stop -> send(test, {:cwd_changes, changes})
    after
      0 -> watch_cwd(cwd, test, if(File.cwd!() == cwd, do: changes, else: changes + 1))
    end
  end
end
