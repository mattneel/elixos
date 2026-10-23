defmodule ElixosSDK.GeneratorTest do
  use ExUnit.Case, async: true

  alias ElixosSDK.{Generator, TestCommands}

  @moduletag :tmp_dir
  @moduletag milestone: 27

  test "generated external app runs its actual host tests without the OS", %{tmp_dir: directory} do
    path = Path.join(directory, "field_counter")
    assert %{app: "field_counter", module: "FieldCounter"} = Generator.generate(path)

    {output, status} = TestCommands.mix(path, ["test"], MIX_ENV: "test", MIX_TARGET: "host")
    assert status == 0, output
  end

  test "explicit app, nested module and manual boot generate independent names", %{
    tmp_dir: directory
  } do
    path = Path.join(directory, "arbitrary-directory")
    Generator.generate(path, app: "meter", module: "Field.Meter", boot: "manual")

    {output, status} = TestCommands.mix(path, ["test"], MIX_ENV: "test", MIX_TARGET: "host")
    assert status == 0, output

    {output, status} =
      TestCommands.mix(
        path,
        [
          "run",
          "-e",
          "IO.inspect({Field.Meter.value(), Field.Meter.increment(3), Field.Meter.value()})"
        ],
        MIX_ENV: "test",
        MIX_TARGET: "host"
      )

    assert status == 0, output
    assert output =~ "{0, {:ok, 3}, 3}"
  end

  test "invalid names and reserved OS namespace cannot emit projects", %{tmp_dir: directory} do
    for options <- [
          [app: "invalid-name"],
          [app: "elixos"],
          [app: "mix"],
          [app: "valid", module: "Elixos.Counter"],
          [app: "valid", module: "lowercase"],
          [app: "valid", boot: "sometimes"]
        ] do
      path = Path.join(directory, "rejected")
      assert_raise Mix.Error, fn -> Generator.generate(path, options) end
      refute File.exists?(path)
    end
  end

  test "existing files and directories are never overwritten", %{tmp_dir: directory} do
    path = Path.join(directory, "existing")
    File.write!(path, "keep me")
    assert_raise Mix.Error, fn -> Generator.generate(path) end
    assert File.read!(path) == "keep me"

    File.rm!(path)
    File.mkdir!(path)
    File.write!(Path.join(path, "keep"), "also keep me")
    assert_raise Mix.Error, fn -> Generator.generate(path) end
    assert File.read!(Path.join(path, "keep")) == "also keep me"
  end

  test "new task rejects missing or surplus paths and unknown options" do
    assert_raise Mix.Error, fn -> Mix.Tasks.Elixos.New.run([]) end
    assert_raise Mix.Error, fn -> Mix.Tasks.Elixos.New.run(["one", "two"]) end

    assert_raise OptionParser.ParseError, fn ->
      Mix.Tasks.Elixos.New.run(["one", "--cross-sdk"])
    end
  end
end
