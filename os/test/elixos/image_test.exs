defmodule Elixos.ImageTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 6
  @moduletag :tmp_dir

  alias Elixos.Image
  alias Elixos.Image.{Capture, Generation, Journal, Store}

  setup %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "image")
    {:ok, image} = Image.open(root)
    %{image: image, root: root}
  end

  defp define(body) do
    mod = Module.concat([Elixos.ImageTest.Defined, "M#{System.unique_integer([:positive])}"])
    on_exit(fn -> unload(mod) end)
    {_, _, [{^mod, bytecode}]} = Capture.eval("defmodule #{inspect(mod)} do\n#{body}\nend")
    {mod, bytecode}
  end

  defp unload(mod) do
    :code.purge(mod)
    :code.delete(mod)
    :code.purge(mod)
  end

  test "a recorded module survives being unloaded: save, then restore", %{image: image} do
    {mod, bytecode} = define("def hi, do: :persisted")
    assert {:ok, hash} = Image.record(image, mod, bytecode)
    assert hash == Store.hash(bytecode)

    assert Image.save(image) == {:ok, 1}

    unload(mod)
    refute Code.loaded?(mod)

    assert Image.restore(image, 1) == {:ok, [mod]}
    assert mod.hi() == :persisted
  end

  test "each save is a new generation whose parent is the previous one", %{
    image: image,
    root: root
  } do
    {a, a_code} = define("def v, do: 1")
    {:ok, _} = Image.record(image, a, a_code)
    assert {:ok, 1} = Image.save(image)

    {b, b_code} = define("def v, do: 2")
    {:ok, _} = Image.record(image, b, b_code)
    assert {:ok, 2} = Image.save(image, boot: [{b, :v, []}])

    dir = Path.join(root, "generations")
    assert {:ok, %Generation{number: 1, parent: 0, modules: m1}} = Generation.read(dir, 1)
    assert Map.keys(m1) == [a]

    assert {:ok, %Generation{number: 2, parent: 1, modules: m2, boot: [{^b, :v, []}]}} =
             Generation.read(dir, 2)

    assert Enum.sort(Map.keys(m2)) == Enum.sort([a, b])
  end

  test "re-recording a module replaces its hash in the working set", %{image: image} do
    {mod, v1} = define("def v, do: 1")
    {:ok, h1} = Image.record(image, mod, v1)

    # Redefining a module warns ("redefining module"); that is expected here.
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      {_, _, [{^mod, v2}]} = Capture.eval("defmodule #{inspect(mod)} do\ndef v, do: 2\nend")
      send(self(), {:v2, v2})
    end)

    assert_received {:v2, v2}
    {:ok, h2} = Image.record(image, mod, v2)

    assert h1 != h2
    assert Image.modules(image) == %{mod => h2}
  end

  test "the working set is rebuilt from the journal on open", %{image: image, root: root} do
    {mod, bytecode} = define("def hi, do: :hi")
    {:ok, hash} = Image.record(image, mod, bytecode)
    :ok = Image.close(image)

    {:ok, reopened} = Image.open(root)
    assert Image.modules(reopened) == %{mod => hash}
  end

  test "forgotten modules are left out of the next generation", %{image: image, root: root} do
    {keep, keep_code} = define("")
    {drop, drop_code} = define("")
    {:ok, _} = Image.record(image, keep, keep_code)
    {:ok, _} = Image.record(image, drop, drop_code)
    :ok = Image.forget(image, drop)

    {:ok, n} = Image.save(image)
    {:ok, %Generation{modules: modules}} = Generation.read(Path.join(root, "generations"), n)
    assert Map.keys(modules) == [keep]
  end

  test "every change is journaled before anything else", %{image: image, root: root} do
    {mod, bytecode} = define("")
    {:ok, hash} = Image.record(image, mod, bytecode)
    :ok = Image.forget(image, mod)
    {:ok, 1} = Image.save(image)

    assert {:ok, entries, :clean} = Journal.read(Path.join(root, "journal.log"))

    assert Enum.map(entries, &elem(&1, 1)) == [
             {:module, mod, hash},
             {:forget, mod},
             {:generation, 1}
           ]
  end

  test "restore failures", %{image: image, root: root} do
    assert Image.restore(image, 42) == {:error, :not_found}

    {mod, bytecode} = define("")
    {:ok, hash} = Image.record(image, mod, bytecode)
    {:ok, n} = Image.save(image)

    {:ok, store} = Store.open(Path.join(root, "store"))
    File.rm!(Store.path_for(store, hash))
    assert Image.restore(image, n) == {:error, {:missing_blob, mod}}
  end
end
