defmodule Elixos.Deck.Layout do
  @moduledoc """
  Where things are on the deck's panel (M33, docs/PROTOCOL.md §12): portrait,
  568 x 1232, origin top left, in the panel's own orientation.

      y    0 ..   28  status line: one text row (rescue or the generation)
      y   32 ..  824  terminal: 33 rows x 46 columns of 12 x 24 cells
      y  832 .. 1232  on-screen keyboard: 5 rows of 80 px, 10 units of 56 px

  The split keeps two thirds of the panel for text and leaves the keyboard
  keys about as large as a phone's (56 x 80 px on a 568 px wide panel).
  The renderer (`Elixos.Deck`) and the tests' screen reader
  (`Elixos.Test.DeckScreen`) both read their geometry from here.
  """

  alias Elixos.Deck.Font

  @width 568
  @height 1232
  @margin 4

  def width, do: @width
  def height, do: @height

  @doc "The status bar: a filled band, with one row of text at `status_origin/0`."
  def status_rect, do: {0, 0, @width, 28}
  def status_origin, do: {@margin, 2}
  def status_columns, do: div(@width - 2 * @margin, Font.width())

  @doc "The terminal grid's top-left pixel, size in cells, and its pixel rectangle."
  def terminal_origin, do: {@margin, 32}
  def columns, do: div(@width - 2 * @margin, Font.width())
  def rows, do: 33

  def terminal_rect do
    {x, y} = terminal_origin()
    {x, y, columns() * Font.width(), rows() * Font.height()}
  end

  @doc "The pixel rectangle of terminal cell `{row, column}`."
  def cell_rect({row, column}) do
    {x, y} = terminal_origin()
    {x + column * Font.width(), y + row * Font.height(), Font.width(), Font.height()}
  end

  @doc "The keyboard's band: everything below the terminal."
  def keyboard_rect, do: {0, keyboard_top(), @width, @height - keyboard_top()}
  def keyboard_top, do: 832
  def key_rows, do: 5
  def key_height, do: 80
  def key_unit, do: 56
  def key_units, do: 10
  def keyboard_left, do: div(@width - key_unit() * key_units(), 2)
end
