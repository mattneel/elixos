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

**Status:** superseded by ADR-041 (how ERTS is built)

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

**Status:** amended by ADR-041 (a shell is allowed for tooling; IEx stays the
login shell and the shim still execs erlexec directly)

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

**Status:** superseded by ADR-041 (x86_64 and aarch64)

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

## ADR-023: The shim validates BEAM-side parameters; it does not apply them

**Status:** accepted (2026-10-09, from the human's review)

**Context.** PROTOCOL.md §5 splits the kernel command line between the two
sides of the launch contract: the shim's parameters (device, generations,
attempts, timeouts, the test hooks) and the BEAM's own (`elixos.commit_after`).
The shim counted every `elixos.*` token it did not *apply* as invalid, so a
boot with `elixos.commit_after=2` — a perfectly good parameter — logged
`ignored 1 invalid elixos.* parameters`. The line exists to catch typos, and a
valid parameter of the other side is not one.

**Decision.** The shim knows the *names* and the syntax of the BEAM-side
parameters as well as its own. For a BEAM-side parameter it checks the syntax
and never applies it (the BEAM reads `/proc/cmdline` itself, §5). `invalid`
counts only what neither side defines, plus values that are malformed by the
rule of whichever side defines them.

**Consequences.** `elixos.commit_after=2` boots quietly;
`elixos.commit_after=abc`, `elixos.commit_after=0` and `elixos.nonsense=1` are
still counted and logged. PROTOCOL.md §5 marks which side owns each parameter,
and the shim's parser tests cover a BEAM-side parameter: valid is silent, a
malformed value is counted. Adding a BEAM-side parameter means teaching the
shim its name and syntax, which is the point — the shim is the only thing that
can say anything about the command line before the BEAM exists.

**Alternatives considered.** (a) Ignore unknown `elixos.*` keys silently: loses
exactly the typo the line is for (`elixos.mx_attempts=3` would boot without a
word). (b) The shim applies BEAM-side values and passes them in the launch
environment: two sources of truth for one setting, and the BEAM's own
`/proc/cmdline` reading is what `Elixos.Boot.Cmdline` already tests. (c) Let
the BEAM do the validating and logging: the command line is read before the
BEAM exists, and a broken one is what the shim's log is for.

---

## ADR-027: The toolchain package is on PATH

**Status:** accepted (M11)

**Context.** A build on the box runs `cc` (the NIF fixture's compiler task
looks it up with `System.find_executable/1`), and the toolchain package
(ADR-009) is exactly that: the disk's `/priv/toolchain/`, where `cc` and `c++`
are symlinks to `zig`. Without it on `PATH`, nothing on the box can find a
compiler - and `Elixos.Zig` deliberately never touches the VM's environment
(ADR-016), so the PATH has to come from the launch contract.

**Decision.** The shim's launch environment (PROTOCOL.md §3) includes `PATH`:
`/priv/toolchain:/bin:/usr/bin` when the persistent disk is mounted, and
`/bin:/usr/bin` without it, since there is nothing to build with then. The
variable is additive: `Elixos.Boot.Env.parse/1` ignores what it does not know,
so the boot is unaffected.

**Consequences.** A session's `System.find_executable("cc")` finds the
toolchain; a build that must not see it can pass its own `PATH`. On the host
there is no `/priv`, and a host build keeps using the host's PATH.

**Alternatives.** Appending the toolchain directory in `Elixos.Zig.init/1`
with `System.put_env/2` would change the VM's environment, which ADR-016
forbids; a shell wrapper is banned by ADR-012.

## ADR-028: The emulator runs `-mode interactive`

**Status:** accepted (M11)

**Context.** ERTS defaults to `-mode embedded` when it is given `-boot`, and
the embedded code server loads only what the boot script names: every call into
a module the system did not start with fails with `undef`, and
`Code.append_path/1` has no effect. Elixos loads code at run time in two
places - the live image restores modules that were defined at a prompt
(M6), and the box builds and installs Mix projects, whose compiled BEAM files
must be loadable the moment they are built (M11). With `-mode interactive`,
`Elixos.Package.install/1` reached the child build and then returned
`{:error, {:load_failed, :ebin, ...}}` before the fix; after it, the install,
the service start and `SampleApp.where/0` all work, which is what
`test/integration/m11_self_hosting_test.exs` (the acceptance test) exercises.
Interactive mode is what the release's own `start` script uses on a normal
machine; embedding is an optimisation for appliances that never load code.

**Decision.** The shim launches ERTS with `-mode interactive`
(PROTOCOL.md §3). The Elixir side parses no new variable: the flag is consumed
by ERTS itself, and `Elixos.Boot.Env` is unaffected.

**Consequences.** Code loaded at run time is loadable; a session may install
new code without a restart. Startup is marginally less eager than embedded
mode's, which changes nothing on a system that restores an image and opens a
REPL.

**Alternatives.** Preloading every installed app's modules from the boot
script would require rebuilding the boot script on every install and would not
help a prompt-defined module restored from an image.

## ADR-029: The M14 packages test reads the disk at the mount point

**Status:** accepted (M14)

**Context.** `test/integration/m14_packages_test.exs` seeds the fixture
repository with `Elixos.Test.Disk.put_tree!(disk, tree, "/hex-repo")` and then
reads `/hex-repo/public_key` *inside the guest*. But `put_tree!` takes a path
on the *disk* - its own moduledoc says so: `/priv/boot.state` in the guest is
`/boot.state` there - and the disk is mounted at `/priv` (ADR-021), so the
file the test wrote is `/priv/hex-repo/public_key` in the guest. The test was
never run against an implementation (that is what M14 is for), and the
`File.read!("/hex-repo/public_key")` failed with `no such file or directory`
on the first real run: a transcription slip - the disk-path spelling leaked
into the guest commands - not a statement about where the disk mounts.

**Decision.** Fix the guest paths: `/priv/hex-repo` and `/priv/hex-mirror`.
The `put_tree!` calls keep `/hex-repo` and `/hex-mirror`, because those are
disk paths and the mapping to `/priv/...` in the guest is the point. Every
assertion keeps its meaning.

**Consequences.** The test exercises what it was written to exercise. The
mount point stays what ADR-021 and PROTOCOL.md §7 say it is; a future test
that writes disk paths into guest command lines will fail the same way, which
is how this one was found.

**Alternatives.** Changing the mount point would be a much larger decision
(ADR-021) and would not fix the inconsistency; the M11, M12 and M13 tests all
use `/priv/...` in their guest commands.

## ADR-030: The M14 toolchain test types one expression per call

**Status:** accepted (M14)

**Context.** `test/integration/m14_packages_test.exs` wrote its stand-in
`zig` escript as one multi-line string and handed it to `QEMU.iex/3`, whose
contract is a single expression: it sends one line and returns everything up
to the *next* prompt numbered higher than the last one seen. A multi-line
paste produces one result but several prompt redraws, so the helper's prompt
counter advances past them and every following call returns the *previous*
call's output (observed: four empty results, then a slice beginning `nil` and
the echo of an earlier line). The test was never run against an
implementation, so the slip never showed.

**Decision.** Send the three escript-writing expressions as three calls, one
line each, and keep every assertion as it was. The toolchain lookup in
`Zig.zig/1` also prefers `bin/zig` (a package payload's layout, ADR-019) over
the flat `zig` the disk's M11 copy carries: with only the flat one, the
stand-in escript the test installs would never be the program that runs,
which is exactly what this test is about.

**Consequences.** The test exercises what it means to: the escript is exec'd
directly, in the session's directory, with no shell, and `Zig.build/2`
reports its output. Multi-line console input stays available to a human at
the prompt; it is the test helper's prompt bookkeeping that a paste
desynchronizes.

**Alternatives.** Teaching the helper to count prompt redraws would give the
test a contract the console does not promise; the M11, M12 and M13 tests all
send single expressions.

## ADR-031: The M14 toolchain test asserts the escript's output, not its inspect

**Status:** accepted (M14)

**Context.** The same test's `Zig.build/2` assertion reads
`assert out =~ ~s("/priv/home")` - the quoted form. The stand-in escript it
just wrote prints its directory with `io:format("~s~n", [Dir])`, and
`Zig.build/2` returns the child's output verbatim
(`{:ok, %{output: "/priv/home\n", status: 0}}`), so the closing quote never
follows `home` directly and the assertion failed on the first real run. The
pattern was carried over from the `cd/1` assertion above it, where the quoted
form is right: `cd/1` *returns* the path, and the prompt inspects it.

**Decision.** Assert the directory itself: `assert out =~ ~s(/priv/home)`.
The escript and `Zig.build/2` are unchanged - `Zig.version/0` trims what it
reports precisely because `run/2` does not.

**Consequences.** The test still proves what it means to: the tool runs with
`cd:` set to the session's directory, and its output reaches the caller.

**Alternatives.** Trimming the output inside `Zig.run/2` would make the
quoted assertion pass, but it would change an M11 API to fit a test that was
never run, and `Zig.version/0` already trims where trimming is wanted.

## ADR-032: Agents restart from the image, with their memory on /priv

**Status:** accepted (M15)

**Context.** Q2 asked whether a boot rebuilds process state from supervisors
and `/priv`, or tries to persist it; M15's agents make the answer concrete. A
module the image keeps is not a process: Jido runs an agent as an
`AgentServer`, whose state is what the agent has been told. A heap snapshot is
the vision's non-goal, and CRIU stays a stretch goal.

**Decision.** `Elixos.Agents` starts recorded agents under
`Elixos.Agents.Supervisor` and records each in the image's journal
(`{:agent, id, module, opts}`), so the boot starts it again. An agent's memory
is written to `/priv/agents/<id>.term` by `Elixos.Agents.snapshot_all/0`, and
that runs whenever the image is written (`Elixos.save/1`) and on a graceful
stop - one durable moment, like everything else the image keeps. A Jido
agent's memory is its state map, handed back as `initial_state`; a plain
agent's is whatever `snapshot/1` returns, handed back as `:snapshot`. The LLM
is a provider, not the definition: `Elixos.Agents.LLM` speaks both wire
shapes, and the `:codex` mode signs in with a ChatGPT subscription through
`~/.codex/auth.json` (refreshing the token when its own `exp` says so), so an
agent works with no model at all and a model works with no API key.

**Consequences.** What survives a power cycle is what a save saw; work done
after the last save is lost, which is the same promise the image makes and the
reason `Elixos.save/1` exists. Agents are ordinary modules: anything the image
can journal, this can run.

**Alternatives.** Persisting process state (Q2's other arm) needs a snapshot
of the heap; CRIU could checkpoint `beam.smp` but is heavy and fragile around
devices (VISION.md, "Not").

## ADR-033: A package may arrive built

**Status:** superseded by ADR-036 (M15)

**Context.** M14 installs a package by building it on the box. Jido's closure
cannot be built there yet: three of its 15 dependencies are rebar projects,
and one of them (telemetry) needs the `pc` plugin, which rebar3 fetches from
the network. The box has neither rebar3 nor that network.

**Decision.** A package whose contents carry `ebin/` and no `mix.exs` is
adopted, not built: the application resource inside names it, its tree is
copied under `/priv/apps` like every install's, its application is loaded and
it is recorded - dependencies first, weighed by the resolver all the same. The
fixture's jido closure arrives this way, written by Hex's own tarball writer so
its checksums are the ones a registry builder recomputes.

**Consequences.** Installing such a package is fast (nothing compiles) and
portable (BEAM files are architecture-independent; a NIF ships built for musl).
Building rebar packages *on* the box waits for rebar3 in the toolchain package
along with a plugin story; until then, a repository that serves one is expected
to serve it built.

**Alternatives.** Vendoring jido (ADR-019 says packages arrive through the
repository); shipping rebar3 plus a pre-seeded plugin cache (a milestone of its
own).

## ADR-034: The shim brings loopback up

**Status:** accepted (M15)

**Context.** The kernel leaves `lo` down until someone asks. Everything local
needs it: an agent's action calling a provider on `127.0.0.1`, a service a
session starts for itself. Until M15 nothing did - M12's SSH comes in over
virtio-net, and a stub on a disk with no network is useless.

**Decision.** After mounting the pseudo-filesystems, PID 1 brings `lo` up with
one ioctl (`SIOCGIFFLAGS`/`SIOCSIFFLAGS`, `IFF_UP|IFF_RUNNING`). A failure is
not fatal and, on the normal path, not logged: the console lines are API
(PROTOCOL.md §6). The Zig unit test checks the ioctl plumbing (a real
interface parses, a missing one is the kernel's error); the guest, where PID 1
is root, is where the flags actually change, and the M15 acceptance proves it
end to end.

**Consequences.** Local sockets work from boot on any image, and nothing else
in the system configures an interface - the network device still comes from
the kernel's `ip=dhcp` or nothing at all.

**Alternatives.** A helper in Elixir (later than PID 1, and no portable ioctl
in the standard library); a shell script (ADR-012).

## ADR-035: The factory ships the stock OTP applications and a CA bundle

**Status:** amended by ADR-041 (the image now installs OTP as its own package
and takes the CA bundle from Alpine's ca-certificates-bundle)

**Context.** A release carries only the applications its dependency graph
names, so `mix release` left out what an *installed* package may need at run
time: mnesia (a hard dependency of jido), ssl and inets (a provider over the
network). And TLS verification needs a trust store, which an initramfs does not
have.

**Decision.** `scripts/build-factory.sh` copies those stock applications from
the cross-built OTP into `/factory/lib`, and the host's CA bundle to
`/etc/ssl/certs/ca-certificates.crt` - the place `:public_key.cacerts_get/0`
reads. `Elixos.Application` puts `/factory/lib/*/ebin` on the code path at
boot, before anything can load from it. Nothing is started by this: the code
is there, and a package's own application starts what it declares.

**Consequences.** An installed package can start its OTP dependencies, and a
hosted provider (or a Hex repository) can be verified from the box. The bundle
is a build-host artifact: refreshing it means rebuilding the factory.
Which applications travel is a short list that grows when something needs one.

**Alternatives.** Shipping every OTP application (the image is an initramfs);
letting each package vendor its dependencies (ADR-019 forbids it).

## ADR-036: Jido is a dependency of Elixos itself

**Status:** accepted (M15)

**Context.** M15 makes agents part of the operating system, and Jido is what
an agent is written in. The first cut brought it in the way M14 brings in a
program: a package, installed from a trusted repository by name, its whole
closure (15 Hex packages) unpacked to `/priv/apps` and loaded at run time.
That is the wrong shape for a framework the OS's own behavior is defined in -
nothing installs `Enum` before the standard library works - and the closure
cannot even be built on the box (three rebar projects, and telemetry's `pc`
plugin fetches from the network), which is why ADR-033 had to invent a "may
arrive built" package for it.

**Decision.** `os/mix.exs` depends on `jido ~> 2.4`, and the factory ships it
like every other application in the release: `mix release` carries the closure
(jido, jido_action, jido_signal, jason, crontab, fuse, multigraph,
nimble_options, nimble_parsec, poolboy, splode, telemetry, telemetry_metrics,
time_zone_info, zoi), and `mnesia` - jido_signal's OTP dependency - comes from
the cross-built OTP beside the ERTS. Nothing is installed or adopted at run
time. The package manager keeps its M14 meaning for programs; a package that
arrives built has no user left, so ADR-033 and the "arrive built" code path are
superseded, and the fixture's prebuilt closure (`build-jido.sh`,
`jido_build.exs`, 15 tarballs) is removed - the fixture repository serves the
`hello_*` sources only.

**Consequences.** Every boot starts jido (and through it mnesia) before
`Elixos.Application` runs, so an agent can run the moment a prompt exists; the
M15 acceptance asserts that instead of installing anything, and
`agents_test.exs`'s moduledoc follows - both changed in their own commit, per
AGENTS.md. `os/test/elixos/package/mix_target_test.exs` now resolves the
project's own dependencies (its lock, pointed at this project's `deps/`) for
the `sample_app` fixture, because the path dependency has a closure of its
own. The OS's dependency set is a fact of the factory (ADR-008): building the
factory needs the network once for `mix deps.get`, like the kernel and OTP
downloads. The closure is pure BEAM - no NIFs - and `time_zone_info`'s
`data.etf` is the only non-BEAM byte it carries, so nothing needed a musl
cross-build.

**Alternatives.** Vendoring the sources under `os/` (a second source of truth,
and still not how a program arrives); keeping install-by-name for jido and
pre-seeding the fixture (the slow, two-step path this replaces); building rebar
packages on the box (ADR-033's alternative - still not possible, and no longer
on the critical path).

## ADR-037: A memory that cannot be written fails the save (and the stop)

**Status:** accepted (M15)

**Context.** `Elixos.save/1` and `Elixos.poweroff/0` are the live image's one
durable moment: everything typed is recorded, and every agent's memory is
written with it. `Elixos.Agents.snapshot_all/0` walked the agents and threw
each write's error away, and `stop/1` ignored the journal write that removes
the record. A full disk could therefore make `Elixos.save()` answer `{:ok, n}`
with stale memory in the generation, or make a power-off lose what an agent
remembered - the one promise this system makes, failing silently.

**Decision.** Every write that is part of that moment is checked. A snapshot
failure makes `snapshot_all/0` return `{:error, {:snapshot_failed, ids}}`, and
`save/1` and the shutdown path propagate it instead of proceeding; a
power-off that cannot write an agent's memory is refused and the caller sees
the error. `stop/1` surfaces a failed forgetting too, keeps the record (which
is what the next boot reads) and answers `{:error, reason}`, so a second stop
finishes the job instead of lying to the caller.

**Consequences.** A broken or full store now costs an error at the prompt -
and a retry - instead of silently losing work. The tests inject the failure
both ways: a file where the agents directory should be, and an image that
refuses to write forgetting down.

**Alternatives.** Logging and continuing (the silent loss this replaces);
writing the generation anyway with a warning (a generation recorded as good
with stale memory is worse than no save at all).

## ADR-038: The Content-Type decides whether a body is an event stream

**Status:** accepted (M15)

**Context.** `Elixos.Agents.LLM` decided how to decode a response by looking
for the substring `data:` anywhere in the body. A perfectly ordinary JSON
completion whose *text* contains `data:` - a question about Kafka, an SSE
example - was then read as server-sent events: no line of the JSON document
starts with `data:`, the list of payloads came back empty, and `complete/2`
answered `{:error, {:no_text, nil}}` for a response that plainly had text.

**Decision.** The headers decide. `http/3` returns the response headers with
the body, and the body is decoded as server-sent events only when the
Content-Type says `text/event-stream`; anything else is one JSON document.

**Consequences.** The one backend that streams (the ChatGPT Responses API,
which insists on `stream: true`) declares it and still works; a JSON body is
JSON no matter what words are in it. A server that streamed bytes while
declaring JSON would no longer be read - none does, and the header is the
protocol.

**Alternatives.** Sniffing for `data:` at a line start (still guesses);
trying both decodings and taking the first that yields text (two code paths
for one truth).

## ADR-039: The closure keeps only what the root can reach

**Status:** accepted (M15)

**Context.** The Hex name resolver rebuilt each pass's constraint map from
every name it had picked *before*, so a release picked for a constraint that
a later pick invalidated stayed in the map and kept contributing its own
requirements. With root -> {a >= 1.0.0, b ~> 1.0}, a 2.0.0 -> {c ~> 1.0},
b 1.0.0 -> {a ~> 1.0} and c 1.0.0 -> {a >= 2.0.0}, the valid closure
a 1.0.0 + b 1.0.0 + root was rejected - c's requirement on a outlived the
version of a that wanted c - and an orphan could be installed besides.

**Decision.** Each pass's constraint map is rebuilt from what the root can
*reach* over the picked releases' own dependencies (breadth-first from the
root); anything unreachable is dropped, its requirements included.

**Consequences.** The fixpoint is over the real closure: a version change
takes its old world with it. The test is a four-package fixture graph
(`orphan_*` in the fixture repository) where the old code answered
`{:error, {:no_matching_version, ...}}` and the new one installs a 1.0.0, b
and root - never c.

**Alternatives.** Keeping orphans but ignoring their constraints (they would
still be installed: the install path would carry a package nothing depends
on); iterating over the full graph including unreached names (the bug).

## ADR-040: Mnesia's directory is pinned under /priv

**Status:** accepted (M15)

**Context.** Mnesia defaults to `Mnesia.<node>` relative to the VM's working
directory. Elixos never changes that directory (ADR-016) and the root is the
RAM-backed initramfs, so a schema - the moment anything uses a disc copy, as
Jido's mnesia journal does when asked - would quietly live in memory and die
with the boot. Nothing used disc copies yet, which is exactly why the default
was a trap for whoever touched it next.

**Decision.** `config/config.exs` pins `config :mnesia, dir: ~c"/priv/mnesia"`
for every build. It is pinned there, not in `config/elixos.exs`, because that
file layers only when a build names `MIX_TARGET=elixos` - and the factory's
release does not; the setting is part of the running system's disk layout, so
it must hold wherever the OS is built. Where Jido keeps its state, and whether
that is Mnesia at all, stays an M18 decision.

**Consequences.** Mnesia resolves `/priv/mnesia` before any schema exists; a
unit test asserts the directory is absolute and under `/priv`, and that
Mnesia resolves what was pinned. One gap this does not close and does not
pretend to: because the factory's release is built without
`MIX_TARGET=elixos`, nothing in `config/elixos.exs` reaches the guest today -
`priv_dir` and `heartbeat_ms` ride their code defaults instead (same values,
or the gap would have shown).

**Alternatives.** Leaving it to whoever first creates a schema (the trap);
pinning it in the target config only (inert in the guest, see above); building
the factory as the target (a build change with its own verification, and not
this finding's business).

## ADR-041: The image build is Alpine packages, melange and apko

**Status:** accepted (M16)

**Context.** The factory has been hand-built since M4: musl.cc's cross
toolchain, OpenSSL, ncurses and OTP compiled inside one script, a `mix
release` from the dev host, and a hand-listed rootfs
(`scripts/build-factory.sh`). That was right for one architecture and one
ecosystem. Elixos is now growing Postgres with pgvector and TimescaleDB,
Emerge, a browser and a shell - on musl, for x86_64 *and* aarch64 - and
Alpine already packages most of that for musl on both. Hand-rolled
cross-compiles do not scale to it; pinned sources, checksums and lockfiles
do. ADR-001 stands: the kernel is still the kernel.org tarball plus our
config fragments, never patched - and never Alpine's kernel package, which is
Alpine's configuration, not ours.

**Decision.**
- `build.zig` keeps building everything written in Zig: the shim, the
  drop-privileges helper, later the evdev helper. Still ReleaseSafe.
- melange builds our own signed APKs from pinned sources: the kernel
  (kernel.org tarball + our fragments), OTP 29.1.1, Elixir 1.20.4, the shim
  (`zig build` inside the melange pipeline), the factory release, and the
  on-box toolchain. Every source is fetched by sha256.
- Everything else comes from a pinned stable Alpine release, resolved in a
  lockfile with checksums and served from a local APK mirror, so a build
  cannot drift. Edge is allowed package by package, each with a note here.
- apko assembles the root filesystem from that lockfile; from it come the
  same images the QEMU tests boot today - a kernel plus an initramfs carrying
  `/init` and `/factory` - for both architectures. apko does not run package
  install scripts, so users an image needs (the Postgres uid, M17) are
  declared in the apko config rather than created by a script.
- The old pipeline goes: the cross-build and the musl.cc download are
  deleted, there is no dual pipeline, and the make targets keep their names
  (`make image`, `make test-qemu`).
- melange and apko themselves are pinned by version and sha256.

**Supersedes.** ADR-008's "how the ERTS is built" (the factory's own zig cc
cross toolchain becomes a melange package). ADR-014's "x86_64 only" (both
architectures now). ADR-012's "no sh anywhere": IEx stays the login shell and
the shim still execs `erlexec` directly - never a release script (ADR-012's
actual decision) - but BusyBox sh, from Alpine, is allowed for *tooling*:
building and packaging, never as the system's login or as a shim exec path.

**Consequences.** The build needs melange, apko, bubblewrap, and - for
aarch64 packages on an x86_64 host - QEMU user emulation through
binfmt_misc; `make check-tools` reports them, and melange/apko are pinned in
the tree. Images become reproducible from the lockfile (two builds, one
digest - checked in the build) and each carries an SBOM naming at least the
kernel, OTP and Elixir versions. The dev APK signing key stays out of git; a
release key is a later decision. Image size moves (recorded in M16): before,
initramfs 44M and rootfs 108M (factory 82M, libs 27M); after, recorded when
the pipeline builds. Emerge ships no aarch64 musl NIF (only aarch64 GNU), so
the GUI milestone (M22) needs a source build for aarch64 - noted there.

**Alternatives.** Keeping the hand-rolled cross-build and adding one
cross-compile per new dependency (what this replaces: every new C dependency
is a new toolchain project, times two architectures); building everything
from source in melange (reproducible, but a reimplementation of Alpine for no
reason); Nerves-style Buildroot (a different, host-side model: the point here
is a machine you live inside, and Alpine is the smallest well-packaged musl
distribution).

## Open questions

## ADR-024: Ctrl+C rides with a newline on the console

**Status:** accepted

**Context.** The M5 Ctrl+C test sent a raw `^C` and, with no gap, the next
expression, expecting the interrupted prompt back and that expression to
evaluate. It failed; so does plain OTP + Elixir. Findings (OTP 29.1.1
sources, reproduced with stock `iex --erl "+Bc"` on a pty):

- With `+Bc` ERTS clears the tty's `VINTR` (`erts_replace_intr` in
  erts/emulator/sys/unix/sys.c), so ^C is no signal: the byte reaches the
  program.
- `user_drv` classifies each *read*: a chunk that *contains* Ctrl+C (with
  more bytes after it) is `ctrl_c`, which exits the console's group with
  `interrupt` and **discards the rest of that chunk**; a lone Ctrl+C byte is
  `none` and forwarded as ordinary input (kernel/src/user_drv.erl,
  `contains_ctrl_g_or_ctrl_c`).
- The console tty is **cooked**: only a tty that starts user_drv *with* an
  initial shell gets raw input; `-noshell`'s default is `input => cooked`, so
  the kernel line-edits and delivers a line at a time. A lone ^C waits in the
  kernel's buffer until a newline arrives.

So `^C` + Enter interrupts (and anything after the ^C in that chunk is lost),
while a lone ^C does nothing until a line is completed. `input: :raw` was
tried in the guest and is worse: a lone ^C is then `none`, and Ctrl+C stops
interrupting at all.

**Decision.** The console keeps OTP's default (cooked — the reference `iex`
behaviour), and the test types Ctrl+C the way a keyboard does on it, `\x03\r`,
then waits for the interrupt's visible effect (`** (EXIT) interrupted`, what
stock IEx prints) before typing the next expression, which arrives as its own
chunk and evaluates. What the test asserts is unchanged: the interrupt aborts
the runaway expression and the prompt comes back usable.
`Elixos.Boot.Login` spawns `IEx.Server.run/1` and lets IEx handle the break
itself (`{:EXIT, _, :interrupt}`), exactly as the reference does.

The same classification rule governs Ctrl-G: a chunk is `ctrl_g` only if it
*contains* Ctrl-G with something after it, so the M9 tests send `\a\r` for the
job-control switch. On a keyboard the newline the cooked console needs for
Ctrl-C behaves the same way: the byte is held until the line is complete.

## ADR-025: Crash dumps live on the persistent disk

**Status:** accepted

**Context.** A VM that dies while booting a generation writes `erl_crash.dump`
into its working directory, which is `/`, the initramfs: it lives in RAM, the
next crash overwrites it, and a power-off loses it. By the time the shim has
fallen back to a good generation and a prompt comes up, the reason the bad one
died is gone.

**Decision.** The shim points ERTS at the persistent disk for every launch:
`ERL_CRASH_DUMP=/priv/crash/gen<g>-attempt<n>.dump` (the generation and the
attempt the plan is running) and `ERL_CRASH_DUMP_BYTES=1048576`, so one dump
cannot fill `/priv`. It creates `/priv/crash` before launching and keeps only
the newest five dumps, by modification time, so a crash loop cannot fill the
disk. Without the data disk both variables are left unset and ERTS keeps its
default: there is nowhere durable to put a dump. This is part of the launch
contract (PROTOCOL.md §3) and of the disk layout (PROTOCOL.md §7); the M8
integration test boots a generation that crashes and reads its dump from the
fallback boot's IEx.

## ADR-026: The M9 session test destructures its console helper wrong

**Status:** accepted

**Context.** `test/integration/m09_session_dir_test.exs` takes its output from
`QEMU.expect_with_before/3`, whose documented contract is
`{matched, before, vm}` (test/support/qemu.ex:144), as a two-element tuple:
`{out, vm} = QEMU.expect_with_before(...)`. Every such call raises a
`MatchError` before any assertion runs, so the test could not pass. The tests
shipped with the M9 roadmap change were never run; this one is a transcription
slip, not a statement about the console.

**Decision.** Fix the four destructures (`{_, out, vm}`) and keep every
assertion as it is. No behaviour changes, and the helper keeps its contract.

Decide these with the human. Until then, follow the proposed default.

- **Q10: The capture tracer across an IEx evaluator restart.** A console
  interrupt makes `IEx.Server` replace its evaluator with `rerun(state, [], ...)`,
  which keeps only `:dot_iex` in `evaluator_options` and rebuilds the
  environment from `opts[:env]`, so the traced env of `Elixos.Boot.Recorder`
  is lost and modules defined after an interrupt are not journaled (evidence in
  that module's moduledoc). Proposed default: accept and document it, and fix
  it in the pinned Elixir when we next touch it (one line in
  `lib/iex/lib/iex/server.ex`: take `[:dot_iex, :env]`), rather than wrapping
  or patching IEx at runtime.

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

## ADR-042: Integration tests thread the console through loops, and the harness waits for the echo

**Status:** accepted (M16)

**Context.** M14's "a name in two trusted repositories" test types four
expressions at the console, two per repository. It was written as a `for`
comprehension over the two repositories, and a comprehension discards each
iteration's returned VM: the second iteration typed into a console whose
prompt `QEMU.iex/3` still believed was the boot's first. The contract of
`iex/3` is a console sitting at a prompt the harness has already consumed, so
with that precondition broken the harness matched the first prompt it saw -
the one already on screen - and returned the echoed input alone. The test
failed roughly one run in three, and the failure was twice diagnosed as a
harness timing bug (`docs/notes/melange-apko.md`).

**Decision.**
- A test that types more than one expression must thread the VM from one call
  to the next: `Enum.reduce/3`, or `for ... reduce: vm`. Never a plain `for`
  whose result is dropped.
- `QEMU.iex/3` anchors on the echo of the line it just sent before waiting
  for a prompt whose own number is higher than the one the expression started
  at, and it judges each matched prompt by that number rather than by the
  highest number ever seen. Both are defensive, not a substitute for the
  contract above; the anchor also survives a redraw arriving before the
  result, which is what made the old code look guilty.

**Consequences.** The m14 test asserts what it means to assert - the first
call's result, then `:ok` from the second - on a console whose state it now
tracks. The anchor's cost is a five-second window per call for multi-line
expressions, whose redraws split the echoed text so the echo never matches;
those fall back to the prompt-number wait.
