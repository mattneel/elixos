defmodule Elixos.Image.CoprocGenerationTest do
  @moduledoc """
  M29: a coprocessor bundle is generation content (ADR-099). It is recorded in
  the working set like a module (store blob plus journal entry), a save makes it
  the generation's, a reopened image replays it, and a candidate overlay cannot
  change it.
  """
  use ExUnit.Case, async: true

  alias Elixos.Image
  alias Elixos.Image.{Generation, Store}

  @moduletag milestone: 29
  @moduletag :tmp_dir

  test "a recorded bundle is saved into the generation and survives a reopen", %{tmp_dir: root} do
    {:ok, image} = Image.open(root)
    bundle = "bundle bytes v1"
    assert {:ok, hash} = Image.record_coproc(image, bundle)
    assert hash == Store.hash(bundle)

    assert {:ok, 1} = Image.save(image)
    assert {:ok, %Generation{coproc: ^hash}} = Image.generation(image, 1)
    assert Image.coproc_bundle(image, 1) == {:ok, bundle}
    :ok = Image.close(image)

    {:ok, image} = Image.open(root)
    assert Image.coproc(image) == hash
    # Removing it is recorded too, and the next generation carries none.
    assert {:ok, nil} = Image.record_coproc(image, nil)
    assert {:ok, 2} = Image.save(image)
    assert Image.coproc_bundle(image, 2) == {:ok, nil}
    assert Image.coproc_bundle(image, 1) == {:ok, bundle}
    :ok = Image.close(image)

    {:ok, image} = Image.open(root)
    assert Image.coproc(image) == nil
  end

  test "a candidate overlay keeps its parent's bundle and may not bring its own", %{tmp_dir: root} do
    {:ok, image} = Image.open(root)
    {:ok, hash} = Image.record_coproc(image, "parent bundle")
    {:ok, 1} = Image.save(image)

    assert {:ok, 2} = Image.stage(image, %Generation{parent: 1, modules: %{}})
    assert {:ok, %Generation{coproc: ^hash}} = Image.generation(image, 2)

    assert Image.stage(image, %Generation{parent: 1, modules: %{}, coproc: Store.hash("x")}) ==
             {:error, :candidate_coproc_bundle}
  end

  test "a manifest written before M29 has no bundle", %{tmp_dir: root} do
    dir = Path.join(root, "generations")
    File.mkdir_p!(dir)

    legacy = %{number: 1, parent: 0, modules: %{}, boot: [], created_at: nil, provenance: nil}
    File.write!(Generation.path(dir, 1), :erlang.term_to_binary({:elixos_generation, 1, legacy}))

    assert {:ok, %Generation{number: 1, coproc: nil}} = Generation.read(dir, 1)
    {:ok, image} = Image.open(root)
    assert Image.coproc_bundle(image, 1) == {:ok, nil}
  end
end
