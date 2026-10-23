%% The coprocessor's side of the deck framebuffer (docs/PROTOCOL.md §12, M33):
%% pure bookkeeping, shared by the board's display backend
%% (coproc_display_k230) and testable on the BEAM.
%%
%%   * header/1 parses the region's 48-byte header;
%%   * plan/2 decides what to push from seq, shown and the damage rectangle:
%%     nothing when shown = seq, the damage rectangle when exactly one commit
%%     was missed, the whole panel otherwise (several commits missed: their
%%     union is unknown) and on the first poll after a (re)start;
%%   * strips/1 cuts a rectangle into bands of at most ?STRIP rows, so a
%%     whole frame is never one 1.4 MB binary on the little core's heap;
%%   * overlay/1 renders the status line (Spleen 12x24, coproc_font) and
%%     compose/3 lays it over the framebuffer's pixels on the way to the panel.
%%     The overlay is never written into the framebuffer: Elixos owns those
%%     pixels, and clearing the status is just pushing the band again.
%%
%% On the board the K230's VO scans the region out itself and the overlay is
%% a VO layer of its own (coproc_display_k230, coproc/src/panel_k230.c), so
%% rows/1, strips/1 and compose/3 serve the panel mirror the host tests use;
%% header/1, plan/2 and overlay/1 serve both.
-module(coproc_deck_scanout).

-export([header/1, plan/2, strips/1, rows/1, overlay/1, compose/3, status_band/0, full/0]).
-export([width/0, height/0, stride/0, header_size/0, shown_offset/0]).

-define(MAGIC, 16#44584C45).
-define(VERSION, 1).
-define(WIDTH, 568).
-define(HEIGHT, 1232).
-define(STRIDE, 1136).
-define(FORMAT_RGB565, 1).
-define(HEADER_SIZE, 4096).
-define(SHOWN_OFFSET, 44).
-define(STRIP, 64).
%% The status band: the same rows as Elixos.Deck's status line.
-define(BAND_HEIGHT, 28).
-define(STATUS_BACKGROUND, 16#7800).
-define(STATUS_TEXT, 16#FFFF).
-define(TEXT_X, 4).
-define(TEXT_Y, 2).

width() -> ?WIDTH.
height() -> ?HEIGHT.
stride() -> ?STRIDE.
header_size() -> ?HEADER_SIZE.
shown_offset() -> ?SHOWN_OFFSET.
full() -> {0, 0, ?WIDTH, ?HEIGHT}.
status_band() -> {0, 0, ?WIDTH, ?BAND_HEIGHT}.

%% The first 48 bytes of the region.
header(<<?MAGIC:32/little, ?VERSION:32/little, ?WIDTH:32/little, ?HEIGHT:32/little,
         ?STRIDE:32/little, ?FORMAT_RGB565:32/little, Seq:32/little,
         X:32/little, Y:32/little, W:32/little, H:32/little, Shown:32/little, _/binary>>) ->
    {ok, #{seq => Seq, damage => {X, Y, W, H}, shown => Shown}};
header(_) ->
    invalid.

%% What to push for this header. First is true until the coprocessor has
%% pushed once since it started: the panel's contents are unknown then.
plan(#{seq := Seq, shown := Shown, damage := Damage}, First) ->
    if
        First -> {push, full(), Seq};
        Seq =:= Shown -> idle;
        Seq =:= (Shown + 1) band 16#FFFFFFFF ->
            case inside(Damage) of
                true -> {push, Damage, Seq};
                false -> {push, full(), Seq}
            end;
        true -> {push, full(), Seq}
    end.

inside({X, Y, W, H}) ->
    W > 0 andalso H > 0 andalso X < ?WIDTH andalso Y < ?HEIGHT andalso
        W =< ?WIDTH - X andalso H =< ?HEIGHT - Y.

strips({X, Y, W, H}) when H =< ?STRIP ->
    [{X, Y, W, H}];
strips({X, Y, W, H}) ->
    [{X, Y, W, ?STRIP} | strips({X, Y + ?STRIP, W, H - ?STRIP})].

%% The byte ranges {Offset, Length} of the region holding Rect's pixels, one
%% per row, or one for full-width rectangles.
rows({0, Y, ?WIDTH, H}) ->
    [{?HEADER_SIZE + Y * ?STRIDE, H * ?STRIDE}];
rows({X, Y, W, H}) ->
    [{?HEADER_SIZE + R * ?STRIDE + 2 * X, 2 * W} || R <- lists:seq(Y, Y + H - 1)].

%% The status band's pixels (RGB565 little-endian, ?WIDTH x ?BAND_HEIGHT) for
%% Text, or none for no status.
overlay(<<>>) ->
    none;
overlay(Text) when is_binary(Text) ->
    Columns = (?WIDTH - ?TEXT_X) div 12,
    Chars = lists:sublist(binary_to_list(Text), Columns),
    Glyphs = [coproc_font:glyph(C) || C <- Chars],
    Background = <<?STATUS_BACKGROUND:16/little>>,
    Blank = binary:copy(Background, ?WIDTH),
    TextWidth = 12 * length(Chars),
    Right = binary:copy(Background, ?WIDTH - ?TEXT_X - TextWidth),
    Left = binary:copy(Background, ?TEXT_X),
    Rows = [
        case Row >= ?TEXT_Y andalso Row < ?TEXT_Y + 24 of
            false ->
                Blank;
            true ->
                G = Row - ?TEXT_Y,
                Cells = [glyph_row(Glyph, G) || Glyph <- Glyphs],
                iolist_to_binary([Left, Cells, Right])
        end
     || Row <- lists:seq(0, ?BAND_HEIGHT - 1)
    ],
    iolist_to_binary(Rows).

glyph_row(Glyph, G) ->
    Skip = 2 * G,
    <<_:Skip/binary, Bits:16, _/binary>> = Glyph,
    << <<(pixel(Bits, Bit)):16/little>> || Bit <- lists:seq(15, 4, -1) >>.

pixel(Bits, Bit) ->
    case (Bits bsr Bit) band 1 of
        1 -> ?STATUS_TEXT;
        0 -> ?STATUS_BACKGROUND
    end.

%% Rect's framebuffer Pixels with the overlay laid over the rows it shares
%% with the status band.
compose(_Rect, Pixels, none) ->
    Pixels;
compose({_X, Y, _W, _H}, Pixels, _Overlay) when Y >= ?BAND_HEIGHT ->
    Pixels;
compose({X, Y, W, H}, Pixels, Overlay) ->
    RowBytes = 2 * W,
    Rows = [
        case Y + R < ?BAND_HEIGHT of
            true -> binary:part(Overlay, (Y + R) * ?STRIDE + 2 * X, RowBytes);
            false -> binary:part(Pixels, R * RowBytes, RowBytes)
        end
     || R <- lists:seq(0, H - 1)
    ],
    iolist_to_binary(Rows).
