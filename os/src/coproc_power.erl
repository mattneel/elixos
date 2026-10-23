%% Power (ADR-109): the K230 PMU's power key (INT0) and main-supply enable
%% (OUT0). The key is an event to subscribers:
%%
%%   {power_key, pressed | released}
%%
%% poweroff/0 is the last step of Elixos.poweroff/0 on the deck, after Linux
%% has synced and stopped: the board backend drops OUT0 and does not return.
-module(coproc_power).

-export([poweroff/0, info/0, request/3]).

%% Cuts the main supply.
-callback poweroff(State :: term()) -> {ok, State :: term()}.

poweroff() ->
    coproc_driver:request(?MODULE, poweroff).

info() ->
    coproc_driver:info(?MODULE).

request(poweroff, Backend, State0) ->
    {ok, State} = Backend:poweroff(State0),
    {reply, ok, [], State};
request(_Request, _Backend, State) ->
    {reply, {error, badarg}, [], State}.
