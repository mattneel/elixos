%% Simulated touch controller: {Action, X, Y} stimuli become touch events.
-module(coproc_touch_sim).

-behaviour(coproc_driver).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1]).

init(undefined) -> {ok, #{touches => 0}};
init(#{} = Handoff) -> {ok, Handoff}.

info(State) ->
    State.

simulate({Action, X, Y}, #{touches := Touches} = State) ->
    case coproc_touch:valid(Action, X, Y) of
        true -> {ok, [{touch, Action, X, Y}], State#{touches := Touches + 1}};
        false -> {{error, badarg}, [], State}
    end;
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(_Message, State) ->
    {[], State}.

handoff(State) ->
    State.
