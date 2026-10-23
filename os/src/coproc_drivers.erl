%% The coprocessor's drivers (M32): one coproc_driver process per subsystem,
%% registered under its subsystem module's name, under one supervisor. The
%% runtime (elixos_coproc) starts them before distribution, so they run
%% whether or not Elixos is connected.
%%
%% The backend set picks the implementation of every driver: the backend of
%% subsystem coproc_X in set S is the module coproc_X_S. AtomVM's Unix build
%% on the host runs set sim; the board's set replaces it (M32 board work).
%% A set is an atom for every subsystem, or a map from subsystem name to set
%% with a `default` (ELIXOS_COPROC_DRIVERS=sim,display=k230: the board's
%% display backend, the others simulated until their board backends exist).
-module(coproc_drivers).

-behaviour(supervisor).

-export([start_link/1, names/0, pids/0, handoff/0, restore/1]).
-export([init/1]).

-define(NAMES, [coproc_console, coproc_display, coproc_touch, coproc_lora, coproc_power]).

start_link(Set) when is_atom(Set); is_map(Set) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, Set).

names() ->
    ?NAMES.

%% Every driver's pid (undefined while one restarts).
pids() ->
    maps:from_list([{Name, whereis(Name)} || Name <- ?NAMES]).

%% Every driver's state worth keeping across a VM restart.
handoff() ->
    maps:from_list([{Name, coproc_driver:handoff(Name)} || Name <- ?NAMES, whereis(Name) =/= undefined]).

%% Gives each driver the state handoff/0 returned before the VM restarted.
%% Done once, right after start_link/1 and before distribution: a driver the
%% supervisor restarts later starts afresh.
restore(Handoff) when is_map(Handoff) ->
    maps:foreach(
        fun(Name, State) ->
            case lists:member(Name, ?NAMES) of
                true -> ok = coproc_driver:restore(Name, State);
                false -> ok
            end
        end,
        Handoff
    ).

init(Set) ->
    Children = [
        #{
            id => Name,
            start => {coproc_driver, start_link, [Name, Name, backend(Name, Set)]},
            restart => permanent,
            shutdown => 1000,
            type => worker
        }
     || Name <- ?NAMES
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.

backend(Name, Sets) when is_map(Sets) ->
    backend(Name, maps:get(Name, Sets, maps:get(default, Sets, sim)));
backend(Name, Set) ->
    list_to_atom(atom_to_list(Name) ++ "_" ++ atom_to_list(Set)).
