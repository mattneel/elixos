defmodule Elixos.GUI.Keyboard do
  @moduledoc """
  Decodes the GUI helper's evdev packets using the default US keyboard layout.

  Modifier state belongs to this GUI session, not to the VM. Direct
  `Elixos.GUI.input/1` events can carry any Unicode character; this decoder
  translates the hardware keycodes and pointer/button packets from the Port.
  """

  defstruct modifiers: MapSet.new(), caps_lock: false, caps_down: false

  @letters Map.new(
             Enum.zip(16..25, ~w(q w e r t y u i o p)) ++
               Enum.zip(30..38, ~w(a s d f g h j k l)) ++
               Enum.zip(44..50, ~w(z x c v b n m))
           )
  @symbols %{
    2 => {"1", "!"},
    3 => {"2", "@"},
    4 => {"3", "#"},
    5 => {"4", "$"},
    6 => {"5", "%"},
    7 => {"6", "^"},
    8 => {"7", "&"},
    9 => {"8", "*"},
    10 => {"9", "("},
    11 => {"0", ")"},
    12 => {"-", "_"},
    13 => {"=", "+"},
    26 => {"[", "{"},
    27 => {"]", "}"},
    39 => {";", ":"},
    40 => {"'", "\""},
    41 => {"`", "~"},
    43 => {"\\", "|"},
    51 => {",", "<"},
    52 => {".", ">"},
    53 => {"/", "?"},
    57 => {" ", " "}
  }
  @special %{
    1 => "Escape",
    14 => "Backspace",
    15 => "Tab",
    28 => "Enter",
    96 => "Enter",
    88 => "F12",
    102 => "Home",
    103 => "ArrowUp",
    104 => "PageUp",
    105 => "ArrowLeft",
    106 => "ArrowRight",
    107 => "End",
    108 => "ArrowDown",
    109 => "PageDown",
    111 => "Delete"
  }
  @modifier_codes [29, 42, 54, 56, 97, 100, 125, 126]
  @buttons %{272 => :left, 273 => :right, 274 => :middle, 275 => :side, 276 => :extra}

  @type t :: %__MODULE__{}
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec decode(t(), binary()) :: {:ok, [term()], t()} | {:error, :invalid_event}
  def decode(state, packet) when is_binary(packet) do
    case String.split(packet) do
      ["KEY", raw_code, raw_value] ->
        with {:ok, code} <- number(raw_code),
             {:ok, value} <- number(raw_value),
             true <- code >= 0 and code <= 65535 and value in [0, 1, 2] do
          key(state, code, value)
        else
          _ -> {:error, :invalid_event}
        end

      ["POINTER", raw_x, raw_y] ->
        with {:ok, x} <- number(raw_x), {:ok, y} <- number(raw_y), true <- x >= 0 and y >= 0 do
          {:ok, [{:pointer, x, y}], state}
        else
          _ -> {:error, :invalid_event}
        end

      ["BUTTON", raw_code, raw_value] ->
        with {:ok, code} <- number(raw_code),
             {:ok, value} <- number(raw_value),
             true <- code >= 0 and code <= 65535 and value in [0, 1, 2] do
          case Map.fetch(@buttons, code) do
            {:ok, button} -> {:ok, [{:button, button, action(value)}], state}
            :error -> {:ok, [], state}
          end
        else
          _ -> {:error, :invalid_event}
        end

      _ ->
        {:error, :invalid_event}
    end
  end

  defp number(raw) do
    case Integer.parse(raw) do
      {value, ""} -> {:ok, value}
      _ -> :error
    end
  end

  defp action(0), do: :release
  defp action(2), do: :repeat
  defp action(_press), do: :press

  defp key(state, code, value) when code in @modifier_codes do
    modifiers =
      if value == 0,
        do: MapSet.delete(state.modifiers, code),
        else: MapSet.put(state.modifiers, code)

    {:ok, [], %{state | modifiers: modifiers}}
  end

  defp key(state, 58, 0), do: {:ok, [], %{state | caps_down: false}}

  defp key(state, 58, value) do
    caps_lock =
      if value == 1 and not state.caps_down, do: not state.caps_lock, else: state.caps_lock

    {:ok, [], %{state | caps_lock: caps_lock, caps_down: true}}
  end

  defp key(state, code, value) do
    case name(state, code) do
      nil -> {:ok, [], state}
      key -> {:ok, [{:key, modified_name(state, key), action(value)}], state}
    end
  end

  defp name(state, code) do
    shift = held?(state, [42, 54])

    cond do
      letter = Map.get(@letters, code) ->
        if shift != state.caps_lock, do: String.upcase(letter), else: letter

      pair = Map.get(@symbols, code) ->
        elem(pair, if(shift, do: 1, else: 0))

      true ->
        Map.get(@special, code)
    end
  end

  defp modified_name(_state, key) when key in ["Escape", "F12"], do: key

  defp modified_name(state, key) do
    cond do
      held?(state, [29, 97]) -> "Ctrl+" <> key
      held?(state, [56, 100]) -> "Alt+" <> key
      held?(state, [125, 126]) -> "Meta+" <> key
      true -> key
    end
  end

  defp held?(state, codes), do: Enum.any?(codes, &MapSet.member?(state.modifiers, &1))
end
