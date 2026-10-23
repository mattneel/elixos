defmodule Elixos.Package.TrustScopeTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :tmp_dir

  alias Elixos.Package.Repo

  test "reading an empty trust store never silently imports a factory preset", %{tmp_dir: tmp} do
    previous = for key <- [:hex_dir, :factory_dir], do: {key, Application.fetch_env(:elixos, key)}

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:elixos, key, value)
          :error -> Application.delete_env(:elixos, key)
        end
      end
    end)

    factory = Path.join(tmp, "factory")
    trust = Path.join(tmp, "trust")
    Application.put_env(:elixos, :factory_dir, factory)
    Application.put_env(:elixos, :hex_dir, trust)
    key = File.read!(Path.join(Elixos.Test.Paths.fixture("hex_repo"), "public/public_key"))
    File.mkdir_p!(Path.join(factory, "hex/keys"))
    File.write!(Path.join(factory, "hex/keys/preset.pub"), key)

    File.write!(
      Path.join(factory, "hex/repos.exs"),
      inspect(preset: [url: "/public/preset", key: key])
    )

    assert Repo.list() == []
    refute File.exists?(Path.join(trust, "repos.exs"))
    assert :ok = Repo.add(:owner, "/public/owner", key: key)
    assert Enum.map(Repo.list(), & &1.name) == [:owner]
    assert :ok = Repo.remove(:owner)
    assert Repo.list() == []

    File.rm!(Path.join(trust, "repos.exs"))
    assert :ok = Repo.ensure_seeded()
    assert Enum.map(Repo.list(), & &1.name) == [:preset]
    assert :ok = Repo.remove(:preset)
    assert :ok = Repo.ensure_seeded()
    assert Repo.list() == []
  end
end
