%% The display unit (ADR-106): the RM69A10 AMOLED (568x1232, MIPI DSI) and
%% the LT9611 HDMI bridge on the same lanes. Elixos renders into a
%% shared-memory framebuffer and tells this driver which region changed; the
%% board backend scans it out to the panel. The driver also holds the status
%% line the coprocessor shows on its own while the big core's BEAM restarts
%% (M33). Both outlive Elixos: the panel keeps the last frame and status.
%%
%% Events: {display, {hdmi, connected | disconnected}}.
-module(coproc_display).

-export([status/1, update/1, info/0, request/3]).

-define(WIDTH, 568).
-define(HEIGHT, 1232).

%% Shows Text as the coprocessor's status line.
-callback set_status(Text :: binary(), State :: term()) -> {ok, State :: term()}.
%% Scans out Region {X, Y, Width, Height} of the shared framebuffer.
-callback flush(Region :: {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()},
                State :: term()) -> {ok, State :: term()}.

status(Text) ->
    coproc_driver:request(?MODULE, {status, Text}).

update(Region) ->
    coproc_driver:request(?MODULE, {update, Region}).

info() ->
    coproc_driver:info(?MODULE).

request({status, Text}, Backend, State0) when is_binary(Text) ->
    {ok, State} = Backend:set_status(Text, State0),
    {reply, ok, [], State};
request({update, {X, Y, W, H} = Region}, Backend, State0) when
    is_integer(X), is_integer(Y), is_integer(W), is_integer(H),
    X >= 0, Y >= 0, W > 0, H > 0, X + W =< ?WIDTH, Y + H =< ?HEIGHT
->
    {ok, State} = Backend:flush(Region, State0),
    {reply, ok, [], State};
request({update, _Region}, _Backend, State) ->
    {reply, {error, out_of_bounds}, [], State};
request(_Request, _Backend, State) ->
    {reply, {error, badarg}, [], State}.
