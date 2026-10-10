defmodule Elixos.MetaTest do
  # Guards the test suite's own conventions (docs/TESTING.md).
  use ExUnit.Case, async: true

  @moduletag milestone: 0

  @test_root Path.expand(".", __DIR__)

  defp test_files do
    @test_root
    |> Path.join("**/*_test.exs")
    |> Path.wildcard()
    |> Enum.reject(&String.contains?(&1, "/fixtures/"))
  end

  test "every test module declares @moduletag milestone: N" do
    missing = Enum.reject(test_files(), &(File.read!(&1) =~ ~r/@moduletag\s+milestone:\s*\d+/))

    assert missing == [],
           "add `@moduletag milestone: N` (see docs/ROADMAP.md) to:\n" <> Enum.join(missing, "\n")
  end

  test "every QEMU test is tagged :qemu and lives in test/integration" do
    for file <- test_files(), file != __ENV__.file, File.read!(file) =~ "Elixos.Test.QEMU" do
      assert String.contains?(file, "/test/integration/"),
             "#{file} boots QEMU outside test/integration"

      assert File.read!(file) =~ "@moduletag :qemu", "#{file} boots QEMU but is not tagged :qemu"
    end
  end
end
