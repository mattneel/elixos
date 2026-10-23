%% The board's display backend (M33, ADR-106): the coprocessor's half of the
%% deck framebuffer (docs/PROTOCOL.md §12). Every ?POLL_MS it reads the
%% region's header; when seq differs from shown it pushes what changed
%% (coproc_deck_scanout:plan/2) to the panel, the status line laid over it,
%% then stores shown. set_status/2 (the lease's "Elixos restarting", or an
%% explicit status) pushes the status band at once.
%%
%% Two seams, each chosen at start from the environment (the payload's on
%% the board, the launcher's on the host):
%%
%%   region  ELIXOS_COPROC_DECK_REGION unset: the board's reserved RAM at
%%           0x08100000 through the firmware's NIFs coproc_k230:fb_read/2 and
%%           fb_write32/2 (coproc/src/platform_nifs.c); a path: that file
%%           (posix_pread/pwrite), as the host tests use it.
%%   panel   ELIXOS_COPROC_DECK_PANEL unset: the RM69A10 over the K230's MIPI
%%           DSI host, coproc_k230:panel_open/0 and panel_write/5 - which
%%           REQUIRE THE BOARD and are not ported yet: the firmware returns
%%           {error, dsi_not_ported} and says so on UART3
%%           (coproc/src/panel_k230.c). A path: a mirror file of the panel
%%           (568 x 1232 RGB565, no header) that receives every push - the
%%           host tests' fake scan-out sink.
%%
%% A panel that cannot be opened leaves the backend polling but never storing
%% shown: nothing was scanned out. info/1 reports panel => {error, Reason}.
-module(coproc_display_k230).

-behaviour(coproc_driver).
-behaviour(coproc_display).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1, set_status/2, flush/2]).

-define(POLL_MS, 20).
-define(STARTING, <<"Elixos starting">>).

init(undefined) ->
    start(#{status => ?STARTING, frames => 0, last_region => none, hdmi => disconnected});
init(#{} = Handoff) ->
    start(coproc_display:restored(with([status, frames, last_region, hdmi, lease], Handoff))).

start(Kept) ->
    Region = open_region(os:getenv("ELIXOS_COPROC_DECK_REGION")),
    Panel = open_panel(os:getenv("ELIXOS_COPROC_DECK_PANEL")),
    Status = maps:get(status, Kept),
    State = Kept#{
        region => Region,
        panel => Panel,
        overlay => coproc_deck_scanout:overlay(Status),
        first => true,
        shown => none,
        pushes => 0
    },
    _ = erlang:send_after(0, self(), poll),
    {ok, State}.

info(State) ->
    Kept = with([status, frames, last_region, hdmi, shown, pushes, lease], State),
    Kept#{
        width => coproc_deck_scanout:width(),
        height => coproc_deck_scanout:height(),
        region => kind(maps:get(region, State)),
        panel => kind(maps:get(panel, State))
    }.

kind({file, _Path, _Fd}) -> file;
kind(board) -> board;
kind({error, _} = Error) -> Error.

set_status(Text, State0) ->
    State = State0#{status := Text, overlay := coproc_deck_scanout:overlay(Text)},
    {ok, push(coproc_deck_scanout:status_band(), State)}.

%% Elixos's explicit update: push it now, the poll may follow with the same.
flush(Region, #{frames := Frames} = State) ->
    {ok, (push(Region, State))#{frames := Frames + 1, last_region := Region}}.

%% Hardware: nothing to simulate.
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(poll, State0) ->
    State = poll(State0),
    _ = erlang:send_after(?POLL_MS, self(), poll),
    {[], State};
handle_info(_Message, State) ->
    {[], State}.

handoff(State) ->
    coproc_display:handoff(with([status, frames, last_region, hdmi, lease], State)).

%% ---------------------------------------------------------------------------

poll(#{region := {error, _}} = State) ->
    State;
poll(#{region := Region, first := First} = State) ->
    case coproc_deck_scanout:header(read(Region, 0, 48)) of
        invalid ->
            State;
        {ok, Header} ->
            case coproc_deck_scanout:plan(Header, First) of
                idle ->
                    State;
                {push, Rect, Seq} ->
                    Pushed = push(Rect, State),
                    case maps:get(panel, Pushed) of
                        {error, _} ->
                            Pushed;
                        _ ->
                            ok = write_shown(Region, Seq),
                            Pushed#{first := false, shown := Seq, last_region := Rect}
                    end
            end
    end.

push(_Rect, #{panel := {error, _}} = State) ->
    State;
push(_Rect, #{region := {error, _}} = State) ->
    State;
push(Rect, #{region := Region, panel := Panel, overlay := Overlay, pushes := Pushes} = State) ->
    Result = lists:foldl(
        fun
            (Strip, ok) ->
                Pixels = iolist_to_binary([read(Region, Offset, Length)
                                           || {Offset, Length} <- coproc_deck_scanout:rows(Strip)]),
                panel_write(Panel, Strip, coproc_deck_scanout:compose(Strip, Pixels, Overlay));
            (_Strip, Error) ->
                Error
        end,
        ok,
        coproc_deck_scanout:strips(Rect)
    ),
    case Result of
        ok -> State#{pushes := Pushes + 1};
        {error, _} = Error -> State#{panel := Error}
    end.

%% ---------------------------------------------------------------------------
%% The region.

open_region(false) ->
    board;
open_region(Path) ->
    case atomvm:posix_open(Path, [o_rdwr]) of
        {ok, Fd} -> {file, Path, Fd};
        {error, _} = Error -> Error
    end.

read(board, Offset, Length) ->
    coproc_k230:fb_read(Offset, Length);
read({file, _Path, Fd}, Offset, Length) ->
    pread(Fd, Offset, Length, []).

pread(_Fd, _Offset, 0, Acc) ->
    iolist_to_binary(lists:reverse(Acc));
pread(Fd, Offset, Length, Acc) ->
    case atomvm:posix_pread(Fd, Length, Offset) of
        {ok, Chunk} ->
            N = byte_size(Chunk),
            pread(Fd, Offset + N, Length - N, [Chunk | Acc]);
        _EofOrError ->
            % A short region reads as black.
            iolist_to_binary(lists:reverse([binary:copy(<<0>>, Length) | Acc]))
    end.

write_shown(board, Seq) ->
    coproc_k230:fb_write32(coproc_deck_scanout:shown_offset(), Seq);
write_shown({file, _Path, Fd}, Seq) ->
    {ok, 4} = atomvm:posix_pwrite(Fd, <<Seq:32/little>>, coproc_deck_scanout:shown_offset()),
    ok.

%% ---------------------------------------------------------------------------
%% The panel.

open_panel(false) ->
    case coproc_k230:panel_open() of
        ok -> board;
        {error, _} = Error -> Error
    end;
open_panel(Path) ->
    case atomvm:posix_open(Path, [o_rdwr, o_creat], 8#644) of
        {ok, Fd} -> {file, Path, Fd};
        {error, _} = Error -> Error
    end.

panel_write(board, {X, Y, W, H}, Pixels) ->
    coproc_k230:panel_write(X, Y, W, H, Pixels);
panel_write({file, _Path, Fd}, Rect, Pixels) ->
    mirror(Fd, Rect, Pixels).

mirror(Fd, {0, Y, 568, _H}, Pixels) ->
    pwrite(Fd, Pixels, Y * coproc_deck_scanout:stride());
mirror(Fd, {X, Y, W, H}, Pixels) ->
    RowBytes = 2 * W,
    lists:foldl(
        fun
            (R, ok) ->
                pwrite(Fd, binary:part(Pixels, R * RowBytes, RowBytes),
                       (Y + R) * coproc_deck_scanout:stride() + 2 * X);
            (_R, Error) ->
                Error
        end,
        ok,
        lists:seq(0, H - 1)
    ).

pwrite(_Fd, <<>>, _Offset) ->
    ok;
pwrite(Fd, Data, Offset) ->
    case atomvm:posix_pwrite(Fd, Data, Offset) of
        {ok, N} ->
            <<_:N/binary, Rest/binary>> = Data,
            pwrite(Fd, Rest, Offset + N);
        {error, _} = Error ->
            Error
    end.

%% maps:with/2, which AtomVM's maps lacks.
with(Keys, Map) ->
    maps:from_list([{Key, Value} || Key <- Keys, {ok, Value} <- [maps:find(Key, Map)]]).
