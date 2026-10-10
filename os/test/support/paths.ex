defmodule Elixos.Test.Paths do
  @moduledoc "Locations of repo files and build artifacts, for tests."

  @repo_root Path.expand("../../..", __DIR__)

  def repo_root, do: @repo_root

  def spec(name), do: Path.join([@repo_root, "spec", name])

  def fixture(name), do: Path.join([@repo_root, "os", "test", "fixtures", name])

  @doc "A build artifact; `ELIXOS_BUILD` overrides the build directory."
  def build(name) do
    dir = System.get_env("ELIXOS_BUILD") || Path.join(@repo_root, "build")
    Path.join(dir, name)
  end
end
