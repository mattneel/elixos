defmodule Elixos.Deck.Paint do
  @moduledoc """
  Pixels and `elixos-deck-fb` commands (docs/PROTOCOL.md §12) for the deck.

  Colours are RGB565. Text is drawn cell by cell from `Elixos.Deck.Font`; a
  rendered cell (24 rows of 12 little-endian pixels) is cached per
  `{codepoint, foreground, background}` in the calling process, so a
  keystroke costs one cached lookup and one small blit.

  Commands, one packet each (the Port adds the 4-byte length):

      F x y w h colour          fill
      B x y w h pixels          blit w * h pixels, rows top to bottom
      M x y w h tx ty           move a rectangle (overlap allowed)
      C x y w h                 commit with this damage rectangle

  All numbers little-endian u16.
  """

  alias Elixos.Deck.Font

  import Bitwise

  @doc "RGB565 from 8-bit channels."
  def rgb(r, g, b), do: (r >>> 3) <<< 11 ||| (g >>> 2) <<< 5 ||| b >>> 3

  def background, do: 0x0000
  def text, do: rgb(0xC0, 0xC0, 0xC0)
  def status_background(:rescue), do: rgb(0xB0, 0x00, 0x00)
  def status_background(_mode), do: rgb(0x00, 0x60, 0x80)
  def status_text, do: 0xFFFF
  def keyboard_background, do: rgb(0x10, 0x10, 0x14)
  def key, do: rgb(0x40, 0x40, 0x48)
  def special_key, do: rgb(0x28, 0x30, 0x40)
  def key_label, do: 0xFFFF

  defp rect({x, y, w, h}), do: <<x::little-16, y::little-16, w::little-16, h::little-16>>

  @doc "A fill command."
  def fill(r, colour), do: ["F", rect(r), <<colour::little-16>>]

  @doc "A move command: the rectangle `r` to `{tx, ty}`."
  def move(r, {tx, ty}), do: ["M", rect(r), <<tx::little-16, ty::little-16>>]

  @doc "A commit command."
  def commit(r), do: ["C", rect(r)]

  @doc """
  A blit of one line of text at `{x, y}`: `cells` is a list of
  `{codepoint, foreground, background}`.
  """
  def text_run({x, y}, cells) do
    rendered = Enum.map(cells, &cell/1)

    pixels =
      for row <- 0..(Font.height() - 1) do
        Enum.map(rendered, &elem(&1, row))
      end

    ["B", rect({x, y, length(cells) * Font.width(), Font.height()}), pixels]
  end

  @doc "The text `string` in one colour pair, as `text_run/2` cells."
  def cells(string, fg, bg), do: for(<<c::utf8 <- string>>, do: {c, fg, bg})

  @doc "One rendered cell: a tuple of #{Font.height()} row binaries."
  def cell({codepoint, fg, bg} = key) do
    case Process.get({__MODULE__, key}) do
      nil ->
        glyph = Font.glyph(codepoint)
        top = Font.width() - 1

        rows =
          for row <- 0..(Font.height() - 1) do
            bits = elem(glyph, row)

            for x <- 0..top,
                into: <<>>,
                do: <<if((bits >>> (top - x) &&& 1) == 1, do: fg, else: bg)::little-16>>
          end
          |> List.to_tuple()

        Process.put({__MODULE__, key}, rows)
        rows

      rows ->
        rows
    end
  end

  @doc "The smallest rectangle covering both (either may be nil)."
  def union(nil, r), do: r
  def union(r, nil), do: r

  def union({x1, y1, w1, h1}, {x2, y2, w2, h2}) do
    x = min(x1, x2)
    y = min(y1, y2)
    {x, y, max(x1 + w1, x2 + w2) - x, max(y1 + h1, y2 + h2) - y}
  end
end
