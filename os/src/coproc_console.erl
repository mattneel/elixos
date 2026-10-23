%% The coprocessor's console (ADR-104): UART3, channel 1 of the CH342K. Lines
%% written here go out on it; lines typed into it are events to subscribers:
%%
%%   {console, Line :: binary()}
-module(coproc_console).

-export([write/1, info/0, request/3]).

%% Writes Line, and a line end, to the UART.
-callback write_line(Line :: binary(), State :: term()) -> {ok, State :: term()}.

write(Line) ->
    coproc_driver:request(?MODULE, {write, Line}).

info() ->
    coproc_driver:info(?MODULE).

request({write, Line}, Backend, State0) when is_binary(Line) ->
    {ok, State} = Backend:write_line(Line, State0),
    {reply, ok, [], State};
request(_Request, _Backend, State) ->
    {reply, {error, badarg}, [], State}.
