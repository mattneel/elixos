%% LoRa (ADR-107): the SX1262 on SPI. Sending is a call; a received packet is
%% an event to subscribers:
%%
%%   {lora, Packet :: binary(), Meta :: #{rssi := integer(), snr := number()}}
%%
%% Packets queue in the driver while nobody is subscribed (coproc_driver), so
%% the radio keeps receiving while the big core's BEAM restarts.
-module(coproc_lora).

-export([send/1, info/0, request/3]).

%% The SX1262's payload limit.
-define(MAX_PACKET, 255).

%% Transmits Packet. Events it causes (the simulation's loopback) are
%% reported like any received packet.
-callback transmit(Packet :: binary(), State :: term()) ->
    {ok, Events :: [term()], State :: term()} | {{error, term()}, State :: term()}.

send(Packet) ->
    coproc_driver:request(?MODULE, {send, Packet}).

info() ->
    coproc_driver:info(?MODULE).

request({send, Packet}, Backend, State0) when
    is_binary(Packet), byte_size(Packet) > 0, byte_size(Packet) =< ?MAX_PACKET
->
    case Backend:transmit(Packet, State0) of
        {ok, Events, State} -> {reply, ok, Events, State};
        {{error, _} = Error, State} -> {reply, Error, [], State}
    end;
request({send, _Packet}, _Backend, State) ->
    {reply, {error, badarg}, [], State};
request(_Request, _Backend, State) ->
    {reply, {error, badarg}, [], State}.
