%% Touch (ADR-106): the GT9895 controller on I2C3, part of the display unit.
%% A touch is an event to subscribers:
%%
%%   {touch, down | move | up, X, Y}
%%
%% in panel coordinates (568x1232). The board backend reads the controller on
%% its interrupt (IO23); the simulated one takes touches as stimuli.
-module(coproc_touch).

-export([info/0, request/3, valid/3]).

info() ->
    coproc_driver:info(?MODULE).

%% Touch has no requests: it only reports.
request(_Request, _Backend, State) ->
    {reply, {error, badarg}, [], State}.

%% Whether {Action, X, Y} is a touch on the panel.
valid(Action, X, Y) ->
    (Action =:= down orelse Action =:= move orelse Action =:= up) andalso
        is_integer(X) andalso is_integer(Y) andalso
        X >= 0 andalso X < 568 andalso Y >= 0 andalso Y < 1232.
