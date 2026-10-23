%% The board's power backend (M33, ADR-109): the K230 PMU's power key (INT0)
%% and main supply (OUT0), through the firmware's NIFs
%% coproc_k230:power_open/0, power_poll/0 and power_off/0
%% (coproc/src/power_k230.c, platform_nifs.c). This backend polls the key
%% every ?POLL_MS and reports {power_key, pressed | released};
%% poweroff/1 has the PMU drop OUT0, which does not return - if it does, the
%% supply stayed on, which is logged and kept in info/1 (poweroff =>
%% {error, still_on}).
%%
%% REQUIRES THE BOARD's firmware; the host tests give AtomVM's Unix build a
%% coproc_k230 module of their own.
-module(coproc_power_k230).

-behaviour(coproc_driver).
-behaviour(coproc_power).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1, poweroff/1]).

-define(POLL_MS, 10).

init(undefined) ->
    start(#{presses => 0, poweroff => false});
init(#{} = Handoff) ->
    start(maps:merge(#{presses => 0, poweroff => false}, Handoff)).

start(Kept) ->
    Pmu = coproc_k230:power_open(),
    case Pmu of
        ok -> _ = erlang:send_after(0, self(), poll);
        {error, _} -> ok
    end,
    {ok, Kept#{pmu => Pmu}}.

info(State) ->
    State.

poweroff(State) ->
    io:format("power: cutting the main supply~n"),
    Result = coproc_k230:power_off(),
    io:format("power: the supply stayed on: ~p~n", [Result]),
    {ok, State#{poweroff := Result}}.

%% Hardware: nothing to simulate.
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(poll, #{presses := Presses} = State) ->
    _ = erlang:send_after(?POLL_MS, self(), poll),
    case coproc_k230:power_poll() of
        pressed -> {[{power_key, pressed}], State#{presses := Presses + 1}};
        released -> {[{power_key, released}], State};
        _NoneOrError -> {[], State}
    end;
handle_info(_Message, State) ->
    {[], State}.

handoff(#{presses := Presses}) ->
    #{presses => Presses}.
