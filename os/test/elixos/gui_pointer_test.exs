defmodule Elixos.GUI.PointerTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 27

  alias Elixos.Approvals.Request
  alias Elixos.GUI.Dialog

  defp question do
    %Request{
      id: 1,
      kind: :confirm,
      prompt: "continue?",
      options: [],
      default: nil
    }
  end

  test "the pointer is visible at the reported screen coordinate, not displaced by panel padding" do
    dialog = Dialog.new(question())
    assert {:continue, dialog} = Dialog.input(dialog, {:pointer, 600, 440})

    pixels =
      EmergeSkia.TreeRenderer.render_to_pixels(
        Dialog.tree(dialog, {640, 480}),
        [otp_app: :elixos, width: 640, height: 480],
        5_000
      )

    background = pixel(pixels, 0, 0)
    assert pixel(pixels, 600, 440) != background
    assert pixel(pixels, 600, 420) == background
  end

  test "a pointer press hits the visible confirm control, but a release or the inter-control gap does not" do
    dialog = Dialog.new(question())
    assert {:continue, dialog} = Dialog.input(dialog, {:pointer, 160, 190})
    assert {:continue, ^dialog} = Dialog.input(dialog, {:button, :left, :release})
    assert {:answer, true, _} = Dialog.input(dialog, {:button, :left, :press})

    assert {:continue, dialog} = Dialog.input(dialog, {:pointer, 320, 190})
    assert {:continue, ^dialog} = Dialog.input(dialog, {:button, :left, :press})
  end

  test "advancing the question keeps the physical pointer location without requiring another movement" do
    dialog = Dialog.new(question())
    assert {:continue, dialog} = Dialog.input(dialog, {:pointer, 160, 190})
    assert {:answer, true, dialog} = Dialog.input(dialog, {:button, :left, :press})

    next = %{question() | id: 2, prompt: "one more?"}
    dialog = Dialog.show(dialog, next)
    assert {:continue, dialog} = Dialog.input(dialog, {:button, :left, :release})
    assert {:answer, true, _} = Dialog.input(dialog, {:button, :left, :press})
  end

  defp pixel(pixels, x, y), do: binary_part(pixels, (y * 640 + x) * 4, 4)
end
