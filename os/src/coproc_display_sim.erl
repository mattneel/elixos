%% Simulated display unit for AtomVM's Unix build: records what it was asked
%% to show instead of driving DSI. HDMI hotplug is a stimulus. A lapsed
%% lease's status (coproc_display) is recorded as any other status.
-module(coproc_display_sim).

-behaviour(coproc_driver).
-behaviour(coproc_display).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1, set_status/2, flush/2]).

init(undefined) ->
    {ok, #{status => <<>>, frames => 0, last_region => none, hdmi => disconnected}};
init(#{} = Handoff) ->
    {ok, coproc_display:restored(Handoff)}.

info(State) ->
    State#{width => 568, height => 1232}.

set_status(Text, State) ->
    io:format("display: status ~s~n", [Text]),
    {ok, State#{status := Text}}.

flush(Region, #{frames := Frames} = State) ->
    {ok, State#{frames := Frames + 1, last_region := Region}}.

simulate({hdmi, Hdmi}, State) when Hdmi =:= connected; Hdmi =:= disconnected ->
    {ok, [{display, {hdmi, Hdmi}}], State#{hdmi := Hdmi}};
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(_Message, State) ->
    {[], State}.

handoff(State) ->
    coproc_display:handoff(State).
