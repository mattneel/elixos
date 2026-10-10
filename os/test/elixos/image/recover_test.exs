defmodule Elixos.Image.RecoverTest do
  # Smalltalk's "recover lost changes": a boot loads the saved generation, never
  # the journal tail, but nothing typed since the last save is ever lost.
  use ExUnit.Case, async: true

  @moduletag milestone: 7
  @moduletag :tmp_dir

  alias Elixos.Image
  alias Elixos.Image.Capture

  setup %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "image")
    {:ok, image} = Image.open(root)
    %{image: image, root: root}
  end

  defp define(body) do
    mod = Module.concat([Elixos.RecoverTest.Defined, "M#{System.unique_integer([:positive])}"])
    on_exit(fn -> unload(mod) end)
    {_, _, [{^mod, bytecode}]} = Capture.eval("defmodule #{inspect(mod)} do\n#{body}\nend")
    {mod, bytecode}
  end

  defp unload(mod) do
    :code.purge(mod)
    :code.delete(mod)
    :code.purge(mod)
  end

  test "modules recorded after a save are unsaved, and recoverable", %{image: image, root: root} do
    {saved, saved_code} = define("def v, do: :saved")
    {:ok, _} = Image.record(image, saved, saved_code)
    {:ok, 1} = Image.save(image)

    {late, late_code} = define("def v, do: :late")
    {:ok, _} = Image.record(image, late, late_code)
    :ok = Image.close(image)

    # "Reboot": a fresh VM state with only generation 1 restored.
    unload(saved)
    unload(late)
    {:ok, image} = Image.open(root)
    {:ok, [^saved]} = Image.restore(image, 1)
    refute Code.loaded?(late)

    assert Image.unsaved(image, 1) == [late]
    assert Image.recover(image, [late]) == {:ok, [late]}
    assert late.v() == :late
  end

  test "a module changed since the save is unsaved too", %{image: image} do
    {mod, v1} = define("def v, do: 1")
    {:ok, _} = Image.record(image, mod, v1)
    {:ok, 1} = Image.save(image)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      {_, _, [{^mod, v2}]} = Capture.eval("defmodule #{inspect(mod)} do\ndef v, do: 2\nend")
      {:ok, _} = Image.record(image, mod, v2)
    end)

    assert Image.unsaved(image, 1) == [mod]
  end

  test "nothing is unsaved right after a save", %{image: image} do
    {mod, code} = define("")
    {:ok, _} = Image.record(image, mod, code)
    {:ok, n} = Image.save(image)
    assert Image.unsaved(image, n) == []
  end

  test "against the factory (generation 0) every recorded module is unsaved", %{image: image} do
    {a, a_code} = define("")
    {b, b_code} = define("")
    {:ok, _} = Image.record(image, a, a_code)
    {:ok, _} = Image.record(image, b, b_code)
    assert Image.unsaved(image, 0) == Enum.sort([a, b])
  end
end
