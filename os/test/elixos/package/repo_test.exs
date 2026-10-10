defmodule Elixos.Package.RepoTest do
  @moduledoc """
  Repository trust (ADR-019, M14): a repository is trusted exactly when it was
  added with its key, and an install can never trust one implicitly.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 14
  @moduletag :tmp_dir

  alias Elixos.Package

  setup %{tmp_dir: tmp_dir} do
    hex_dir = Path.join(tmp_dir, "hex")
    previous = Application.get_env(:elixos, :hex_dir)
    Application.put_env(:elixos, :hex_dir, hex_dir)

    on_exit(fn ->
      if previous, do: Application.put_env(:elixos, :hex_dir, previous),
        else: Application.delete_env(:elixos, :hex_dir)
    end)

    %{hex_dir: hex_dir, key: fixture_key()}
  end

  defp fixture_key do
    Elixos.Test.Paths.fixture("hex_repo")
    |> Path.join("public/public_key")
    |> File.read!()
  end

  test "nothing is trusted before it is added" do
    refute Elixos.Package.Repo.trusted?(:anything)
    assert Package.repos() == []
  end

  test "adding a repository with its key is the consent step", %{hex_dir: hex_dir, key: key} do
    assert Package.add_repo(:team, "/data/mirrors/team", key: key) == :ok
    assert Elixos.Package.Repo.trusted?(:team)

    assert [%Elixos.Package.Repo{name: :team, url: "/data/mirrors/team", key: ^key}] = Package.repos()

    # The key is kept where PROTOCOL.md §8 says, so trust survives a power cycle.
    assert File.read!(Path.join([hex_dir, "keys", "team.pub"])) == key
  end

  test "a key that is not a public key is refused, and nothing is written", %{hex_dir: hex_dir} do
    for bad <- ["not a key", "-----BEGIN RSA PUBLIC KEY-----\ngarbage\n", ""] do
      assert Package.add_repo(:bad, "https://example.invalid", key: bad) == {:error, :bad_key}
    end

    refute Elixos.Package.Repo.trusted?(:bad)
    refute File.exists?(Path.join([hex_dir, "keys", "bad.pub"]))
  end

  test "an install never trusts a repository implicitly", %{key: key} do
    # Adding the repository is what makes it trusted; after removing it, the
    # same URL is unknown again — nothing was remembered behind our back.
    assert Package.add_repo(:team, "/data/mirrors/team", key: key) == :ok
    assert Package.remove_repo(:team) == :ok

    refute Elixos.Package.Repo.trusted?(:team)
    assert Package.repos() == []
    assert {:error, :unknown_repo} = Package.remove_repo(:team)
  end

  test "replacing a repository needs replace: true", %{key: key} do
    assert Package.add_repo(:team, "/a", key: key) == :ok
    assert Package.add_repo(:team, "/b", key: key) == {:error, :already_configured}
    assert Package.add_repo(:team, "/b", key: key, replace: true) == :ok
    assert [%Elixos.Package.Repo{url: "/b"}] = Package.repos()
  end
end
