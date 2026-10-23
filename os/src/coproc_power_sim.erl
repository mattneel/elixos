%% Simulated PMU: records a power-off request instead of dropping OUT0, and
%% takes {key, pressed | released} stimuli.
-module(coproc_power_sim).

-behaviour(coproc_driver).
-behaviour(coproc_power).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1, poweroff/1]).

init(undefined) -> {ok, #{poweroff => false, presses => 0}};
init(#{} = Handoff) -> {ok, Handoff}.

info(State) ->
    State.

poweroff(State) ->
    io:format("power: poweroff requested~n"),
    {ok, State#{poweroff := true}}.

simulate({key, pressed}, #{presses := Presses} = State) ->
    {ok, [{power_key, pressed}], State#{presses := Presses + 1}};
simulate({key, released}, State) ->
    {ok, [{power_key, released}], State};
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(_Message, State) ->
    {[], State}.

handoff(State) ->
    State.
