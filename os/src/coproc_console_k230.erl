%% The board's console backend (M33, ADR-104): UART3, the second port of
%% the CH342K, through the firmware's NIFs coproc_k230:console_write/1 and
%% console_read/0 (coproc/src/hw.c, platform_nifs.c; the firmware sets
%% UART3 up at boot, coproc/src/uart_k230.c). A line written goes out with a
%% line end (the firmware sends \r\n); typed bytes are polled every ?POLL_MS
%% and each line (ended by \r or \n, empty ones dropped, at most ?MAX_LINE
%% bytes) is reported as {console, Line}.
%%
%% The firmware's own output (AtomVM's standard output) goes to the same
%% UART. REQUIRES THE BOARD's firmware; the host tests give AtomVM's Unix
%% build a coproc_k230 module of their own.
-module(coproc_console_k230).

-behaviour(coproc_driver).
-behaviour(coproc_console).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1, write_line/2]).

-define(POLL_MS, 20).
-define(MAX_LINE, 1024).

init(undefined) ->
    start(#{lines => 0, typed => 0});
init(#{} = Handoff) ->
    start(maps:merge(#{lines => 0, typed => 0}, Handoff)).

start(Kept) ->
    _ = erlang:send_after(?POLL_MS, self(), poll),
    {ok, Kept#{pending => <<>>}}.

info(State) ->
    maps:remove(pending, State).

write_line(Line, #{lines := Lines} = State) ->
    ok = coproc_k230:console_write(<<Line/binary, "\n">>),
    {ok, State#{lines := Lines + 1}}.

%% Hardware: nothing to simulate.
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(poll, #{pending := Pending, typed := Typed} = State) ->
    _ = erlang:send_after(?POLL_MS, self(), poll),
    {Lines, Rest} = lines(<<Pending/binary, (coproc_k230:console_read())/binary>>, <<>>, []),
    Events = [{console, Line} || Line <- Lines],
    {Events, State#{pending := Rest, typed := Typed + length(Events)}};
handle_info(_Message, State) ->
    {[], State}.

handoff(#{lines := Lines, typed := Typed}) ->
    #{lines => Lines, typed => Typed}.

%% Complete lines in order, and what is left of an unfinished one.
lines(<<>>, Line, Acc) ->
    {lists:reverse(Acc), Line};
lines(<<C, Rest/binary>>, Line, Acc) when C =:= $\r; C =:= $\n ->
    lines(Rest, <<>>, line(Line, Acc));
lines(<<C, Rest/binary>>, Line, Acc) when byte_size(Line) + 1 >= ?MAX_LINE ->
    lines(Rest, <<>>, line(<<Line/binary, C>>, Acc));
lines(<<C, Rest/binary>>, Line, Acc) ->
    lines(Rest, <<Line/binary, C>>, Acc).

line(<<>>, Acc) -> Acc;
line(Line, Acc) -> [Line | Acc].
