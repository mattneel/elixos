defmodule Elixos.Image.CaptureTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 6

  alias Elixos.Image.Capture

  # Unique names keep async tests independent; on_exit unloads what we defined.
  defp fresh_module do
    module = Module.concat([Elixos.Captured, "M#{System.unique_integer([:positive])}"])
    on_exit(fn -> unload(module) end)
    module
  end

  defp unload(module) do
    :code.purge(module)
    :code.delete(module)
    :code.purge(module)
  end

  test "captures a module defined by the evaluated code" do
    mod = fresh_module()

    {value, _binding, captured} =
      Capture.eval("defmodule #{inspect(mod)} do\n  def hi, do: :hi\nend\n1 + 1")

    assert value == 2
    assert [{^mod, bytecode}] = captured
    assert <<"FOR1", _::binary>> = bytecode
  end

  test "captures several modules in definition order" do
    a = fresh_module()
    b = fresh_module()

    {_, _, captured} =
      Capture.eval("defmodule #{inspect(a)} do end\ndefmodule #{inspect(b)} do end")

    assert Enum.map(captured, &elem(&1, 0)) == [a, b]
  end

  test "captures nested modules" do
    outer = fresh_module()
    inner = Module.concat(outer, Inner)
    on_exit(fn -> unload(inner) end)

    code = "defmodule #{inspect(outer)} do\n  defmodule Inner do\n  end\nend"
    {_, _, captured} = Capture.eval(code)
    assert captured |> Enum.map(&elem(&1, 0)) |> Enum.sort() == Enum.sort([outer, inner])
  end

  test "captures modules defined inside function calls" do
    mod = fresh_module()

    {_, _, captured} =
      Capture.eval("Enum.each([1], fn _ -> defmodule #{inspect(mod)} do end end)")

    assert [{^mod, _}] = captured
  end

  test "plain expressions capture nothing and keep the binding" do
    assert Capture.eval("x + 1", x: 41) == {42, [x: 41], []}
    assert {_, binding, []} = Capture.eval("y = 2", [])
    assert binding[:y] == 2
  end

  test "captured bytecode reloads after the module is gone" do
    mod = fresh_module()

    {_, _, [{^mod, bytecode}]} =
      Capture.eval("defmodule #{inspect(mod)} do\n  def hi, do: :back\nend")

    unload(mod)
    refute Code.loaded?(mod)

    assert {:module, ^mod} = :code.load_binary(mod, ~c"captured", bytecode)
    assert mod.hi() == :back
  end

  test "errors raised by the code propagate" do
    assert_raise RuntimeError, "boom", fn -> Capture.eval(~s|raise "boom"|) end
  end
end
