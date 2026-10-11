defmodule Elixos.ObanImageTest do
  @moduledoc """
  An app's `oban:` declaration is part of its install (M19): it survives a
  reopen, becomes a boot MFA on the *next* generation, and replays only as the
  entry that was written - a historical install from before M19 has no
  declaration, and none is invented for it.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 19
  @moduletag :tmp_dir

  alias Elixos.Image
  alias Elixos.Image.Generation

  @declaration [queues: [jobs: 3], cron: [{"0 3 * * *", Elixos.ObanImageTest.Worker}]]

  test "a declaration replays and becomes configure_app! before the services", %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "image")
    {:ok, image} = Image.open(root)

    :ok =
      Image.record_app(
        image,
        :demo,
        "1.0.0",
        [{Elixos.ObanImageTest.Service, []}],
        %{oban: "~> 2.24"},
        @declaration
      )

    :ok = Image.record_app(image, :plain, "0.1.0", [], %{}, [])
    {:ok, n} = Image.save(image)
    :ok = Image.close(image)

    {:ok, reopened} = Image.open(root)
    assert Image.apps(reopened) == %{demo: "1.0.0", plain: "0.1.0"}
    assert %{app: :demo, version: "1.0.0", deps: %{oban: "~> 2.24"}} =
             Enum.find(Image.packages(reopened), &(&1.app == :demo))

    {:ok, %Generation{boot: boot}} = Generation.read(Path.join(root, "generations"), n)

    assert {Elixos.Oban, :configure_app!, [:demo, @declaration]} in boot
    assert {Elixos.Package, :start_service, [{Elixos.ObanImageTest.Service, []}]} in boot

    # The app that declared nothing gets no MFA, and the declaration is
    # configured before the services that may enqueue.
    refute Enum.any?(boot, &match?({_, _, [:plain | _]}, &1))
    oban = Enum.find_index(boot, &match?({Elixos.Oban, :configure_app!, _}, &1))
    service = Enum.find_index(boot, &match?({Elixos.Package, :start_service, _}, &1))
    assert oban < service

    # A generation that is written again keeps one MFA per app, not two.
    {:ok, n2} = Image.save(reopened)
    {:ok, %Generation{boot: boot2}} = Generation.read(Path.join(root, "generations"), n2)
    assert Enum.count(boot2, &match?({Elixos.Oban, :configure_app!, [:demo, _]}, &1)) == 1
    :ok = Image.close(reopened)
  end

  test "a historical install replays as an app that declared no scheduler", %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "image")
    journal = Path.join(root, "journal.log")
    File.mkdir_p!(root)

    # What M11 and M15 wrote, before M19 existed: services and requirements,
    # in their own entries.
    {:ok, journal} = Elixos.Image.Journal.open(journal)
    {:ok, _} = Elixos.Image.Journal.append(journal, {:app, :legacy, "2.0.0", []})
    {:ok, _} = Elixos.Image.Journal.append(journal, {:app_deps, :legacy, %{ecto: "~> 3.0"}})
    :ok = Elixos.Image.Journal.close(journal)

    {:ok, image} = Image.open(root)
    assert Image.apps(image) == %{legacy: "2.0.0"}
    {:ok, n} = Image.save(image)
    :ok = Image.close(image)

    {:ok, %Generation{boot: boot}} = Generation.read(Path.join(root, "generations"), n)
    refute Enum.any?(boot, &match?({Elixos.Oban, _, _}, &1))
  end
end
