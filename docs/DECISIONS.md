# Decisions

Architecture decision records. Add new ones at the end; never renumber.
When an acceptance test has to change, the ADR that explains why goes here
first (AGENTS.md, hard rules).

---

## ADR-001: Boot an unmodified mainline kernel

**Status:** accepted (project constraint)

**Context.** Vendor and patched kernels tie a system to someone else's fork.

**Decision.** Use a kernel.org release, pinned in `kernel/VERSION` with its
SHA-256. Configure it (`x86_64_defconfig` + `kvm_guest.config` +
`kernel/elixos.config`); never patch it. Building in an initramfs or a command
line (`CONFIG_INITRAMFS_SOURCE`, `CONFIG_CMDLINE`) is configuration, allowed.

**Consequences.** Hardware support is whatever mainline has. Anything we
need is built in (`=y`): there is no modprobe or udev. `scripts/check-kernel-config.sh`
fails the build if a requested option does not survive `olddefconfig`.
Pinned 2026-10-09: 7.2.9 (stable); 6.18.55 was the newest longterm.

## ADR-002: PID 1 is a tiny Zig shim; the BEAM is never PID 1

**Status:** accepted

**Context.** If PID 1 exits, the kernel panics. Recovery from a crashed or
hung BEAM needs an observer outside it. PID 1 must also reap orphans and do
mount and shutdown chores, which erlinit does for Nerves.

**Decision.** `/init` is a small static Zig program that mounts, plans,
launches ERTS, watches it (exit status plus heartbeats), and recovers. It never
parses anything richer than `key=value` and protocol lines.

**Consequences.** Crashes and hangs look the same to the shim. Its logic is
small enough to unit test exhaustively (`shim/src/*.zig`).

## ADR-003: Write the shim in Zig master

**Status:** accepted

**Decision.** Track Zig master, pinned to an exact nightly in `.zig-version`
(`scripts/install-zig.sh`). Use raw `std.os.linux` syscalls, no libc, no
allocation after startup, single-threaded.

**Consequences.** Master's std churns. The pinned std source is the
authority, not memory; compiler errors are the guide (AGENTS.md §Zig).
Verified for this scaffold on 0.18.0-dev.131+41f885830 (0.17.0 had just
been released).

## ADR-004: The shim survives its own panics

**Status:** accepted (M8)

**Decision.** Override the panic handler to re-exec `/init` in a recovery
mode. `execve` keeps PID 1 and keeps the BEAM as our child; pass the BEAM's
pid and the control fd in a pre-built argv.

**Consequences.** One failed bounds check in PID 1 is an inconvenience, not a
kernel panic. It is the same trick as systemd's daemon-reexec.

## ADR-005: The image is code plus data, not a heap snapshot

**Status:** accepted

**Context.** Lisp machines save the heap. The BEAM cannot; CRIU could
checkpoint `beam.smp`, but it is a heavy C dependency and fragile around
devices and sockets.

**Decision.** Smalltalk's model: content-addressed module blobs, an
append-only journal of every change, and immutable generation manifests. A
boot rebuilds the system from a generation.

**Consequences.** Nothing typed is lost (the journal); bad changes are
bisectable; process state is rebuilt, not restored (open question Q2).
CRIU stays a stretch goal.

## ADR-006: The shim owns `boot.state`

**Status:** accepted

**Decision.** `boot.state` has a single writer, the shim. The BEAM asks for
changes over the control protocol (`COMMIT`, `NEXT`). The format is three
`key=value` lines, parsed strictly (PROTOCOL.md §4). An unreadable file is
kept as evidence and the boot goes to rescue.

## ADR-007: Recovery walks provisional → last_good → factory rescue

**Status:** accepted

**Decision.** Count attempts *before* each launch. A generation becomes good
only when the running system commits it (`Elixos.Boot.AutoCommit` after
`elixos.commit_after` seconds of healthy uptime, or `Elixos.commit/0`). After
`max_attempts`, fall back to `last_good`; if that is exhausted too, boot the
factory in rescue mode and wait for the user. Exact rules: ARCHITECTURE.md §3.3.

## ADR-008: ERTS is dynamically linked against musl, built with zig cc

**Status:** accepted

**Context.** NIFs are shared objects loaded with `dlopen`; statically linked
musl cannot `dlopen`.

**Decision.** Cross-build OTP for `x86_64-linux-musl` with `zig cc`, linked
dynamically. Ship `/lib/ld-musl-x86_64.so.1` (musl's loader is its libc).
OpenSSL for `:crypto` is built the same way.

**Consequences.** One toolchain (zig) builds the shim, ERTS and, later, NIFs on
the box. Precompiled musl NIFs from packages load as-is. If the cross-build
blocks progress, a known-good musl OTP build may stand in temporarily behind
the same paths; record it in docs/notes/ and replace it before M11.

## ADR-009: zig cc is the system C compiler, in a toolchain package

**Status:** accepted (M11)

**Decision.** Ship `zig cc`/`zig c++` (plus make and a BusyBox sh, which
`elixir_make` needs) as a package fetched into `/priv` on first use, never in
the factory. `ZIG_GLOBAL_CACHE_DIR=/priv/cache/zig`.

**Consequences.** An x86_64 Elixos can cross-build NIFs for other targets
too, since BEAM bytecode is portable and only NIFs are architecture-specific.
The "no sh" rule (ADR-012) holds for the system: the toolchain's sh only runs
build recipes.

## ADR-010: Elixos is a Mix target, not an environment

**Status:** accepted

**Decision.** `MIX_TARGET=elixos`, the mechanism Nerves uses. Apps keep
dev/test/prod; `config/elixos.exs` layers on top; `targets: :elixos` scopes
dependencies; builds go to `_build/elixos_<env>`.

**Consequences.** `config_env() == :prod` checks in `runtime.exs` keep
working. Verified by `os/test/elixos/package/mix_target_test.exs`.

## ADR-011: `elixos:` in mix.exs says how to install; config/elixos.exs says how to behave

**Status:** accepted

**Decision.** Mix ignores unknown project keys (as with ExDoc's `:docs`), so
an `elixos:` key costs nothing on a plain host. It holds install metadata
(services, persist, min_os, boot) readable without building the app;
`config/elixos.exs` holds runtime configuration.

## ADR-012: REPLs are the login shells; there is no sh in the base system

**Status:** accepted

**Decision.** `/etc/shells` is erl, IEx and gsh. Logins (console, SSH) start
the user's REPL through OTP's shell contract (an MFA returning the shell pid).
Nothing in the factory may need a shell: the shim execs `erlexec` directly,
not a release's `bin/` scripts.

**Consequences.** Every REPL sees the same running VM. Switching REPLs does
not switch worlds.

## ADR-013: Single user

**Status:** accepted

**Decision.** One user, Lisp-machine style: full power everywhere, no
permission model, no login prompt on the console, public-key-only SSH.

**Consequences.** A REPL is not a security boundary, and that is fine.

## ADR-014: x86_64 only, booting via the EFI stub

**Status:** accepted (for now)

**Decision.** Build and test only x86_64. QEMU boots the kernel directly
(`-kernel`/`-initrd`); hardware boots the kernel's EFI stub from the ESP, no
bootloader.

**Consequences.** One kernel config, one ERTS build. aarch64 is a later,
explicit decision.

## ADR-015: One module namespace means system-wide package resolution

**Status:** proposed (see Q1)

**Context.** Releases give each app its own VM; Elixos runs every app in one,
with one module namespace.

**Decision (proposed).** Keep exactly one version of each package installed,
Debian style. Refuse an install that would break an installed app. The
`elixos` package is the running OS: dependencies on it are checked against the
OS version and a bundled copy is refused.

## ADR-016: Nothing changes the VM's global state for everyone

**Status:** accepted

**Context.** On Elixos every program shares one VM. Its working directory,
OS environment and code path are global. Found while writing this scaffold:
`Mix.Project.in_project/4` changes the VM's cwd, and a concurrently compiling
test file then failed with `:enoent`.

**Decision.** No OS code changes the VM's cwd or environment variables, even
briefly. Builds (`Elixos.Package.install/1`) run in a child ERTS exec'd
directly. `Elixos.Package.Spec.read_project/1` is tested to never move the cwd.

## ADR-017: Test-driven, milestone-gated development

**Status:** accepted

**Decision.** The roadmap exists as tests. `MILESTONE` gates them (Zig: skip;
ExUnit: exclude). Golden vectors in `spec/` are shared by the Zig and Elixir
suites. System behavior is tested by booting QEMU and reading the serial
console and the disk image (docs/TESTING.md). Every pure test shipped in the
scaffold was run against a throwaway reference implementation first, so a red
test means missing code, not a broken test.

## ADR-018: QEMU test images carry test hooks; hardware images never do

**Status:** accepted

**Decision.** `elixos.test.*` parameters are compiled in only with
`-Dtest-hooks=true` (`make shim`). `make release-shim` builds without them.

## ADR-019: Hex is the package manager; commands are functions

**Status:** accepted (M14)

**Context.** Elixos runs every app in one VM (ADR-015), so "install an app"
means "make its modules loadable here", not "set up another release". Mix is
already on the box, Hex is already the Elixir ecosystem's package format, and
`mix release`-style workflows are wrong for a machine you live inside.

**Decision.** Package sources are **Hex repositories**, used the way apt uses
its sources: a repo is a name, a URL and a **public key**, and nothing from it
is installed until that key was trusted. `elixos` is official and ships
configured in the factory with its public key; `elixos-community` and anyone
else's repo are opt-in. The official repository is hosted on GitHub Pages
(`https://mattneel.github.io/elixos`), built and published by
`.github/workflows/hex-repo.yml` from the projects under `hex/packages/`; the
factory ships the matching public key, and the build refuses to sign with any
other key, because every shipped box would refuse the result. A repo is added with its public key or a verified
fingerprint (like `mix hex.repo add --public-key/--fetch-public-key`), and an
install never trusts a repo implicitly: adding it is the consent step, and on a
single-user machine (ADR-013) there is no sudo in the way. Repositories are
self-hosted static Hex repos built with `mix hex.registry build`.

`Elixos.Package.install/1` takes a **name**: the package is found in the
trusted repos, its tarball fetched and unpacked, and the directory handed to
the M11 path (build in a child ERTS, load, start services, record in the
image). `install/1` with a path keeps its M11 meaning ("install this
directory"). The apt verbs are functions, not commands: `add_repo/3`,
`remove_repo/1`, `repos/0`, `search/1` (a static repo has no search API, so a
name is matched against the registry's names index), `info/1`, `upgrade/0,1`,
`remove/1`.

Across every trusted repo a package **name** belongs to exactly one repo, so
ADR-015's one-version-per-package rule holds; a clash is an error naming both
repos. `:elixos` is never fetched: a dependency on it is satisfied by the
running OS, and a package that bundles it is refused (M10).

**Programs are packages, commands are functions.** A package exposes an Elixir
API; it does not ship a CLI. When a package must run a native tool it execs it
directly (`System.cmd/3` or a `Port`) with `cd:` set to the caller's session
directory — never through a shell (ADR-012), never by changing the VM's working
directory (ADR-016). The first instance is the M11 toolchain's `Zig` module
(`Zig.init/1`, `Zig.build/2`, ...).

`Mix.install/2` is not the mechanism: it raises when called a second time with
different dependencies, and while installing it changes the whole VM's working
directory with `File.cd!` (verified on Elixir 1.20.4). Both are exactly what
one shared VM cannot have.

**Consequences.** Package installation is a function call that fetches from a
trusted repo; a repo is trusted by its key and nothing else; curated snapshots
and prebuilt binary caches are out of scope for now. `mix.exs` keeps its
`elixos:` key (ADR-011) for how an app wants to be installed; Hex carries it as
package metadata.

**Alternatives considered.** (a) Git-URL installs (`mix deps.get`): no
registry, so no search, no versions, no signatures, and every user's URL is a
different dependency identity. (b) `Mix.install/2`: see above — one-shot deps
and a global `File.cd!`. (c) A custom package format: reinventing Hex's
signing, registry and tarball format for no gain, and cutting apps off from the
Hex ecosystem. (d) Trusting a repo on first use (TOFU): makes the first
install the attack, and a single-user machine has no second line of defence.
(e) Curated snapshot repositories: nice for appliances, wrong for a machine you
program while it runs, and out of scope.

## ADR-020: Each REPL session has its own working directory

**Status:** accepted (M9)

**Context.** Every process on Elixos shares one VM, and its working directory
is global (ADR-016). A shell that must not change it therefore cannot use the
VM's cwd as its own. Meanwhile IEx's `cd/1`, `pwd/0` and `ls/0,1` are built on
`File.cd/1` and `File.cwd/0` (verified on Elixir 1.20.4: `IEx.Helpers.cd/1`
calls `File.cd/1`), and the erl shell's `cd/1` comes from `user_default` and
calls `file:set_cwd/1`: both change the world for everyone.

**Decision.** A **REPL session** has its own working directory, starting at
`/priv/home`. The directory is keyed by the session's process-group leader,
which every process spawned from that REPL inherits, so console jobs, SSH
channels and anything they start each have one. Relative paths typed at a
prompt expand against the session's directory.

The login REPLs carry session-aware `cd/1`, `pwd/0` and `ls/0,1`: for IEx, the
Elixos helpers are imported into the evaluation environment instead of
`IEx.Helpers`; for erl, `user_default` provides them; gsh follows when it
lands. Native tools run with `cd:` set to it (ADR-019), and nothing any of them
does changes the VM's working directory.

**Consequences.** Two consoles can sit in different directories while
`File.cwd!/0` stays `/` for every process; a `cd` is local to the session and
does not survive a power cycle (the directory is not persisted). Anything that
must resolve a relative path for a process needs the session it belongs to,
which is why the key is the group leader rather than the calling pid.

**Alternatives considered.** (a) Change the VM's cwd and restore it around each
command: racy the moment anything is concurrent, and forbidden by ADR-016.
(b) One working directory for all sessions: what the shells do today, and
useless as soon as two sessions exist. (c) A process dictionary per process: a
spawned process would lose the directory, so `System.cmd(cd: ...)` would break
for anything started from a task. (d) An explicit session handle passed to
every function: infects every API, and the shells' built-ins cannot take it.

## ADR-021: The persistent disk mounts at /priv

**Status:** accepted (decided by the human, 2026-10-09)

**Context.** The persistent ext4 disk was mounted at `/data`, a name from the
scaffold. The human moved it to `/priv`, named after OTP's `priv` directories:
the OS's private storage, the counterpart of an application's `lib/`.

**Decision.** The disk mounts at `/priv`; the user's home is `/priv/home`, and
`~` means `/priv/home` everywhere. The launch contract sets `HOME=/priv/home`
(PROTOCOL.md §3), so `Path.expand/1`, IEx, Mix and anything else that resolves
`~` land there with no Elixos-specific code, and there is no other home
directory. Session directories start in `~` (ADR-020).

The kernel parameters keep their names: `elixos.data=` and `elixos.data_wait=`
name the *device*, not the path, and renaming them would change an interface
for a filesystem rename and rewrite passing M1 and M3 acceptance tests.

**Consequences.** Every path under the old mount point moved: `boot.state`,
`store/`, `journal.log`, `generations/`, `user.exs`, `home/`, `ssh/`,
`cache/`, `apps/` and `hex/`. The shipped tests that spelled the old path — the
M9, M11, M12 and M14 acceptance files, whose fixtures and assertions name it —
changed path for path in the same commit, which is what this ADR records
(AGENTS.md, hard rules). `docs/TESTING.md` and the `Elixos.Test.Disk` helper's
docs now say that `/priv/x` in the guest is `/x` on the disk.

**Alternatives considered.** (a) Keep `/data`: the human decided otherwise, and
`priv` already means "this system's own files" to an OTP reader. (b) `/var`:
POSIX shaped, and wrong for a system whose userland is one application.
(c) `/persist`, `/state`, `/store`: longer, and meaningless to that reader.
(d) Renaming `elixos.data`: rejected above — it would break the M1 and M3
tests for no gain.

## ADR-022: The factory's ERTS is built with the musl cross gcc

**Status:** accepted (2026-10-09). Supersedes the ERTS half of ADR-008.

**Context.** ADR-008 chose zig cc as the one toolchain that builds the shim,
the ERTS and (later) the NIFs, with the ERTS dynamically linked against musl.
Building OTP 29.1.1 that way failed for reasons that are properties of Zig as
of 0.18.0-dev.131, not of the configuration (the full story is in
docs/notes/factory-build.md):

  * Zig's linker *localizes* libc's string and math symbols that shared
    libraries need at run time (`memcpy`, `memcmp`, `bcmp`, the libm entry
    points). Linking musl's own objects with `zig cc -shared` leaves them out
    of `.dynsym`, while GNU ld exports them, as a canonical musl loader does
    (checked against Alpine's `ld-musl-x86_64.so.1`). A shared library such as
    `libcrypto.so.3` therefore carries dynamic relocations only a loader
    exporting those names can satisfy — and Zig's bundled `libc.so` is
    static-pie with no `_dlstart`, so it cannot be that loader.
  * OTP's build works against it: `erts/emulator` defines `DEP_CC=$(CC)`, so it
    preprocesses C++ sources with the C driver, which does not add libc++'s
    include paths; and the *bootstrap* (host) builds inherit any exported
    `CPPFLAGS`/`LDFLAGS`, which put musl headers in front of the host's.

**Decision.** The factory's ERTS is built with musl.cc's
`x86_64-linux-musl-cross` gcc, pinned and checksummed like the kernel is
(ADR-001); every factory download is, so the image cannot change because an
upstream tarball did. The shim stays on zig (ADR-003) and builds the initramfs;
the on-box compiler for NIFs stays zig cc (ADR-009).

**Consequences.** The split is invisible to the running system and to NIFs:
they are loaded with `dlopen` into the same dynamically linked musl ERTS, and a
session still compiles with zig cc. What changes is who produces the factory —
`scripts/build-factory.sh` rather than a `zig build` step — and ADR-008's goal
(a dynamic musl ERTS) is met by a different compiler. Replacing the cross gcc
with zig cc later is a build-script change, not an image change; the two
blockers above are what would have to be fixed first, and ADR-008's escape
hatch (a known-good musl build behind the same paths) was not needed.

**Alternatives considered.** (a) Keep pushing on zig cc: the loader problem was
worked around by linking musl's loader with GNU ld and a fake-native configure
made the probes run, but OTP's bootstrap and dependency generation still fought
the toolchain, and the loader Zig links against is unusable as an interpreter.
(b) The host's gcc with a musl sysroot: no musl-targeting host compiler exists
here (`musl-gcc` links statically only, which breaks `dlopen` and ADR-008).
(c) Build inside an Alpine container natively: the newest OTP there is 27, too
old to bootstrap 29.1.1. (d) A prebuilt musl OTP: ADR-008 allows it as a
temporary stand-in, but a checked-in binary is worse than a pinned download.

---

## Open questions

Decide these with the human. Until then, follow the proposed default.

- **Q1: Package versions.** One version per package system-wide (proposed,
  ADR-015), or something cleverer, such as per-app module renaming?
- **Q2: Process state.** Rebuild from supervisors and `/priv` at boot
  (proposed), or persist some process state across boots?
- **Q3: Wi-Fi.** `wpa_supplicant`/`iwd` as a package, or nl80211 from Elixir?
- **Q4: The cyberdeck hardware.** Which machine? It decides the kernel
  options and firmware blobs needed beyond the QEMU set.
- **Q5: Kernel and factory upgrades on hardware.** Two ESP entries with
  `BootNext`, or something simpler?
- **Q6: gsh.** Packaging the `gleam` compiler that gsh drives.
- **Q7: On-disk layout of repo configuration and trusted keys.** Proposed
  default: `/priv/hex/repos.exs` (a keyword list of `name: [url:, key:]`, the
  key being the PEM text) and `/priv/hex/keys/<repo>.pub` for the key files, so
  trust survives power cycles and a repo can be inspected by hand. The factory
  ships the default in `/factory/hex/`, and `/priv/hex/repos.exs` is what a
  session reads: seeded from the factory the first time, then the machine
  owner's. It is read by evaluating it (`Code.eval_file/1`), because PEM keys
  do not fit a line format; that single exception is why it is worth a
  decision. The root is `Application.get_env(:elixos, :hex_dir, "/priv/hex")`,
  so the host unit tests can point it at a temporary directory. PROTOCOL.md §7
  and §8 document the paths and the format.
- **Q8: Repo URLs beyond http(s).** Proposed default: a repo URL may be an
  `http(s)://` URL or a local path (the tests use a local path, and an offline
  mirror is just a directory). No other schemes.
- **Q9: Module names for package-provided APIs.** ADR-019 says a package
  exposes an Elixir API. Proposed default: the package's own top-level name,
  as Hex packages normally do — the M11 toolchain package provides `Zig`, so
  `Zig.init/1` is how a session initializes it.
