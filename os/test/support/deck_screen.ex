defmodule Elixos.Test.DeckScreen do
  @moduledoc """
  Reads the deck framebuffer (docs/PROTOCOL.md §12) the way the
  coprocessor would, from the host file behind it (QEMU's ivshmem backing
  file, or a plain file in host tests), and turns the panel back into text so
  tests assert on what a person would read, not on pixels.

  Each cell of the status line and the terminal grid (`Elixos.Deck.Layout`)
  is matched against the renderer's own font (`Elixos.Deck.Font`): the
  cell's most common colour is its background, every other pixel is ink, and
  the ink pattern must equal one glyph exactly. A cell matching no glyph
  reads as U+FFFD. Inverted cells (the cursor) read as their character.
  """

  import Bitwise

  alias Elixos.Deck.{Font, Layout}

  @header_size 4096
  @fields [
    :magic,
    :version,
    :width,
    :height,
    :stride,
    :format,
    :seq,
    :damage_x,
    :damage_y,
    :damage_w,
    :damage_h,
    :shown
  ]

  @doc "The header's fields, by name."
  @spec header(binary()) :: map()
  def header(<<fields::binary-size(48), _::binary>>) do
    values = for <<value::little-32 <- fields>>, do: value
    Map.new(Enum.zip(@fields, values))
  end

  @doc "Whether `region` (bytes) starts with a valid deck header (§12)."
  @spec valid?(binary()) :: boolean()
  def valid?(region) when byte_size(region) >= @header_size do
    match?(
      %{magic: 0x44584C45, version: 1, width: 568, height: 1232, stride: 1136, format: 1},
      header(region)
    )
  end

  def valid?(_region), do: false
  @doc "Reads `path` and decodes it: `%{header:, status:, lines:}`. The header must be valid."
  @spec read(Path.t()) :: map()
  def read(path), do: decode(File.read!(path))

  @doc "Decodes a region's bytes, as `read/1`."
  @spec decode(binary()) :: map()
  def decode(region) do
    header = header(region)

    ExUnit.Assertions.assert(
      %{magic: 0x44584C45, version: 1, width: 568, height: 1232, stride: 1136, format: 1} =
        Map.take(header, [:magic, :version, :width, :height, :stride, :format]),
      "not a deck framebuffer header: #{inspect(header)}"
    )

    pixels = binary_part(region, @header_size, header.stride * header.height)
    {sx, sy} = Layout.status_origin()
    {tx, ty} = Layout.terminal_origin()

    %{
      header: header,
      status: read_line(pixels, {sx, sy}, Layout.status_columns()) |> String.trim_trailing(),
      lines:
        for row <- 0..(Layout.rows() - 1) do
          read_line(pixels, {tx, ty + row * Font.height()}, Layout.columns())
          |> String.trim_trailing()
        end
    }
  end

  @doc "The terminal's text: its lines joined, trailing blank lines dropped."
  @spec text(map()) :: String.t()
  def text(%{lines: lines}), do: lines |> Enum.join("\n") |> String.trim_trailing()

  @doc "The RGB565 pixel at `{x, y}` of a region's bytes."
  def pixel(region, {x, y}) do
    <<value::little-16>> = binary_part(region, @header_size + y * Layout.width() * 2 + x * 2, 2)
    value
  end

  defp read_line(pixels, {x, y}, columns) do
    for column <- 0..(columns - 1), into: "" do
      read_cell(pixels, {x + column * Font.width(), y})
    end
  end

  defp read_cell(pixels, {x, y}) do
    rows =
      for dy <- 0..(Font.height() - 1) do
        row = binary_part(pixels, (y + dy) * Layout.width() * 2 + x * 2, Font.width() * 2)
        for <<value::little-16 <- row>>, do: value
      end

    background =
      rows
      |> List.flatten()
      |> Enum.frequencies()
      |> Enum.max_by(fn {_colour, n} -> n end)
      |> elem(0)

    bits =
      rows
      |> Enum.map(fn row ->
        Enum.reduce(row, 0, fn value, acc ->
          acc <<< 1 ||| if(value == background, do: 0, else: 1)
        end)
      end)
      |> List.to_tuple()

    case Map.fetch(glyph_index(), bits) do
      {:ok, codepoint} -> <<codepoint::utf8>>
      :error -> "\uFFFD"
    end
  end

  # Ink pattern => codepoint; the lowest codepoint wins where glyphs look
  # alike (ASCII before Latin-1).
  defp glyph_index do
    case :persistent_term.get({__MODULE__, :index}, nil) do
      nil ->
        index =
          Font.glyphs()
          |> Enum.reverse()
          |> Map.new(fn {codepoint, rows} -> {rows, codepoint} end)

        :persistent_term.put({__MODULE__, :index}, index)
        index

      index ->
        index
    end
  end

  @doc """
  The `elixos-deck-fb` binary for host tests, built once per run into
  build/deck (or `ELIXOS_DECK_FB`).
  """
  @spec helper() :: Path.t()
  def helper do
    case :persistent_term.get({__MODULE__, :helper}, nil) do
      nil ->
        path = System.get_env("ELIXOS_DECK_FB") || build_helper()
        :persistent_term.put({__MODULE__, :helper}, path)
        path

      path ->
        path
    end
  end

  defp build_helper do
    zig =
      System.find_executable("zig") ||
        ExUnit.Assertions.flunk("zig is not on PATH; cannot build elixos-deck-fb")

    root = Elixos.Test.Paths.repo_root()
    prefix = Elixos.Test.Paths.build("deck")

    {output, status} =
      System.cmd(zig, ["build", "-Drelease", "--prefix", prefix],
        cd: root,
        stderr_to_stdout: true
      )

    status == 0 || ExUnit.Assertions.flunk("zig build failed:\n" <> output)
    Path.join([prefix, "bin", "elixos-deck-fb"])
  end

  @doc "A fresh, zeroed region file of `size` bytes in `dir`."
  @spec region(Path.t(), pos_integer()) :: Path.t()
  def region(dir, size \\ 2 * 1024 * 1024) do
    path = Path.join(dir, "deckfb")
    File.write!(path, :binary.copy(<<0>>, size))
    path
  end
end
