defmodule ElixosSDK.PackageTest do
  use ExUnit.Case, async: true

  alias ElixosSDK.{Package, TestCommands}

  @moduletag :tmp_dir
  @moduletag milestone: 27

  test "requirements select the Elixos production target" do
    declarations = [
      {:elixos, "~> 0.1", targets: :elixos},
      {:shared, "~> 1.0"},
      {:target_only, "~> 2.0", targets: [:elixos, :other], only: [:dev, :prod]},
      {:host_only, path: "unavailable", targets: :host},
      {:test_only, path: "unavailable", only: :test}
    ]

    assert Package.dependencies(declarations) == Enum.take(declarations, 3)
  end

  test "the running OS must remain a required versioned Hex requirement" do
    for dependencies <- [
          [],
          [{:elixos, path: "../os"}],
          [{:elixos, "~> 0.1", path: "../os"}],
          [{:elixos, "~> 0.1", git: "https://example.invalid/os"}],
          [{:elixos, "~> 0.1", optional: true}],
          [{:elixos, "not a version requirement"}],
          [{:elixos, "~> 0.1", hex: :different_package}]
        ] do
      assert_raise Mix.Error, fn -> Package.require_os!(dependencies) end
    end
  end

  test "a fresh target command builds real Hex metadata without compiling or fetching", %{
    tmp_dir: directory
  } do
    project = copy_fixture(directory)
    tarball = Path.join(directory, "consumer.tar")
    {output, status} = TestCommands.mix(project, ["elixos.package", "--output", tarball])
    assert status == 0, output
    assert File.regular?(tarball)
    refute File.exists?(Path.join(project, "_build"))
    refute File.exists?(Path.join(project, "deps"))

    %{metadata: metadata, contents: contents} = unpack(tarball)
    requirements = metadata["requirements"]

    assert Map.keys(requirements) |> Enum.sort() == [
             "elixos",
             "elixos_demo_stats",
             "target_conditional"
           ]

    assert requirements["elixos"]["requirement"] == "~> 0.1"
    assert requirements["elixos"]["optional"] == false
    assert requirements["elixos_demo_stats"]["requirement"] == "~> 0.1"
    assert requirements["elixos_demo_stats"]["repository"] == "explicit_sample"
    assert requirements["target_conditional"]["requirement"] == "~> 0.2"

    files = Enum.map(contents, fn {name, _bytes} -> to_string(name) end)
    refute Enum.any?(files, &String.starts_with?(&1, ["deps/", "_build/"]))
    refute Enum.any?(files, &String.ends_with?(&1, [".beam", ".so", ".app"]))
  end

  test "a portable library packages source without an OS dependency", %{tmp_dir: directory} do
    project = copy_fixture(directory, "portable_package_subject")
    tarball = Path.join(directory, "portable.tar")
    {output, status} = TestCommands.mix(project, ["elixos.package", "--output", tarball])
    assert status == 0, output
    refute File.exists?(Path.join(project, "_build"))
    refute File.exists?(Path.join(project, "deps"))

    %{metadata: metadata, contents: contents} = unpack(tarball)
    assert metadata["requirements"] == %{}
    files = Enum.map(contents, fn {name, _bytes} -> to_string(name) end)
    assert "lib/portable_package_subject.ex" in files
    refute Enum.any?(files, &String.starts_with?(&1, ["deps/", "_build/"]))
    refute Enum.any?(files, &String.ends_with?(&1, [".beam", ".so", ".app"]))
  end

  test "even an empty native contract requires an OS dependency", %{tmp_dir: directory} do
    project = copy_fixture(directory, "native_package_without_os")
    tarball = Path.join(directory, "native.tar")
    {output, status} = TestCommands.mix(project, ["elixos.package", "--output", tarball])
    assert status != 0
    assert output =~ "requires a non-optional Hex dependency"
    refute File.exists?(tarball)
    refute File.exists?(Path.join(project, "_build"))
    refute File.exists?(Path.join(project, "deps"))
  end

  test "Hex unpack output option retains source and never compiles it", %{tmp_dir: directory} do
    project = copy_fixture(directory)
    destination = Path.join(directory, "unpacked")

    {output, status} =
      TestCommands.mix(project, ["elixos.package", "--unpack", "-o", destination])

    assert status == 0, output
    refute File.exists?(Path.join(project, "_build"))
  end

  test "host and test invocations fail before writing any package", %{tmp_dir: directory} do
    project = copy_fixture(directory)
    tarball = Path.join(directory, "wrong-target.tar")

    for environment <- [[MIX_TARGET: "host"], [MIX_ENV: "test"]] do
      {output, status} = TestCommands.mix(project, ["elixos.package", "-o", tarball], environment)
      assert status != 0
      assert output =~ "MIX_ENV=prod MIX_TARGET=elixos mix elixos.package"
      refute File.exists?(tarball)
    end
  end

  test "unsupported package options are not forwarded silently" do
    assert_raise OptionParser.ParseError, fn ->
      Mix.Tasks.Elixos.Package.run(["--cross-compile"])
    end

    assert_raise Mix.Error, fn -> Mix.Tasks.Elixos.Package.run(["some-project"]) end
  end

  defp copy_fixture(directory, fixture \\ "package_subject") do
    destination = Path.join(directory, "consumer")
    File.cp_r!(Path.join([__DIR__, "fixtures", fixture]), destination)
    destination
  end

  defp unpack(tarball) do
    module = Module.concat([Hex, Tar])

    unless Code.ensure_loaded?(module) do
      raise "SDK packaging tests require Hex 2.5 or later: mix local.hex --force"
    end

    apply(module, :unpack!, [tarball, :memory])
  end
end
