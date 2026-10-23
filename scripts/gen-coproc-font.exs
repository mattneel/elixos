# Generates os/src/coproc_font.erl from os/priv/deck/spleen-12x24.txt: the
# printable ASCII glyphs the coprocessor's display driver draws its status
# line with (M33). os/test/elixos/coproc_display_k230_test.exs checks that
# the two fonts agree.
#
#   elixir scripts/gen-coproc-font.exs
root = Path.expand("..", __DIR__)
lines = File.read!(Path.join(root, "os/priv/deck/spleen-12x24.txt")) |> String.split("\n", trim: true)

glyphs =
  for line <- lines, [cp, hex] = String.split(line, " "), c = String.to_integer(cp, 16), c in 32..126,
      into: %{},
      do: {c, hex}

rows = fn hex -> Enum.join(for(<<r::binary-size(4) <- hex>>, do: "16#" <> r <> ":16"), ", ") end
clauses = for c <- 32..126, do: "glyph(#{c}) ->\n    <<" <> rows.(Map.fetch!(glyphs, c)) <> ">>;"

File.write!(Path.join(root, "os/src/coproc_font.erl"), """
%% GENERATED from os/priv/deck/spleen-12x24.txt (printable ASCII only) by
%% scripts/gen-coproc-font.exs; do not edit.
%%
%% Spleen 12x24 by Frederic Cambus, version 2.1.0, BSD 2-Clause licence
%% (os/priv/deck/LICENSE.spleen; the copyright notice travels with the data).
%%
%% The coprocessor display driver draws its own status line with it
%% (coproc_deck_scanout), so it shows the same glyphs as Elixos.Deck.Font.
%% glyph(Char) is 24 rows of 16 bits, big-endian, bit 15 the leftmost of 12
%% pixels; a character outside 32..126 draws as $?.
-module(coproc_font).

-export([glyph/1, width/0, height/0]).

width() -> 12.

height() -> 24.

#{Enum.join(clauses, "\n")}
glyph(_) ->
    <<#{rows.(Map.fetch!(glyphs, ??))}>>.
""")
