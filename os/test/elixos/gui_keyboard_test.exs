defmodule Elixos.GUI.KeyboardTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 27

  alias Elixos.GUI.Keyboard

  test "shift affects text only while held, including autorepeat" do
    state = Keyboard.new()
    assert {:ok, [], state} = Keyboard.decode(state, "KEY 42 1")
    assert {:ok, [{:key, "Y", :press}], state} = Keyboard.decode(state, "KEY 21 1")
    assert {:ok, [{:key, "Y", :repeat}], state} = Keyboard.decode(state, "KEY 21 2")
    assert {:ok, [], state} = Keyboard.decode(state, "KEY 42 0")
    assert {:ok, [{:key, "y", :press}], _state} = Keyboard.decode(state, "KEY 21 1")
  end

  test "caps lock toggles once per press and combines with shift for letters, not digits" do
    assert {:ok, [], state} = Keyboard.decode(Keyboard.new(), "KEY 58 1")
    assert {:ok, [], state} = Keyboard.decode(state, "KEY 58 2")
    assert {:ok, [{:key, "A", :press}], state} = Keyboard.decode(state, "KEY 30 1")
    assert {:ok, [{:key, "1", :press}], state} = Keyboard.decode(state, "KEY 2 1")
    assert {:ok, [], state} = Keyboard.decode(state, "KEY 42 1")
    assert {:ok, [{:key, "a", :press}], state} = Keyboard.decode(state, "KEY 30 1")
    assert {:ok, [{:key, "!", :press}], state} = Keyboard.decode(state, "KEY 2 1")
    assert {:ok, [], state} = Keyboard.decode(state, "KEY 58 0")
    assert {:ok, [], state} = Keyboard.decode(state, "KEY 58 1")
    assert {:ok, [], state} = Keyboard.decode(state, "KEY 42 0")
    assert {:ok, [{:key, "a", :press}], _state} = Keyboard.decode(state, "KEY 30 1")
  end

  test "control and alt modified letters do not become accidental text answers" do
    assert {:ok, [], state} = Keyboard.decode(Keyboard.new(), "KEY 29 1")
    assert {:ok, [{:key, "Ctrl+c", :press}], state} = Keyboard.decode(state, "KEY 46 1")
    assert {:ok, [], state} = Keyboard.decode(state, "KEY 29 0")
    assert {:ok, [], state} = Keyboard.decode(state, "KEY 56 1")
    assert {:ok, [{:key, "Alt+c", :press}], _state} = Keyboard.decode(state, "KEY 46 1")
  end

  test "extended navigation and release packets retain their meaning" do
    state = Keyboard.new()
    assert {:ok, [{:key, "ArrowDown", :press}], ^state} = Keyboard.decode(state, "KEY 108 1")
    assert {:ok, [{:key, "Enter", :release}], ^state} = Keyboard.decode(state, "KEY 28 0")
    assert {:ok, [{:key, "F12", :press}], ^state} = Keyboard.decode(state, "KEY 88 1")
    assert {:ok, [{:pointer, 320, 240}], ^state} = Keyboard.decode(state, "POINTER 320 240")
    assert {:ok, [{:button, :left, :press}], ^state} = Keyboard.decode(state, "BUTTON 272 1")
  end

  test "malformed packet values are errors, not input" do
    state = Keyboard.new()

    for packet <- ["KEY 21 3", "KEY y 1", "POINTER 1 x", "BUTTON 272 8", "garbage"] do
      assert Keyboard.decode(state, packet) == {:error, :invalid_event}
    end
  end
end
