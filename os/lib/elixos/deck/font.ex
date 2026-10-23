defmodule Elixos.Deck.Font do
  @moduledoc """
  The deck's bitmap font (M33): Spleen 12x24 by Frederic Cambus, version
  2.1.0, BSD 2-Clause licence (`priv/deck/LICENSE.spleen`, compatible with the
  repository's MIT licence; the copyright notice travels with the data).

  `priv/deck/spleen-12x24.txt` holds the glyphs Elixos draws, taken from the
  upstream BDF: ASCII, Latin-1, curly quotes, bullet, ellipsis and box
  drawing. Each line is `<codepoint hex> <24 rows of 4 hex digits>`, each row
  12 pixels left-aligned in 16 bits (bit 15 is x = 0). The table is read at
  compile time; nothing is loaded at run time.

  A codepoint without a glyph draws as `?`. The font is the renderer's and
  the test screen reader's (`Elixos.Test.DeckScreen`), so the two can never
  disagree about what a character looks like.
  """

  @width 12
  @height 24
  @source Path.expand("../../../priv/deck/spleen-12x24.txt", __DIR__)
  @external_resource @source

  @glyphs (for line <- File.read!(@source) |> String.split("\n", trim: true), into: %{} do
             [cp, hex] = String.split(line, " ")

             rows =
               for <<row::binary-size(4) <- hex>>, do: Bitwise.bsr(String.to_integer(row, 16), 4)

             {String.to_integer(cp, 16), List.to_tuple(rows)}
           end)

  @doc "Glyph width in pixels."
  def width, do: @width

  @doc "Glyph height in pixels."
  def height, do: @height

  @doc """
  The glyph for `codepoint`: a tuple of #{@height} rows, each a #{@width}-bit
  integer whose most significant bit is the leftmost pixel.
  """
  @spec glyph(non_neg_integer()) :: tuple()
  def glyph(codepoint) do
    case @glyphs do
      %{^codepoint => rows} -> rows
      %{?? => rows} -> rows
    end
  end

  @doc "Whether the font has a glyph of its own for `codepoint`."
  @spec has?(non_neg_integer()) :: boolean()
  def has?(codepoint), do: Map.has_key?(@glyphs, codepoint)

  @doc "Every `{codepoint, rows}` in the font, by codepoint."
  @spec glyphs() :: [{non_neg_integer(), tuple()}]
  def glyphs, do: @glyphs |> Map.to_list() |> Enum.sort()
end
