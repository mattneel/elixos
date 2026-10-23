%% The board's touch backend (M33, ADR-106): the GT9895 on I2C3, through the
%% firmware's NIFs coproc_k230:touch_open/0 and touch_read/0
%% (coproc/src/touch_k230.c, platform_nifs.c). The firmware powers, resets
%% and checks the controller once per boot and turns its reports into
%% {down | move | up, X, Y} in panel coordinates (568 x 1232); this backend
%% polls it every ?POLL_MS and reports each as {touch, Action, X, Y}.
%%
%% A controller that cannot be opened leaves the backend idle; info/1
%% reports touch => {error, Reason}. REQUIRES THE BOARD's firmware; the host
%% tests give AtomVM's Unix build a coproc_k230 module of their own.
-module(coproc_touch_k230).

-behaviour(coproc_driver).

-export([init/1, info/1, simulate/2, handle_info/2, handoff/1]).

-define(POLL_MS, 20).

init(undefined) ->
    start(#{touches => 0, errors => 0});
init(#{} = Handoff) ->
    start(maps:merge(#{touches => 0, errors => 0}, Handoff)).

start(Kept) ->
    Touch = coproc_k230:touch_open(),
    case Touch of
        ok -> _ = erlang:send_after(0, self(), poll);
        {error, _} -> ok
    end,
    {ok, Kept#{touch => Touch}}.

info(State) ->
    State.

%% Hardware: nothing to simulate.
simulate(_Stimulus, State) ->
    {{error, badarg}, [], State}.

handle_info(poll, #{touches := Touches, errors := Errors} = State) ->
    _ = erlang:send_after(?POLL_MS, self(), poll),
    case coproc_k230:touch_read() of
        Reports when is_list(Reports) ->
            Events = [{touch, Action, X, Y} || {Action, X, Y} <- Reports, coproc_touch:valid(Action, X, Y)],
            {Events, State#{touches := Touches + length(Events)}};
        {error, _} ->
            {[], State#{errors := Errors + 1}}
    end;
handle_info(_Message, State) ->
    {[], State}.

handoff(#{touches := Touches, errors := Errors}) ->
    #{touches => Touches, errors => Errors}.
