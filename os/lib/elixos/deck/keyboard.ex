defmodule Elixos.Deck.Keyboard do
  @moduledoc """
  The deck's on-screen keyboard (M33): three layers of five rows on the
  lower part of the panel (`Elixos.Deck.Layout`). Every row is ten units of
  56 px; a key spans one or more units.

      :lower      1 2 3 4 5 6 7 8 9 0 / q w e r t y u i o p /
                  a s d f g h j k l : / ^ z x c v b n m DEL /
                  ?123 space . , RET
      :upper      the same with capitals; `^` shifts one letter
      :symbols    ! @ # $ % ^ & * ( ) / - _ = + [ ] { } \\ | /
                  ; : ' " < > / ? ` ~ / ' ( ) [ ] { } " DEL /
                  abc space . , RET

  Taps arrive as touch events (`{:touch, :down | :move | :up, x, y}`,
  `Elixos.Coproc.Touch`): a key is pressed on `:down` and typed on `:up`,
  wherever the finger was lifted; `:move` is ignored.
  """

  alias Elixos.Deck.Layout

  @type action ::
          {:char, String.t()} | :backspace | :enter | :shift | :symbols | :letters
  @type key :: %{
          label: String.t(),
          action: action(),
          rect: {integer(), integer(), integer(), integer()}
        }
  @type layer :: :lower | :upper | :symbols
  @type t :: %{layer: layer(), pressed: key() | nil}

  @letters [~c"qwertyuiop", ~c"asdfghjkl"]

  @doc "A keyboard showing its lower-case layer, nothing pressed."
  @spec new() :: t()
  def new, do: %{layer: :lower, pressed: nil}

  @doc "The keys of `layer`, with their pixel rectangles."
  @spec keys(layer()) :: [key()]
  def keys(layer) do
    layer
    |> rows()
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, index} -> place(row, index) end)
  end

  defp rows(:symbols) do
    [
      chars("!@#$%^&*()"),
      chars("-_=+[]{}\\|"),
      chars(";:'\"<>/?`~"),
      chars("'()[]{}\"") ++ [{"DEL", :backspace, 2}],
      bottom({"abc", :letters, 2})
    ]
  end

  defp rows(letters) do
    case_fun = if letters == :upper, do: &String.upcase/1, else: & &1
    [first, second] = Enum.map(@letters, &(&1 |> to_string() |> case_fun.()))

    [
      chars("1234567890"),
      chars(first),
      chars(second <> ":"),
      [{"^", :shift, 1}] ++ chars(case_fun.("zxcvbnm")) ++ [{"DEL", :backspace, 2}],
      bottom({"?123", :symbols, 2})
    ]
  end

  defp bottom(toggle) do
    [
      toggle,
      {"space", {:char, " "}, 4},
      {".", {:char, "."}, 1},
      {",", {:char, ","}, 1},
      {"RET", :enter, 2}
    ]
  end

  defp chars(text), do: for(c <- String.graphemes(text), do: {c, {:char, c}, 1})

  defp place(row, index) do
    y = Layout.keyboard_top() + index * Layout.key_height()

    {keys, _} =
      Enum.map_reduce(row, 0, fn {label, action, span}, unit ->
        x = Layout.keyboard_left() + unit * Layout.key_unit()

        {%{
           label: label,
           action: action,
           rect: {x, y, span * Layout.key_unit(), Layout.key_height()}
         }, unit + span}
      end)

    keys
  end

  @doc "The key of `layer` under `{x, y}`, or nil."
  @spec hit(layer(), integer(), integer()) :: key() | nil
  def hit(layer, x, y) do
    Enum.find(keys(layer), fn %{rect: {kx, ky, w, h}} ->
      x >= kx and x < kx + w and y >= ky and y < ky + h
    end)
  end

  @doc "The centre of the key of `layer` that does `action`: where a test taps."
  @spec center(layer(), action()) :: {integer(), integer()}
  def center(layer, action) do
    %{rect: {x, y, w, h}} =
      Enum.find(keys(layer), &(&1.action == action)) ||
        raise ArgumentError, "no #{inspect(action)} on #{layer}"

    {x + div(w, 2), y + div(h, 2)}
  end

  @doc """
  The layer and action that type the character `char` (a one-grapheme
  string), preferring the lower layer: how a test spells out an expression.
  """
  @spec locate(String.t()) :: {layer(), action()}
  def locate(char) do
    Enum.find_value([:lower, :upper, :symbols], fn layer ->
      if Enum.any?(keys(layer), &(&1.action == {:char, char})), do: {layer, {:char, char}}
    end) || raise ArgumentError, "no key types #{inspect(char)}"
  end

  @doc """
  Feeds one touch event. Returns the new keyboard, what was typed (`{:char,
  text}`, `:backspace`, `:enter` or nil) and whether the layer changed (the
  keyboard must then be redrawn).
  """
  @spec touch(t(), {:touch, :down | :move | :up, integer(), integer()}) ::
          {t(), {:char, String.t()} | :backspace | :enter | nil, boolean()}
  def touch(state, {:touch, :down, x, y}),
    do: {%{state | pressed: hit(state.layer, x, y)}, nil, false}

  def touch(%{pressed: nil} = state, {:touch, :up, _x, _y}), do: {state, nil, false}

  def touch(%{pressed: key} = state, {:touch, :up, _x, _y}),
    do: type(%{state | pressed: nil}, key.action)

  def touch(state, {:touch, _other, _x, _y}), do: {state, nil, false}

  defp type(state, :shift), do: switch(state, if(state.layer == :upper, do: :lower, else: :upper))
  defp type(state, :symbols), do: switch(state, :symbols)
  defp type(state, :letters), do: switch(state, :lower)

  # A shift lasts for one key.
  defp type(%{layer: :upper} = state, action), do: {%{state | layer: :lower}, action, true}
  defp type(state, action), do: {state, action, false}

  defp switch(state, layer), do: {%{state | layer: layer}, nil, true}
end
