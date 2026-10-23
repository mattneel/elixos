%% Simulated UART3: AtomVM's standard output stands in for the wire, each
%% line prefixed "uart3: ". {input, Line} stimuli are lines typed into it.
-module(coproc_console_sim).

-behaviour(coproc_driver).
-behaviour(coproc_console).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1, write_line/2]).

init(undefined) -> {ok, #{lines => 0}};
init(#{} = Handoff) -> {ok, Handoff}.

info(State) ->
    State.

write_line(Line, #{lines := Lines} = State) ->
    io:format("uart3: ~s~n", [Line]),
    {ok, State#{lines := Lines + 1}}.

simulate({input, Line}, State) when is_binary(Line) ->
    {ok, [{console, Line}], State};
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(_Message, State) ->
    {[], State}.

handoff(State) ->
    State.
