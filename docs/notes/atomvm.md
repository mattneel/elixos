# AtomVM as the coprocessor (M29)

What took time, so the next session does not repeat it.

## Building it

- `make atomvm` runs `scripts/build-atomvm.sh`: melange builds
  `melange/atomvm.yaml` into `build/apk-atomvm/` and extracts
  `build/atomvm/{AtomVM,atomvmlib.avm}`. The cache key is the recipe plus
  `melange/atomvm/*.patch`; `FORCE=1` rebuilds.
- Static linking needs three things together: `-DCMAKE_EXE_LINKER_FLAGS=-static`
  with `CMAKE_FIND_LIBRARY_SUFFIXES=.a`, `ZLIB_USE_STATIC_LIBS=ON` (FindZLIB
  ignores the suffix list), and `AVM_STATIC_MBEDTLS=ON` with
  `CMAKE_DISABLE_FIND_PACKAGE_MbedTLS=ON` (Mbed TLS's CMake package points at
  the shared library and AtomVM refuses static linking through it).
- `PACKBEAM_PATH` does not keep rebar3 offline: AtomVM links the checkout as
  `_checkouts/packbeam`, rebar3 only matches `_checkouts/atomvm_packbeam`, and
  then fetches from Hex. The recipe links the right name itself and sets
  `REBAR_OFFLINE=1 HEX_OFFLINE=1`.
- Alpine 3.24 has `erlang28`, `elixir` 1.19.6, `mbedtls3-static`, `gperf` in
  main/community: everything the build needs without our own OTP.

## Running it

- The VM ends when the start module's `start/0` returns ("Return value: …");
  there is no `erlang:halt/0,1`. `:elixos_coproc` returns after a deploy.
- AtomVM distribution always registers with an epmd on 127.0.0.1:4369. The
  runtime starts AtomVM's own Erlang `epmd` unlinked; on a host that already
  runs epmd it fails to bind (logged as a crash report) and AtomVM registers
  with the host's instead. Both bind 0.0.0.0.
- Without `reuseaddr` (patch 0001) a restarted AtomVM cannot listen for about
  a minute: the connections the previous instance closed hold the port in
  TIME_WAIT. Every deploy restarts it, so this matters.
- Without `DFLAG_PUBLISHED` (patch 0002) OTP treats every AtomVM node as
  hidden: connected, but absent from `Node.list()`.
- `string:trim/1` strips only spaces; the cookie file's newline would end up
  in the cookie and every handshake fails with `invalid_challenge`.
- `erpc:execute_call/4` exits with its result, which AtomVM prints as a crash
  dump per call unless built with `AVM_PRINT_PROCESS_CRASH_DUMPS=OFF`.
- A spawn request with the `link` option (`Node.spawn_link/4`) does not link;
  `Process.link/1` on the remote pid does.

## OTP side

- OTP 29 reads `kernel` `epmd_module` and `inet_dist_use_interface` from the
  application environment when distribution starts, so `Elixos.Coproc` sets
  them at runtime; `address_please/3` returning `{ok, Ip, Port, 6}` skips epmd
  entirely.
- Starting distribution creates `$HOME/.erlang.cookie` if missing (on Elixos,
  `/priv/home/.erlang.cookie`).
- Once the node is alive IEx switches to `alive_prompt` (`iex(node)N>`);
  `config :iex, alive_prompt:` keeps the console prompt `iex(N)> `.

## QEMU

- A slirp `guestfwd` cannot target the network's own host address (x.x.x.2);
  the link uses 10.0.3.9. `cmd:socat - TCP:…` starts one relay per
  connection, so the link survives the coprocessor restarting.
- With two NICs, `ip=dhcp` lets the kernel pick either; `ip=:::::eth0:dhcp`
  pins it to the external one.

## Drivers (M32)

- The runtime archive (`Elixos.Coproc.runtime/0`) carries the drivers:
  `coproc_drivers` (supervisor), `coproc_driver` (the generic process) and,
  per subsystem, `coproc_<x>` (API + backend behaviour) and its backends
  `coproc_<x>_<set>`. `ELIXOS_COPROC_DRIVERS` picks the set (default `sim`).
  They start before distribution, so they never depend on Elixos.
- AtomVM cannot monitor a remote pid (`monitor/2` takes local pids only) and
  sends no exit or DOWN signal when a distribution connection closes. A
  driver therefore cannot tell that an Elixos subscriber is gone. Events are
  numbered and queued (64 per driver) until acknowledged; a subscriber gets
  the queue on subscribing. A remote node has one subscription, replaced on
  resubscribe; `Elixos.Coproc` renews them on every nodeup and drops
  duplicates by `{driver pid, seq}`.
- Sending to a pid of a node that is not connected makes AtomVM autoconnect
  (`net_kernel` setup through epmd); it fails harmlessly because Elixos never
  registers with an epmd. A pid of an earlier Elixos incarnation (another
  creation) is dropped silently.
- AtomVM only adds modules: `code:load_binary/3` replaces the name lookup,
  but there is no delete or purge, and the old code stays in memory. A
  bundle change therefore still ends the VM (ADR-099); the runtime hands the
  drivers' state (`coproc_drivers:handoff/0`, term_to_binary in
  `<bundle>.drivers`) to the next VM, which restores it before
  distribution. A generation switch that keeps the bundle never touches the
  coprocessor.
- Patch 0003: AtomVM's `socket_dist_controller` stopped `normal` when the
  socket closed, so the linked connection process lived on until the next
  tick (up to 15 s) and net_kernel kept the node "alive"; an Elixos that
  reconnected meanwhile with the same creation failed the handshake
  (`invalid_challenge`) every time. It now stops `{shutdown, closed}`.
  A new Elixos incarnation reconnected fine even before the patch.
- Testing the restart of Elixos needs a second BEAM: `:peer` with
  `connection: :standard_io` and no name starts it undistributed, so its own
  `Elixos.Coproc` can start distribution.
