defmodule Elixos.Package.InstallByNameTest do
  @moduledoc """
  Resolving and unpacking a package by name (ADR-019, M14). A name is resolved
  among the *trusted* repositories only, and a name offered by two of them is
  an error naming both.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 14
  @moduletag :tmp_dir

  alias Elixos.Package
  alias Elixos.Package.Hex

  setup %{tmp_dir: tmp_dir} do
    hex_dir = Path.join(tmp_dir, "hex")
    previous = Application.get_env(:elixos, :hex_dir)
    Application.put_env(:elixos, :hex_dir, hex_dir)

    on_exit(fn ->
      if previous, do: Application.put_env(:elixos, :hex_dir, previous),
        else: Application.delete_env(:elixos, :hex_dir)
    end)

    fixture = Elixos.Test.Paths.fixture("hex_repo")
    key = File.read!(Path.join(fixture, "public/public_key"))
    :ok = Package.add_repo(:fixture, Path.join(fixture, "public"), key: key)

    %{fixture: fixture, key: key, tmp_dir: tmp_dir}
  end

  test "finds a package in a trusted repository", %{fixture: fixture} do
    assert {:ok, %{repo: %{name: :fixture}, name: "hello_pkg", version: "0.1.0"}} =
             Hex.resolve("hello_pkg")

    assert {:ok, names} = Hex.names(Package.repos() |> hd(), "hello")
    assert "hello_pkg" in names
    assert Hex.resolve("no_such_package") == {:error, :no_such_package}
    assert Path.expand(Path.join(fixture, "public")) == Package.repos() |> hd() |> Map.fetch!(:url)
  end

  test "a package name in two repositories is an error naming both", %{fixture: fixture, key: key, tmp_dir: tmp_dir} do
    mirror = Path.join(tmp_dir, "mirror")
    File.cp_r!(Path.join(fixture, "public"), mirror)
    :ok = Package.add_repo(:mirror, mirror, key: key)

    assert {:error, {:name_in_multiple_repos, "hello_pkg", repo_a, repo_b}} =
             Hex.resolve("hello_pkg")

    assert Enum.sort([repo_a, repo_b]) == [:fixture, :mirror]
  end

  test "unpacking gives the package's own files", %{tmp_dir: tmp_dir} do
    repo = Package.repos() |> hd()
    dest = Path.join(tmp_dir, "hello_pkg")

    assert {:ok, ^dest} = Hex.unpack(repo, "hello_pkg", "0.1.0", dest)
    assert File.read!(Path.join(dest, "mix.exs")) =~ "HelloPkg.MixProject"
    assert File.read!(Path.join(dest, "lib/hello_pkg.ex")) =~ "hello_from_hex"
  end

  test "a repository that is not trusted is never used", %{fixture: fixture} do
    :ok = Package.remove_repo(:fixture)

    assert Package.repos() == []
    assert {:error, :no_such_package} = Hex.resolve("hello_pkg")
    # The repository is still there, it is simply not trusted.
    assert File.dir?(Path.join(fixture, "public"))
  end
end
