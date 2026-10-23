%% The board's LoRa backend (M33, ADR-107): the SX1262 module on QSPI0,
%% through the firmware's NIFs coproc_k230:lora_open/1, lora_send/1 and
%% lora_poll/0 (coproc/src/lora_k230.c, platform_nifs.c). The firmware brings
%% the radio up with LilyGO's SX1262 configuration (LoRa, 125 kHz, SF10,
%% CR 4/6, sync word 0x12, 22 dBm, preamble 16, no CRC) on the configured
%% frequency and keeps it receiving; this backend polls it every ?POLL_MS and
%% reports each packet as
%%
%%   {lora, Packet, #{rssi := Dbm, snr := Db}}
%%
%% Configuration (the payload's environment): ELIXOS_COPROC_LORA_FREQUENCY,
%% in Hz, default 915000000 (LilyGO's SX1262 build; the 433, 868 and 923 MHz
%% SKUs need theirs). A send starts the transmission and returns; the radio
%% is back to receiving once the firmware reports it sent, and a send before
%% that is {error, busy}.
%%
%% A radio that cannot be opened leaves the backend idle and every send
%% answers {error, not_open}; info/1 reports lora => {error, Reason}. REQUIRES
%% THE BOARD's firmware; the host tests give AtomVM's Unix build a
%% coproc_k230 module of their own.
-module(coproc_lora_k230).

-behaviour(coproc_driver).
-behaviour(coproc_lora).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1, transmit/2]).

-define(POLL_MS, 20).
-define(DEFAULT_FREQUENCY, 915000000).

-define(COUNTERS, #{sent => 0, received => 0, crc_errors => 0, errors => 0}).

init(undefined) ->
    start(?COUNTERS);
init(#{} = Handoff) ->
    start(maps:merge(?COUNTERS, Handoff)).

start(Kept) ->
    Frequency = frequency(os:getenv("ELIXOS_COPROC_LORA_FREQUENCY")),
    Lora =
        case Frequency of
            {error, _} = Error -> Error;
            Hz -> coproc_k230:lora_open(Hz)
        end,
    case Lora of
        ok -> _ = erlang:send_after(0, self(), poll);
        {error, _} -> ok
    end,
    {ok, Kept#{lora => Lora, frequency => Frequency}}.

frequency(false) ->
    ?DEFAULT_FREQUENCY;
frequency(Text) ->
    try list_to_integer(Text) of
        Hz when Hz > 0 -> Hz;
        _ -> {error, {bad_frequency, Text}}
    catch
        error:badarg -> {error, {bad_frequency, Text}}
    end.

info(State) ->
    State.

transmit(Packet, #{lora := ok} = State) ->
    case coproc_k230:lora_send(Packet) of
        ok -> {ok, [], State};
        {error, _} = Error -> {Error, State}
    end;
transmit(_Packet, State) ->
    {{error, not_open}, State}.

%% Hardware: nothing to simulate.
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(poll, State) ->
    _ = erlang:send_after(?POLL_MS, self(), poll),
    poll(coproc_k230:lora_poll(), State);
handle_info(_Message, State) ->
    {[], State}.

handoff(State) ->
    maps:from_list([{Key, maps:get(Key, State)} || Key <- maps:keys(?COUNTERS)]).

poll(none, State) ->
    {[], State};
poll(sent, #{sent := Sent} = State) ->
    {[], State#{sent := Sent + 1}};
poll(crc_error, #{crc_errors := Errors} = State) ->
    {[], State#{crc_errors := Errors + 1}};
poll({packet, Packet, Rssi, SnrQuarters}, #{received := Received} = State) ->
    {[{lora, Packet, #{rssi => Rssi, snr => SnrQuarters / 4}}], State#{received := Received + 1}};
poll({error, _}, #{errors := Errors} = State) ->
    {[], State#{errors := Errors + 1}}.
