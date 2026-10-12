defmodule Elixos.GUI.DialogTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 27

  alias Elixos.Ask.Question
  alias Elixos.GUI.Dialog

  defp question(kind, opts \\ []) do
    struct!(
      Question,
      Keyword.merge(
        [
          id: 1,
          kind: kind,
          prompt: "choose",
          options: ["alpha", "beta", "gamma"],
          default: nil,
          allow_other: false,
          asker: self()
        ],
        opts
      )
    )
  end

  defp key(dialog, key), do: Dialog.input(dialog, {:key, key, :press})

  test "confirmation has a conservative selection unless a true default was supplied" do
    assert {:answer, false, _} = Dialog.new(question(:confirm)) |> key("Enter")
    assert {:answer, true, _} = Dialog.new(question(:confirm, default: true)) |> key("Enter")
    assert {:answer, true, _} = Dialog.new(question(:confirm)) |> key("y")
    assert {:answer, false, _} = Dialog.new(question(:confirm, default: true)) |> key("n")
  end

  test "choice navigation wraps and a supplied option is initially selected" do
    dialog = Dialog.new(question(:choice, default: "beta"))
    assert {:answer, "beta", _} = key(dialog, "Enter")
    assert {:continue, dialog} = key(dialog, "ArrowDown")
    assert {:answer, "gamma", _} = key(dialog, "Enter")
    assert {:continue, dialog} = key(dialog, "ArrowDown")
    assert {:answer, "alpha", _} = key(dialog, "Enter")
    assert {:continue, dialog} = key(dialog, "ArrowUp")
    assert {:answer, "gamma", _} = key(dialog, "Enter")
  end

  test "other text is a separate choice, including an explicitly empty default" do
    dialog = Dialog.new(question(:choice, default: "", allow_other: true))
    assert {:answer, "", _} = key(dialog, "Enter")
    assert {:continue, dialog} = key(dialog, "δ")
    assert {:answer, "δ", _} = key(dialog, "Enter")

    ordinary = Dialog.new(question(:choice))
    assert {:continue, ^ordinary} = key(ordinary, "z")
    assert {:answer, "alpha", _} = key(ordinary, "Enter")
  end

  test "text editing ignores releases and backspace removes a whole grapheme" do
    dialog = Dialog.new(question(:text, default: "Ada"))
    assert {:continue, dialog} = key(dialog, " ")
    assert {:continue, dialog} = key(dialog, "e\u0301")
    assert {:continue, ^dialog} = Dialog.input(dialog, {:key, "x", :release})
    assert {:continue, dialog} = key(dialog, "Backspace")
    assert {:answer, "Ada ", _} = key(dialog, "Enter")
    assert {:continue, dialog} = key(dialog, "λ")
    assert {:answer, "Ada λ", _} = key(dialog, "Enter")
  end

  test "multi selection requires an explicit non-empty selection and preserves option order" do
    dialog = Dialog.new(question(:multi))
    assert {:continue, %{error: "Select at least one option."} = dialog} = key(dialog, "Enter")
    assert {:continue, dialog} = key(dialog, "ArrowDown")
    assert {:continue, dialog} = key(dialog, " ")
    assert {:continue, dialog} = key(dialog, "ArrowUp")
    assert {:continue, dialog} = key(dialog, " ")
    assert {:answer, ["alpha", "beta"], _} = key(dialog, "Enter")
    assert {:continue, dialog} = key(dialog, " ")
    assert {:answer, ["beta"], _} = key(dialog, "Enter")
  end

  test "multi defaults preselect only options the question actually offers" do
    dialog = Dialog.new(question(:multi, default: ["gamma", "absent", "alpha"]))
    assert {:answer, ["alpha", "gamma"], _} = key(dialog, "Enter")
  end

  test "autorepeat edits text but cannot answer or dismiss unseen questions" do
    dialog = Dialog.new(question(:text, default: "a"))
    assert {:continue, dialog} = Dialog.input(dialog, {:key, "a", :repeat})
    assert dialog.text == "aa"
    assert {:continue, ^dialog} = Dialog.input(dialog, {:key, "Enter", :repeat})
    assert {:continue, ^dialog} = Dialog.input(dialog, {:key, "Escape", :repeat})
    assert {:answer, "aa", _} = key(dialog, "Enter")

    confirm = Dialog.new(question(:confirm, default: true))
    assert {:continue, ^confirm} = Dialog.input(confirm, {:key, "y", :repeat})
    assert {:continue, ^confirm} = Dialog.input(confirm, {:key, "Enter", :repeat})

    multi = Dialog.new(question(:multi, default: ["alpha"]))
    assert {:continue, ^multi} = Dialog.input(multi, {:key, " ", :repeat})
    assert {:answer, ["alpha"], _} = key(multi, "Enter")
  end

  test "queue notifications preserve an edit until the displayed question actually changes" do
    one = question(:text)
    assert {:continue, dialog} = Dialog.new(one) |> key("x")
    dialog = Dialog.show(dialog, one)
    assert {:answer, "x", _} = key(dialog, "Enter")

    two = %{question(:text, default: "next") | id: 2}
    dialog = Dialog.show(dialog, two)
    assert {:answer, "next", _} = key(dialog, "Enter")
  end

  test "escape dismisses a question but returns the idle view to the console" do
    assert {:dismiss, _} = Dialog.new(question(:text)) |> key("Escape")
    assert {:stop, _} = Dialog.new(nil) |> key("Escape")
    assert {:stop, _} = Dialog.new(question(:choice)) |> key("F12")
  end
end
