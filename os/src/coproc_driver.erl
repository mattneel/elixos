%% A coprocessor driver (M32): the process behind one subsystem the M30 gate
%% gave the coprocessor (UART3 console ADR-104; panel, touch and HDMI
%% ADR-106; LoRa ADR-107; power key and power-off ADR-109). It runs on
%% AtomVM, is started by the coprocessor runtime at boot (coproc_drivers) and
%% does not depend on Elixos being connected.
%%
%% Three modules make a driver:
%%
%%   * this one, the generic process: registration, requests, subscribers and
%%     the event queue;
%%   * the subsystem module (coproc_display, coproc_lora, ...): its public API,
%%     the requests it accepts, and the behaviour its backends implement;
%%   * a backend (coproc_lora_sim, later coproc_lora_k230): the hardware, or a
%%     simulation of it. A backend implements this module's callbacks and its
%%     subsystem's.
%%
%% A subsystem that keeps its own timers (the display's lease, M33) sends
%% itself {coproc_subsystem, Message}; the driver hands that to
%% Subsystem:handle_info(Message, Backend, BackendState), not to the backend.
%%
%% Events and subscribers. A backend reports what happened (a packet came in,
%% the screen was touched) as event terms; each gets the next sequence number
%% and goes into a queue of at most ?LIMIT events (the oldest is dropped and
%% counted), and to every subscriber as
%%
%%   {coproc_event, Name, DriverPid, Seq, Event}
%%
%% An event leaves the queue when a subscriber acknowledges it
%% (gen_server:cast(DriverPid, {ack, Seq}) acknowledges everything up to Seq).
%% A new subscriber first gets every queued event. So nothing is lost while
%% Elixos is away: AtomVM does not signal links or monitors when a
%% distribution connection closes, so the driver cannot tell that a remote
%% subscriber is gone, and does not need to - unacknowledged events are sent
%% again when Elixos subscribes after it comes back.
%%
%% A remote node has one subscription: subscribing replaces that node's
%% previous subscriber (a restarted Elixos has a new pid). Local subscribers
%% (code in the coprocessor's bundle) are monitored and may be many.
-module(coproc_driver).

-behaviour(gen_server).

-export([
    start_link/3,
    request/2,
    simulate/2,
    info/1,
    subscribe/2,
    unsubscribe/2,
    handoff/1,
    restore/2
]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% A backend starts from undefined, and is started again from the state its
%% predecessor handed off across a VM restart (handoff/1, restore/2).
-callback init(Handoff :: term()) -> {ok, State :: term()}.
%% What the backend reports about the subsystem.
-callback info(State :: term()) -> map().
%% A stimulus from the outside world. Simulated backends turn it into events
%% (a touch, a received packet); hardware backends refuse it.
-callback simulate(Stimulus :: term(), State :: term()) ->
    {Reply :: term(), Events :: [term()], State :: term()}.
%% Any other message the process receives: interrupts, timers, ports.
-callback handle_info(Message :: term(), State :: term()) ->
    {Events :: [term()], State :: term()}.
%% The state worth keeping across a VM restart (a bundle deploy).
-callback handoff(State :: term()) -> term().

-define(LIMIT, 64).
-define(TIMEOUT, 5000).

start_link(Name, Subsystem, Backend) ->
    gen_server:start_link({local, Name}, ?MODULE, {Name, Subsystem, Backend}, []).

%% A subsystem request, answered by Subsystem:request/3.
request(Name, Request) ->
    gen_server:call(Name, {request, Request}, ?TIMEOUT).

simulate(Name, Stimulus) ->
    gen_server:call(Name, {simulate, Stimulus}, ?TIMEOUT).

info(Name) ->
    gen_server:call(Name, info, ?TIMEOUT).

%% Returns {ok, DriverPid}: acknowledgements go to that pid.
subscribe(Name, Pid) when is_pid(Pid) ->
    gen_server:call(Name, {subscribe, Pid}, ?TIMEOUT).

unsubscribe(Name, Pid) when is_pid(Pid) ->
    gen_server:call(Name, {unsubscribe, Pid}, ?TIMEOUT).

handoff(Name) ->
    gen_server:call(Name, handoff, ?TIMEOUT).

%% Takes over a predecessor's handoff/1 state: its queue, its sequence
%% numbers and its backend's state.
restore(Name, Handoff) ->
    gen_server:call(Name, {restore, Handoff}, ?TIMEOUT).

init({Name, Subsystem, Backend}) ->
    {ok, BState} = Backend:init(undefined),
    {ok, #{
        name => Name,
        subsystem => Subsystem,
        backend => Backend,
        bstate => BState,
        seq => 0,
        queue => [],
        dropped => 0,
        subscribers => #{}
    }}.

handle_call({restore, #{seq := Seq, queue := Queue, dropped := Dropped, backend := Handoff}}, _From,
            #{backend := Backend} = State) ->
    {ok, BState} = Backend:init(Handoff),
    {reply, ok, State#{bstate := BState, seq := Seq, queue := Queue, dropped := Dropped}};
handle_call({request, Request}, _From, #{subsystem := Subsystem, backend := Backend, bstate := S0} = State) ->
    {reply, Reply, Events, S} = Subsystem:request(Request, Backend, S0),
    {reply, Reply, emit(Events, State#{bstate := S})};
handle_call({simulate, Stimulus}, _From, #{backend := Backend, bstate := S0} = State) ->
    {Reply, Events, S} = Backend:simulate(Stimulus, S0),
    {reply, Reply, emit(Events, State#{bstate := S})};
handle_call(info, _From, #{backend := Backend, bstate := S} = State) ->
    #{queue := Queue, seq := Seq, dropped := Dropped, subscribers := Subscribers} = State,
    Info = maps:merge(Backend:info(S), #{
        pid => self(),
        backend => Backend,
        seq => Seq,
        pending => length(Queue),
        dropped => Dropped,
        subscribers => maps:values(Subscribers)
    }),
    {reply, Info, State};
handle_call({subscribe, Pid}, _From, #{subscribers := Subscribers, queue := Queue} = State) ->
    Key = key(Pid),
    case {Key, maps:is_key(Key, Subscribers)} of
        {{local, _}, false} -> erlang:monitor(process, Pid);
        _ -> ok
    end,
    lists:foreach(fun({Seq, Event}) -> deliver(Pid, Seq, Event, State) end, Queue),
    {reply, {ok, self()}, State#{subscribers := Subscribers#{Key => Pid}}};
handle_call({unsubscribe, Pid}, _From, #{subscribers := Subscribers} = State) ->
    {reply, ok, State#{subscribers := drop(Pid, Subscribers)}};
handle_call(handoff, _From, #{backend := Backend, bstate := S} = State) ->
    #{seq := Seq, queue := Queue, dropped := Dropped} = State,
    {reply, #{seq => Seq, queue => Queue, dropped => Dropped, backend => Backend:handoff(S)}, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({ack, Seq}, #{queue := Queue} = State) when is_integer(Seq) ->
    {noreply, State#{queue := [Entry || {S, _} = Entry <- Queue, S > Seq]}};
handle_cast(_Message, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #{subscribers := Subscribers} = State) ->
    {noreply, State#{subscribers := drop(Pid, Subscribers)}};
handle_info({coproc_subsystem, Message}, #{subsystem := Subsystem, backend := Backend, bstate := S0} = State) ->
    {Events, S} = Subsystem:handle_info(Message, Backend, S0),
    {noreply, emit(Events, State#{bstate := S})};
handle_info(Message, #{backend := Backend, bstate := S0} = State) ->
    {Events, S} = Backend:handle_info(Message, S0),
    {noreply, emit(Events, State#{bstate := S})}.

terminate(_Reason, _State) ->
    ok.

emit([], State) ->
    State;
emit([Event | Rest], #{seq := Seq0, queue := Queue, dropped := Dropped, subscribers := Subscribers} = State) ->
    Seq = Seq0 + 1,
    maps:foreach(fun(_Key, Pid) -> deliver(Pid, Seq, Event, State) end, Subscribers),
    {Queue1, Dropped1} = trim(Queue ++ [{Seq, Event}], Dropped),
    emit(Rest, State#{seq := Seq, queue := Queue1, dropped := Dropped1}).

trim(Queue, Dropped) when length(Queue) > ?LIMIT -> trim(tl(Queue), Dropped + 1);
trim(Queue, Dropped) -> {Queue, Dropped}.

deliver(Pid, Seq, Event, #{name := Name}) ->
    Pid ! {coproc_event, Name, self(), Seq, Event},
    ok.

key(Pid) when node(Pid) =:= node() -> {local, Pid};
key(Pid) -> {node, node(Pid)}.

drop(Pid, Subscribers) ->
    maps:filter(fun(_Key, Subscriber) -> Subscriber =/= Pid end, Subscribers).
