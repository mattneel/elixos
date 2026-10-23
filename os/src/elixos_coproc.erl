%% The coprocessor runtime (M29, ADR-098): the start module of the archive a
%% coprocessor's AtomVM boots. Elixos packs it from its own compiled code
%% (Elixos.Coproc.runtime/0); it runs only on AtomVM, never on the BEAM.
%%
%% It joins Elixos over Erlang distribution and owns the coprocessor's bundle:
%% the .avm of user modules a generation carries (ADR-099). The bundle lives in
%% a file; at start it is added to the code path, and deploy/1 replaces it and
%% ends the VM (start/0 returns: AtomVM has no halt), so it restarts on the new
%% code - on the host the launcher restarts AtomVM, on hardware whatever loaded
%% the coprocessor does.
%%
%% It also starts the coprocessor's drivers (M32, coproc_drivers) before
%% distribution: they run whether Elixos is connected or not. They are part
%% of this runtime, not of the bundle, so a generation switch that keeps the
%% bundle never touches them. A deploy ends the VM and the drivers with it;
%% their state (queued events, the display's status and last frame) is handed
%% to the next VM in <bundle>.drivers and restored before distribution starts.
%%
%% Configuration comes from the environment (the host stand-in's launcher sets
%% it; the cookie is read from a file, never passed in the environment):
%%
%%   ELIXOS_COPROC_NODE         this node's name, e.g. coproc@10.0.3.2
%%   ELIXOS_COPROC_PORT         the fixed distribution port to listen on
%%   ELIXOS_COPROC_COOKIE_FILE  file holding the shared cookie
%%   ELIXOS_COPROC_BUNDLE       the bundle file (absent means no bundle)
%%   ELIXOS_COPROC_DRIVERS      the drivers' backend set (default sim)
%%
%% AtomVM's distribution always registers with an epmd on 127.0.0.1:4369 and
%% binds 0.0.0.0, so the runtime starts AtomVM's own Erlang epmd first. Elixos
%% never asks epmd: it dials the fixed port (Elixos.Coproc.Epmd), and is
%% always the side that connects.
-module(elixos_coproc).

-export([start/0, digest/0, deploy/1]).

-define(SERVER, elixos_coproc).
-define(HEADER, "#!/usr/bin/env AtomVM\n").

start() ->
    Node = list_to_atom(env("ELIXOS_COPROC_NODE")),
    Port = list_to_integer(env("ELIXOS_COPROC_PORT")),
    Cookie = trim(read_file(env("ELIXOS_COPROC_COOKIE_FILE"))),
    BundlePath = env("ELIXOS_COPROC_BUNDLE"),
    Digest = load_bundle(BundlePath),
    {ok, _} = coproc_drivers:start_link(driver_set()),
    ok = coproc_drivers:restore(take_handoff(BundlePath)),
    % A host epmd may already own 4369: then AtomVM's own epmd (started
    % unlinked, as its start_link/1 would take this process down with it)
    % fails to bind, and registering with the host's works as well.
    _ = gen_server:start({local, epmd}, epmd, [], []),
    {ok, _} = net_kernel:start(Node, #{
        name_domain => longnames,
        avm_dist_opts => #{listen_port_min => Port, listen_port_max => Port}
    }),
    ok = net_kernel:set_cookie(Cookie),
    true = register(?SERVER, self()),
    io:format("elixos_coproc: ~s up, bundle ~s~n", [Node, show(Digest)]),
    loop(#{path => BundlePath, digest => Digest}).

%% The sha256 of the running bundle, lowercase hex, or none.
digest() ->
    call(digest).

%% Replaces the bundle (none removes it), then ends the VM so it restarts on
%% it. Returns ok before that: the reply leaves first.
deploy(none) ->
    call({deploy, none});
deploy(Bundle) when is_binary(Bundle) ->
    case Bundle of
        <<?HEADER, 0, 0, _/binary>> -> call({deploy, Bundle});
        _ -> {error, invalid_bundle}
    end.

call(Request) ->
    Ref = make_ref(),
    ?SERVER ! {Request, self(), Ref},
    receive
        {Ref, Reply} -> Reply
    after 30000 -> {error, timeout}
    end.

loop(#{path := Path, digest := Digest} = State) ->
    receive
        {digest, From, Ref} ->
            From ! {Ref, Digest},
            loop(State);
        {{deploy, Bundle}, From, Ref} ->
            case store(Path, Bundle) of
                ok ->
                    Handoff = save_handoff(Path),
                    From ! {Ref, ok},
                    io:format("elixos_coproc: bundle ~s deployed, restarting (drivers ~s)~n", [
                        show(digest_of(Bundle)), Handoff
                    ]),
                    % Let the reply cross the link before the VM goes away.
                    % AtomVM has no erlang:halt/0,1: the VM ends when its
                    % start process returns, so start/0 returns here.
                    receive
                    after 200 -> ok
                    end;
                {error, _} = Error ->
                    From ! {Ref, Error},
                    loop(State)
            end
    end.

driver_set() ->
    case os:getenv("ELIXOS_COPROC_DRIVERS") of
        false -> sim;
        Set -> list_to_atom(Set)
    end.

%% The drivers' state for the next VM, next to the bundle. A failure costs the
%% state, never the deploy.
save_handoff(BundlePath) ->
    try write_file(BundlePath ++ ".drivers", term_to_binary(coproc_drivers:handoff())) of
        ok -> <<"handed off">>;
        {error, _} -> <<"not handed off">>
    catch
        _:_ -> <<"not handed off">>
    end.

%% What the previous VM handed off, read once.
take_handoff(BundlePath) ->
    Path = BundlePath ++ ".drivers",
    case read_file(Path) of
        <<>> ->
            #{};
        Binary ->
            _ = atomvm:posix_unlink(Path),
            try binary_to_term(Binary) of
                #{} = Handoff -> Handoff;
                _ -> #{}
            catch
                _:_ -> #{}
            end
    end.

load_bundle(Path) ->
    case read_file(Path) of
        <<>> ->
            none;
        Bundle ->
            ok = atomvm:add_avm_pack_binary(Bundle, [{name, elixos_bundle}]),
            digest_of(Bundle)
    end.

store(Path, none) ->
    case atomvm:posix_unlink(Path) of
        ok -> ok;
        {error, enoent} -> ok;
        {error, _} = Error -> Error
    end;
store(Path, Bundle) ->
    write_file(Path, Bundle).

%% Replaces Path's contents atomically: a temporary file, synced, renamed.
write_file(Path, Data) ->
    Temporary = Path ++ ".new",
    case atomvm:posix_open(Temporary, [o_wronly, o_creat, o_trunc], 8#600) of
        {ok, Fd} ->
            Written = write_all(Fd, Data),
            Synced = atomvm:posix_fsync(Fd),
            ok = atomvm:posix_close(Fd),
            case {Written, Synced} of
                {ok, ok} -> atomvm:posix_rename(Temporary, Path);
                {ok, Error} -> Error;
                {Error, _} -> Error
            end;
        {error, _} = Error ->
            Error
    end.

write_all(_Fd, <<>>) ->
    ok;
write_all(Fd, Data) ->
    case atomvm:posix_write(Fd, Data) of
        {ok, N} ->
            <<_:N/binary, Rest/binary>> = Data,
            write_all(Fd, Rest);
        {error, _} = Error ->
            Error
    end.

%% The whole file, or <<>> when it does not exist.
read_file(Path) ->
    case atomvm:posix_open(Path, [o_rdonly]) of
        {ok, Fd} ->
            Data = read_all(Fd, []),
            ok = atomvm:posix_close(Fd),
            Data;
        {error, enoent} ->
            <<>>
    end.

read_all(Fd, Acc) ->
    case atomvm:posix_read(Fd, 65536) of
        {ok, Chunk} -> read_all(Fd, [Chunk | Acc]);
        eof -> list_to_binary(lists:reverse(Acc))
    end.

digest_of(none) ->
    none;
digest_of(Bundle) ->
    list_to_binary([hex(B) || <<B>> <= crypto:hash(sha256, Bundle)]).

hex(B) ->
    [digit(B bsr 4), digit(B band 15)].

digit(D) when D < 10 -> $0 + D;
digit(D) -> $a + D - 10.

show(none) -> <<"none">>;
show(Digest) -> Digest.

%% AtomVM's string:trim/1 strips only spaces, so a cookie file's trailing
%% newline would end up in the cookie.
trim(Binary) ->
    list_to_binary(strip(lists:reverse(strip(lists:reverse(binary_to_list(Binary)))))).

strip([C | Rest]) when C =:= $\s; C =:= $\t; C =:= $\r; C =:= $\n -> strip(Rest);
strip(String) -> String.

env(Name) ->
    case os:getenv(Name) of
        false -> erlang:error({missing_environment, Name});
        Value -> Value
    end.
