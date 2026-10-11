defmodule Elixos.Image.VerifiedRestoreTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 17
  @moduletag :tmp_dir

  alias Elixos.Image
  alias Elixos.Image.{Capture, Store}

  test "a corrupt later blob does not load an earlier module", %{tmp_dir: dir} do
    {:ok, image} = Image.open(Path.join(dir, "image"))
    suffix = "M#{System.unique_integer([:positive])}"
    first = Module.concat([__MODULE__, "A", suffix])
    last = Module.concat([__MODULE__, "Z", suffix])

    on_exit(fn -> Enum.each([first, last], &unload/1) end)

    hashes =
      for module <- [first, last], into: %{} do
        {_, _, [{^module, bytes}]} =
          Capture.eval("defmodule #{inspect(module)} do\n  def value, do: :verified\nend")

        {:ok, hash} = Image.record(image, module, bytes)
        {module, hash}
      end

    assert Image.save(image) == {:ok, 1}
    Enum.each([first, last], &unload/1)
    {:ok, store} = Store.open(Path.join([dir, "image", "store"]))
    File.write!(Store.path_for(store, hashes[last]), "corrupt bytes")

    assert Image.restore(image, 1) == {:error, {:missing_blob, last}}
    refute Code.loaded?(first)
    refute Code.loaded?(last)
  end

  defp unload(module) do
    :code.purge(module)
    :code.delete(module)
    :code.purge(module)
  end
end
