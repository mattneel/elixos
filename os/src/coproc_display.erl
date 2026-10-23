%% The display unit (ADR-106): the RM69A10 AMOLED (568x1232, MIPI DSI) and
%% the LT9611 HDMI bridge on the same lanes. Elixos renders into a
%% shared-memory framebuffer and tells this driver which region changed; the
%% board backend scans it out to the panel. The driver also holds the status
%% line the coprocessor shows on its own while the big core's BEAM restarts
%% (M33). Both outlive Elixos: the panel keeps the last frame and status.
%%
%% The lease (M33): while Elixos runs, its deck renews a lease every few
%% seconds with lease(TtlMs, Text), Text being what it knows of itself (the
%% generation and boot attempt). When a lease is not renewed within TtlMs,
%% Elixos is away - its BEAM crashed, hangs or restarts - and the driver
%% shows its own status over the last frame:
%%
%%     Elixos restarting, was <Text>
%%
%% The next renewal clears it (and so does the first lease after the driver
%% starts, which clears whatever status the backend showed until then). The
%% lease lives in the backend's state, which is therefore a map for every
%% display backend; its key `lease` belongs to this module. The lapse timer
%% message comes back through coproc_driver as {coproc_subsystem, _}. A
%% backend that is handed state across a VM restart calls restored/1 from its
%% init/1, so a lease that was running lapses in the new VM as well.
%%
%% Events: {display, {hdmi, connected | disconnected}}.
-module(coproc_display).

-export([status/1, update/1, lease/2, info/0, request/3, handle_info/3, handoff/1, restored/1, lapsed_text/1]).

-define(WIDTH, 568).
-define(HEIGHT, 1232).

%% Shows Text as the coprocessor's status line (<<>> clears it).
-callback set_status(Text :: binary(), State :: map()) -> {ok, State :: map()}.
%% Scans out Region {X, Y, Width, Height} of the shared framebuffer.
-callback flush(Region :: {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()},
                State :: map()) -> {ok, State :: map()}.

status(Text) ->
    coproc_driver:request(?MODULE, {status, Text}).

update(Region) ->
    coproc_driver:request(?MODULE, {update, Region}).

%% Elixos is here for another TtlMs milliseconds; Text says who it is.
lease(TtlMs, Text) ->
    coproc_driver:request(?MODULE, {lease, TtlMs, Text}).

info() ->
    coproc_driver:info(?MODULE).

%% The status shown when a lease lapses.
lapsed_text(Text) ->
    <<"Elixos restarting, was ", Text/binary>>.

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
request({lease, Ttl, Text}, Backend, State0) when is_integer(Ttl), Ttl > 0, is_binary(Text) ->
    State1 =
        case maps:get(lease, State0, none) of
            #{lapsed := false} ->
                State0;
            _NoneOrLapsed ->
                {ok, Cleared} = Backend:set_status(<<>>, State0),
                Cleared
        end,
    Lease = arm(#{text => Text, ttl => Ttl, lapsed => false}),
    {reply, ok, [], State1#{lease => Lease}};
request(_Request, _Backend, State) ->
    {reply, {error, badarg}, [], State}.

%% The lapse timer. A renewal made a new reference, so only the latest
%% lease's timer counts.
handle_info({lease_lapsed, Ref}, Backend, #{lease := #{ref := Ref, lapsed := false, text := Text} = Lease} = State0) ->
    {ok, State} = Backend:set_status(lapsed_text(Text), State0),
    {[], State#{lease := Lease#{lapsed := true}}};
handle_info(_Message, _Backend, State) ->
    {[], State}.

%% What a backend hands to the next VM (its handoff/1 calls this): the lease
%% without its timer reference, which means nothing there.
handoff(#{lease := Lease} = State) ->
    State#{lease := maps:remove(ref, Lease)};
handoff(State) ->
    State.

%% A backend's state handed over from the previous VM (its init/1 calls
%% this): the timer is gone, so a running lease gets a fresh one with its full
%% TTL.
restored(#{lease := #{lapsed := false} = Lease} = State) ->
    State#{lease := arm(Lease)};
restored(State) ->
    State.

arm(#{ttl := Ttl} = Lease) ->
    Ref = make_ref(),
    _ = erlang:send_after(Ttl, self(), {coproc_subsystem, {lease_lapsed, Ref}}),
    Lease#{ref => Ref}.
