%% Simulated SX1262: every transmitted packet is heard back (loopback), and
%% {receive, Packet, Meta} stimuli are packets from the air.
-module(coproc_lora_sim).

-behaviour(coproc_driver).
-behaviour(coproc_lora).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1, transmit/2]).

init(undefined) -> {ok, #{sent => 0, received => 0}};
init(#{} = Handoff) -> {ok, Handoff}.

info(State) ->
    State.

transmit(Packet, #{sent := Sent, received := Received} = State) ->
    Meta = #{rssi => -30, snr => 10, loopback => true},
    {ok, [{lora, Packet, Meta}], State#{sent := Sent + 1, received := Received + 1}}.

simulate({'receive', Packet, Meta}, #{received := Received} = State) when
    is_binary(Packet), is_map(Meta)
->
    Full = maps:merge(#{rssi => -90, snr => 5}, Meta),
    {ok, [{lora, Packet, Full}], State#{received := Received + 1}};
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(_Message, State) ->
    {[], State}.

handoff(State) ->
    State.
