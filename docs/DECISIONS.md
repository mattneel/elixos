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
that is Mnesia at all, stays an M19 decision.

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
  install scripts, so users an image needs (the Postgres uid, M18) are
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
the GUI milestone (M27) needs a source build for aarch64 - noted there.

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

## ADR-043: Elixos.info carries the architecture

**Status:** accepted (M16)

**Context.** M16 builds for two architectures, and the aarch64 acceptance asks
the running box what it is through the same API the x86_64 tests already read
facts from. `Elixos.Boot.info/0` had generation, mode, attempt and version -
no architecture. The information exists: ERTS knows the target it was built
for. Nothing surfaced it.

**Decision.** `Elixos.Boot.info/0` gains `arch`: the part of
`:erlang.system_info(:system_architecture)` before the first dash, so
`"x86_64"` and `"aarch64"` rather than the full target triple.
`Elixos.Boot.arch/0` is public for callers that want just that. The value
comes from the VM, not from the shim's launch contract (PROTOCOL.md §3): on
the console what matters is what the BEAM is running on.

**Consequences.** The unit test that asserted the map exactly, and the
moduledoc examples in `Elixos.Boot` and `Elixos` (documentation - this repo
runs no doctests), change with it. The aarch64 smoke test's assertion - the
console output contains the architecture - is the acceptance.

## ADR-044: Console job-control tests wait for each ready prompt

**Status:** accepted (M16; M9 acceptance synchronization)

**Context.** The full x86_64 QEMU suite on the packaged image passed 40 of
41 tests. M9's two-session test sent `s` and `c 2` back-to-back after Ctrl-G;
the console showed `s` and another `-->`, but never the connected Erlang
shell. OTP 29.1.1's `lib/kernel/src/user_drv.erl`, `switch_loop/3`, parses one
line with `edlin:edit_line/2` and explicitly discards `_Rest` from that input
chunk. A second command in the same chunk is lost. The other M9 console-job
test already waits for the command prompt and passes.

**Decision.** `m09_session_dir_test.exs` consumes the initial `-->` before a
command, the next `-->` after starting the shell, and the IEx prompt after
reconnecting to the first job. Each command now reaches a driver ready for
that line. This is synchronization, not pacing: no sleeps, retries, widened
regexes, changed assertions or raised timeouts.

**Consequences.** The acceptance still proves two independent session
directories and an unchanged VM cwd. OTP and the OS remain unmodified for
this issue. This ADR covers the protected test change in its own commit;
`make audit` must still report zero violations.

## ADR-045: The agent-toolset roadmap renumbers what has not started

**Status:** accepted (roadmap, after M16)

**Context.** The human queued a new direction behind the build-system switch
(M16): Elixos plus Jido plus the coding-agent toolset, so the machine can
modify itself safely - an escape hatch first, then Postgres, Oban and Ask as
already planned, then the OMP toolset, the on-box coding agent,
self-modification and native hot paths, with the browser and the GUI after
those, in their order. An earlier draft of that roadmap (a crew runtime,
shim modes, OCI images) was withdrawn; container and OCI mode stay a separate
write-up.

**Decision.** The milestones that have not started are renumbered:

| milestone | was |
|---|---|
| M17 The escape hatch: an unprivileged BEAM and sealed commits | new |
| M18 The system database (Postgres) | M17 |
| M19 Jobs that survive reboots (Oban) | M18 |
| M20 Ask the human | M21 |
| M21 The OMP toolset on Elixos | new |
| M22 The on-box coding agent | new |
| M23 Self-modification | new |
| M24 Native hot paths | new |
| M25 A browser to call from the prompt | M19 |
| M26 Installed packages are Mix dependencies | M20 |
| M27 GUI (Emerge on the framebuffer) | M22 |

The installed-packages milestone is not named in the human's order; it keeps
its place between the browser and the GUI, as before. Test files, test module
names, `@moduletag milestone:` tags, the stubs' TODO numbers and every
cross-reference move with their milestone, and each "Done when" names its own
milestone's number (several still carried numbers from before M16 was
inserted). `os/test/test_helper.exs` excludes every milestone above the
current one up to 99, so the bound no longer needs raising each time the
roadmap grows. Two plans change with the new order, not just their numbers:
Postgres runs as its own uid through M17's helper allow-list instead of a
helper the BEAM execs, and the GUI's console handover is a helper while its
devices use the `video` and `input` groups.

**Consequences.** The renumbered acceptance tests change only names and
numbers; no assertion changes, and this ADR is the cover `make audit` asks
for. The audit follows Git-detected, committed renames only when their current
content is covered by an ADR-carrying commit; unapproved deletions and later
uncommitted changes still fail. `MILESTONE` remains 16 in this roadmap commit;
none of the future milestones is started here.

## ADR-046: The BEAM runs unprivileged, commits are sealed, and root is behind the shim

**Status:** accepted (M17; PROTOCOL.md §2, §3 and §6 define the contract)

**Context.** From M21 on, code running in the BEAM includes an agent with a
shell, an editor and a compiler - code that can change Elixos itself. Before
M17 the BEAM ran as root, so anything it ran could rewrite `boot.state`, the
committed generations and the store, which together are the way back from a
bad change. The escape hatch has to be something the BEAM cannot touch.

**Decision.**
- The shim is the trusted base. It execs erlexec as the dedicated `elixos`
  uid (setgroups, setgid, setuid, `PR_SET_NO_NEW_PRIVS`), keeping only the
  ambient capabilities PROTOCOL.md §3 lists - `CAP_NET_BIND_SERVICE`, for the
  SSH daemon on port 22. The account is declared in the apko config (ADR-041:
  no install scripts run).
- `boot.state` is root's and readable (0644); the control pipe stays the
  BEAM's only way to change it. The BEAM writes candidate generations; on
  COMMIT the shim seals the committed one - its manifest and every store blob
  it references become root-owned and 0444. Root owns `/priv`,
  `/priv/generations`, `/priv/store` and the store's fan-out directories;
  writable shared parents are 1777 and prepared by the shim before dropping
  uid. The BEAM cannot unlink, rename or replace a sealed child; merely adding
  a sticky bit to a BEAM-owned directory would not protect it. The factory and
  helper list stay root-owned in the initramfs. Restore reads and verifies
  every blob against its hash before loading any module.
  A mode/owner change does not revoke a retained writable descriptor. Publish
  fresh root-owned inodes containing verified candidate bytes before changing
  `last_good`, unless those inodes were sealed before any BEAM could open them.
  Verify the copied bytes before publication; an old open handle must not be
  able to corrupt a newly committed recovery path.
  `boot.state` is published from a fresh exclusive, no-follow inode in the
  root-private `/priv/.seal` workspace; candidate-owned temporary paths cannot
  supply an already-open descriptor to the new recovery state.
- Anything that needs root moves behind the shim: the image declares an
  allow-list of privileged helpers in `/etc/elixos/helpers` (name, uid and
  gid, absolute path and arguments, exec'd directly, never through a shell).
  The BEAM asks with `HELPER <name>` on the control pipe and reads `HELPER
  <name> OK <pid>` or `HELPER <name> REFUSED` from a reply pipe
  (`ELIXOS_REPLY_FD`); the shim reads the list once at startup, so the BEAM
  cannot add to it, and logs every refusal (`elixos-shim: helper refused
  name=<name>`). Helpers are the shim's children, stopped after the BEAM on
  poweroff, halt and reboot.
  The client serializes the name-only protocol and drains a timed-out active
  request before sending the next, so a late reply cannot answer another
  caller. The helper list is all-or-nothing, fixed storage; malformed or
  oversized lists expose no helpers. The shim's panic handoff carries both
  pipe fds, the actual running generation and helper pids, not a pending NEXT.
- Access that only needs a group - the framebuffer (`video`), input devices
  (`input`) - uses the group, never the allow-list.

**Consequences.** Two PROTOCOL.md changes, both written with the code: the
control protocol (§2) gains the HELPER request and a reply direction, and the
launch contract (§3) gains the uid, the capabilities and `ELIXOS_REPLY_FD`;
the refusal is a console line (§6). The Postgres plan's helper exec'd by the
BEAM is gone (ADR-045): Postgres is an allow-list entry. A candidate can still
break a boot, and the shim still falls back - but no candidate can take the
fallback away.

## ADR-047: The OMP toolset keeps OMP's contract and runs in a peer node

**Status:** withdrawn by ADR-083 (2026-10-13); historical proposal only

**Context.** An agent on the box needs the coding-agent toolset, and prompts
written for OMP should work unchanged. OMP's tools are TypeScript on Bun.
QuickBEAM runs JavaScript in QuickJS through a NIF: in the main VM, a crash in
that engine would take down the VM that holds the prompt, the services and
the heartbeat the shim watches.

**Decision.**
- Scope: every tool the pinned OMP SDK's factories construct (35 at
  `@oh-my-pi/pi-coding-agent` 18.8.7), with the same names, parameters,
  outputs and error behaviour. The pinned OMP is the reference; the pin and
  the inventory live in `os/test/fixtures/omp/inventory.exs`, and moving the
  pin is a note here plus re-recorded fixtures.
- The first implementation is OMP's TypeScript in QuickBEAM, inside a peer
  node (`:peer`) that the main VM supervises - never inside the main VM - run
  with `apis: false`, memory limits, reduction limits and per-call timeouts
  (`apis: [:node]` would let `process.env` writes reach `System.put_env/2`,
  which is VM-global, ADR-016).
  Use `QuickBEAM.ContextPool` and `QuickBEAM.Context`: in 0.11.3
  `QuickBEAM.start/1` does not forward `:max_reductions`. Memory and reduction
  budgets are per-context; the timeout belongs to every eval/call. Acceptance
  must exercise these limits and disabled APIs, not merely inspect a keyword
  list that the runtime could ignore.
- Each tool is a pure core plus Elixir effect handlers - processes, files,
  globbing, the network - scoped to the calling session's workspace and M9
  session directory. External binaries come from Alpine packages; an OMP
  native addon QuickBEAM cannot load is reimplemented in Elixir or Zig.
- Differential tests against fixtures recorded from the reference cover every
  tool, outputs and failure semantics alike; shadow runs compare pure results
  only. A dispatcher picks the implementation before each call and records
  which one ran. A tool that needs a later milestone waits for it.
- Generation configuration in the always-loaded `config/config.exs` can select
  an Elixir or native module per tool; an absent entry uses QuickBEAM.
  `Elixos.Toolset.Implementation.call/2` receives OMP parameters and the
  isolated session. Runtime promotion or reversion (M24) overrides that
  selection without changing callers. The optional target config is not the
  source of this generation-wide decision (ADR-040).

**Consequences.** A QuickJS crash costs one call, not the machine: the caller
gets an error, the peer is restarted, and the shim never sees a missed
heartbeat. Every crossing of the peer boundary copies its terms - the price of
that isolation, and the measurement M24 starts from.

## ADR-048: The agent's prompt and tools are generation content

**Status:** withdrawn by ADR-083 (2026-10-13); historical proposal only

**Context.** The on-box agent's system prompt and tool selection decide what
it does. If they lived outside the image, a change to them would be the one
change Elixos could not roll back, and rescue would run whatever was last
written instead of something known good.

**Decision.** The agent's system prompt and its toolset are code: they live in
the generation like every other module, saved, NEXT'd and committed through
the same path, restored by a fallback, and in rescue the factory's. Project
instructions come from the `AGENTS.md` of the repository the agent is working
in, as in OMP - those belong to the project, not to the OS. Model credentials
are the exception the other way: they live in `/priv/credentials/`, outside any
generation, and are never written to a log, the journal or a crash dump.

**Consequences.** A bad prompt is a bad generation: the attempt counter and
the fallback deal with it like any other. Changing the agent is a commit, with
a manifest that says who made it (ADR-049).

## ADR-049: Self-modification goes through generations only

**Status:** withdrawn by ADR-083 (2026-10-13); historical proposal only

**Context.** The agent can change Elixos itself: OS code, its own tools, its
own prompt. Hot code loading would let such a change reach the running system
with no test run, no health check and no way back.

**Decision.**
- Code the agent writes never loads into the main VM. A candidate is built in
  a child ERTS (M11), tested in a peer node against the full portable system
  unit suite and the toolset's recorded fixture/smoke suite, then booted as a
  generation: NEXT, reboot, health checks, then COMMIT or fallback. Hot loading
  from an agent session is refused.
- The AutoCommit health predicate becomes real checks - the system's tests and
  toolset smoke tests - not liveness.
- The portable suite excludes host candidate-build orchestration and QEMU
  provisioning, not runtime behavior. Candidate orchestration tests carry
  `:host_orchestration` so validation cannot recursively build and validate
  itself. Boot health runs the same portable and tool suites as pre-boot
  validation, in a peer; real core and selected-tool defects must fail them.
- A failed candidate's evidence (crash dump, logs, the failing check) is kept
  under `/priv/evidence/<generation>/`; fallback never deletes it.
- Each generation's manifest records what produced it: the session, the model,
  the tool revisions and the parent generation.
- A rollback restores code and the image's state, not the world: messages
  sent, payments made and migrations run stay done. Migrations follow the
  expand-before-commit rule: a generation ships only migrations its parent can
  ignore.

**Consequences.** Self-modification is as slow as a reboot and as safe as the
generation machinery plus ADR-046's sealing. A change that breaks the boot
costs an attempt, not the machine; factory rescue runs the factory's agent.

## ADR-050: Native code is promoted on evidence, one hot path at a time

**Status:** withdrawn by ADR-083 (2026-10-13); historical proposal only

**Context.** Some toolset paths will be hot, and Zig through Zigler can make
them faster. A native function also runs inside whichever VM loads it: one
crash there is a crash of that VM, and an unbounded synchronous NIF stalls a
scheduler.

**Decision.**
- Port only measured hot paths, as pure functions. Promote one only after it
  passes the differential suite and a p99 latency benchmark under concurrent
  sessions, conversion overhead included.
- Synchronous NIFs only for bounded work well under 1 ms; anything longer runs
  dirty or threaded, with admission limits.
- Unproven native code runs in the peer node; a promoted implementation moves
  into the main VM only if latency demands it.
- Generation manifests pin native libraries content-addressed (each version
  its own file name), the target and the toolchain. Zigler's Zig, which
  `mix zig.get` would fetch, is pinned and baked into the toolchain package.
- The dispatcher can revert one tool's implementation; that reverts the
  implementation, not the environment.

**Consequences.** Native speed is earned per function and reversible per tool,
and a native crash before promotion costs only the peer.

## ADR-051: Agent IDs remain strings, not permanent atoms

**Status:** accepted

**Context.** Plain-agent registration used `String.to_atom("elixos.agent.#{id}")`.
A disposable BEAM probe retained all 5,000 generated names after garbage
collection. That establishes an atom leak, not agent capacity: an atom is
never collected, even after the agent stops.

**Decision.** Register plain-agent child pids with OTP's `:global`, using
`{Elixos.Agents, supervisor_pid, binary_id}` as the key. No ID-derived atom is
created. The supervisor pid scopes names to this tree, including connected
peer instances and distribution started after the agents. OTP monitors the
registered child and removes the name when it exits; supervisor restarts
register the replacement under the same key. Jido's existing string-keyed
registry is unchanged.

The supervisor's child-start MFA must register another process, not itself.
`:global.register_name/2` supports that; `Registry.register/3` does not.
This preserves generic agents' `start_link/1` contract without imposing a
`:name` option or adding a second custom registry process.

**Consequences.** Registration uses OTP's distributed coordination when peers
are connected. A disposable, isolated BEAM exercised lookup, duplicate
rejection, crash/restart, snapshots and 256 sequential start/stop lifecycles
with zero added atoms after warm-up. Maximum live agents was one: this is
lifecycle/retention evidence, not a capacity result.

## ADR-052: Heavy services live in a read-only system image

**Status:** accepted (M18)

**Context.** The factory must remain the rescue minimum. PostgreSQL 17 alone
adds 15.2 MiB installed; its Apache-only TimescaleDB extension adds 11.6 MiB
before the client and shared-library closure. Both targets require built-in
loop devices and gzip SquashFS; the common kernel fragment requires them.
Changing that fragment requires rebuilding the cached kernel APK.

**Decision.** Assemble a separate, architecture-specific Alpine package set
with apko and committed lockfiles, then pack a reproducible gzip SquashFS.
The pristine disk carries it at `/priv/system/system.squashfs`, under a
root-owned directory excluded from the writable-state ownership migration.
PID 1 opens the root-owned, non-writable regular file without following
symlinks, attaches it to a read-only loop device and mounts it at `/system`
only for normal launches. Rescue starts without that mount or its services.
Mount failure disables the service, not the prompt. No kernel patches.
The image also supplies ICU and timezone data at Alpine's compiled-in
absolute paths. PID 1 exports just those two read-only directories into
empty factory mount points, and releases the exports before `/system`.
Neither the factory nor the BEAM carries a mutable duplicate of the data.

Keep PostgreSQL 17 from Alpine v3.24. The current v3.24 extensions require
PostgreSQL 18, so select only the PG17-compatible extensions from a tagged
v3.22 community repository: pgvector 0.6.2-r1 and TimescaleDB 2.17.2-r1.
The server and shared-library closure stay on v3.24. These are signed Alpine
packages pinned by the system lockfiles, not another PostgreSQL build.
Alpine's TimescaleDB build explicitly sets `APACHE_ONLY=ON`; no Timescale
License features ship.

**Consequences.** The factory carries only the account and native init guard,
not the database binaries. A system-image change is a disk/image build, not
a mutation of the mounted service. The older extension pins are deliberate
PG17 ABI choices and must be reviewed with any PostgreSQL major upgrade.

Sources: [PG17 package](https://pkgs.alpinelinux.org/package/v3.24/main/x86_64/postgresql17),
[PG17 extensions](https://pkgs.alpinelinux.org/package/v3.22/community/aarch64/postgresql-pgvector),
[Apache-only build](https://gitlab.alpinelinux.org/alpine/aports/-/raw/3.22-stable/community/postgresql-timescaledb/APKBUILD).

## ADR-053: PID 1 owns PostgreSQL's identity and clean shutdown

**Status:** accepted (M18)

**Decision.** Declare `postgres` as uid/gid 70 in the factory. PID 1 prepares
`/priv/postgres/data` owned by that account, mode 0700, and
`/priv/postgres/log` owned by it, mode 0755. Log files are 0644 so the single
user can read the shutdown evidence without access to the cluster files.

Two fixed allow-listed helpers run without supplementary groups or BEAM
capabilities: `postgres-init` executes a libc-free native guard which skips
an existing `PG_VERSION` and otherwise directly execs Alpine's `initdb`;
`postgres` directly execs the postmaster. Their paths and argv are image
policy. Dynamic libraries come from `/system` through a fixed child-only
environment; nothing changes the main VM's cwd or environment.

The postmaster listens only on loopback with local trust authentication,
loads `timescaledb` before accepting queries, and writes persistent logs.
The Elixir manager starts asynchronously in normal mode before either login
frontend can issue a query; readiness requires a successful real query. A failed
start is non-critical and remains visible to callers and the console.

On halt, reboot or power-off, the BEAM stops first while its database remains
available. PID 1 then sends the postmaster SIGINT (fast shutdown), waits for
its exit for up to 30 seconds, and only then stops remaining helpers, syncs
and unmounts. A deadline failure is logged before SIGKILL; it is not reported
as a clean database shutdown. Panic adoption retains the helper pid and the
same shutdown policy.

**Consequences.** An initialized cluster survives boots without rerunning
`initdb`. Oban's Repo can use the database until the VM stops. Rescue is still
the factory with the persistent disk, not a database-dependent boot.

## ADR-054: QEMU expression evaluation consumes the whole multiline block

**Status:** accepted (M18)

**Problem.** `QEMU.iex/3` returned at the first completed prompt after sending
several top-level statements. M18's unchanged ownership probe consequently
returned only `Elixos.Postgres.status/0`, before its final assertion map.
The VM cursor then disagreed with the console's actual evaluation state.

**Decision.** Wrap multiline `iex/3` input in one parenthesized IEx block.
The next completed prompt now follows the entire supplied expression.
Keep single-line input and the raw interactive input helpers unchanged.
No acceptance assertion, matching expression or timeout is weakened.

**Consequences.** Existing multiline probes exercise all their statements
and retain their IEx bindings. The unchanged M18 integration test covers
this path through real database ownership, extensions and shutdown checks.

## ADR-055: Power off each database guest before the next boot

**Status:** accepted (M18)

**Problem.** M18's reference fixture checked the second boot's clean
PostgreSQL log, then launched rescue with the same writable disk while that
guest was still alive. QEMU correctly refused the second writer's disk lock.
All preceding database assertions passed; rescue never started.

**Decision.** Thread the final normal-mode VM handle and use the fixture's
existing power-off helper before booting rescue. It asserts QEMU's zero
exit status and absence of a kernel panic. Keep every database and rescue
assertion, regex and timeout unchanged.

**Consequences.** The fixture represents three sequential power-ons rather
than two concurrent writers. This acceptance-fixture correction is committed
separately from the M18 implementation.

## ADR-056: Declaration coverage includes the service-image native modules

**Status:** accepted (M18)

**Decision.** Extend the shim's existing `refAllDecls` test with
`system_image` and `postgres_init`, preserving every existing reference.
The standalone init guard is also a real build target, not a lazily
unreferenced declaration. This is the coverage required by AGENTS.md for
new files on the pinned Zig nightly.

**Consequences.** The protected test block is stronger, not relaxed.
The host runs all 64 unit tests and both release targets compile. Record
this addition with the native implementation so the acceptance audit can
distinguish added compiler coverage from an unapproved test change.

## ADR-057: Oban is an OS dependency on the system database

**Status:** accepted (M19)

**Context.** Jobs must survive a power cycle and retry: the state that makes
that true is Postgres (M18), and what turns it into a scheduler is Oban.
The factory ships OTP and Elixir from its own packages, and every runtime
dependency of `os/` needs an ADR. Oban's own schema also has to exist before
its first queue - the factory build has no `mix ecto.migrate` and no shell
(ADR-012).

**Decision.** `oban 2.24.1`, `ecto_sql 3.14.0` and `postgrex 0.22.4` are
direct dependencies of `os/`. Their whole closure is pure BEAM (no NIFs, no
ports, no build step beyond compilation), so they cross-build with everything
else and ship in the factory release.

One `Ecto.Repo` (`Elixos.Oban.Repo`) connects to M18's database as the
`postgres` role over loopback - the same host, role and database
`Elixos.Postgres.query/1` already uses, with `-A trust` authentication
(ADR-053). There is no second database and no password to carry: the
postmaster listens on loopback only and refuses everything else. The
connection lives in `config :elixos, Elixos.Oban.Repo`, not only in
`Ecto.Repo.start_link/1` options, because `Ecto.Repo.config/0` - the app
environment - is what Oban's notifier, peer and engine read to open their own
connections; options passed only to `start_link/1` leave them with nothing.

`Elixos.Oban.Manager` owns the lifecycle and is not boot-critical: wait for
Postgres, start the Repo, run Oban's schema as a real Ecto migration
(`Elixos.Oban.Migration` -> `Oban.Migrations.up/1`, recorded in
`schema_migrations`), and only then start Oban - and only after
`Elixos.Oban.activate/0`, which `Elixos.Application` calls once the
supervision tree is up. The manager starts *before* `Elixos.Boot.Restore`,
so a generation's `configure_app!/2` boot MFAs are collected while the image
restores and no queue can run against a half-restored image. A refused
declaration raises, so the boot fails and the shim falls back (ADR-007)
rather than booting half-configured.

An app's `elixos:` key gains `oban: [queues: [name: limit], cron:
[{expression, module}]]`, validated by `Elixos.Oban.Declaration` (five-field
expressions, positive limits, worker modules). The declaration is persisted
with the app's services and requirements in one journal entry, and becomes a
boot MFA. Queue names under `elixos_` are reserved for the system. Two apps
may share a queue only when they agree on the limit; a disagreement is
refused, never silently overwritten. Live installs and removals change the
real queues through Oban's own API; a cron change restarts the Oban
supervisor with the new plugin list while the Repo stays up.

**Consequences.** A job enqueued at the prompt is a row in Postgres the
moment it is accepted, and a scheduled job runs after a power cycle because
its worker module comes back with the generation. There is no scheduler in
rescue, and none appears when Postgres fails: `status/0` stays
`{:error, :not_running}`. Stopping the VM stops Oban before the shim stops
Postgres, so an interrupted power-off costs an incomplete job's retry, not
its row. A future Oban upgrade that changes the schema is one new version in
`Elixos.Oban.Migration`.

## ADR-058: The M19 fixture powers off before its rescue boot

**Status:** accepted (M19)

**Problem.** The same defect ADR-055 fixed in M18's fixture was present in
M19's: after the scheduled job ran, the test booted rescue with the same
writable disk while the second guest was still running. QEMU refused the
second writer's disk lock. Every assertion before that point passed - the
module came back from the image and the scheduled job ran - so the failure
was in the fixture, not the scheduler.

**Decision.** Use the fixture's own `power_off/1` before the rescue boot, and
keep the VM handle it needs (`_vm` becomes `vm`). That helper asserts QEMU's
zero exit status and the absence of a kernel panic, so the fifth power-on
starts from a disk nobody else holds. No assertion, regex or timeout is
weakened.

**Consequences.** The M19 acceptance is three normal power-ons plus one rescue
power-on, strictly sequential. Both fixtures now follow the same rule; a
future test that boots a second guest on one disk must power the first off.

## ADR-059: Questions are data; the console is the first front-end

**Status:** accepted (M20)

**Context.** An agent needs to ask the human something and act on the answer
(M20, M22). The answer must be checked against the question - a front-end must
not be able to hand back a value the question never allowed - and the same
question has to work from the console, from an ssh session (M12), and from the
framebuffer GUI (M27). Putting any of that in the asking agent makes every
front-end a special case.

**Decision.** `Elixos.Ask` is one queue in the OS supervision tree (normal
mode; rescue starts none of it), holding open questions as data:
`id`, `kind` (`:text | :choice | :multi | :confirm`), `prompt`, `options`,
`allow_other`, an optional `default`, the asking process, and when it was
asked. `ask/2` blocks the asker until the question is resolved; `pending/0`
lists what is open, oldest first; `answer/2` and `dismiss/1` resolve by id.
An answer is validated against its question before it is accepted: a choice
must be one of its options (or free text when the question offered it), a
multi a non-empty subset of them, a confirm a boolean, a text a binary. A
timeout is resolved server-side and answers `{:error, :timeout}`; a dismissed
question answers `{:error, :dismissed}`; an asker that goes away has its
questions dismissed rather than answered by guesswork.

The console REPL is the first front-end and prints one notice line per new
question - `elixos-ask: question <id> (<kind>): <prompt>`, documented in
PROTOCOL.md §6 and matched byte for byte by the M20 acceptance. Answering is
any front-end's job; the prompt does it with `Elixos.Ask.answer/2`.
`Elixos.Ask.Action` is the Jido action (`ask_human`) that lets an agent route
a signal to the queue and carry the answer into its own state, so an agent
asks the same way it does anything else.

**Consequences.** A question is VM state, not disk state: it does not survive
a power cycle, which is honest - the human it was addressed to is the console
or the GUI, and both are gone when the machine is. The M20 acceptance asks
from an agent, sees the notice on the console, answers at the prompt, and
finds the answer in the agent's state. M27 adds a second view over the same
queue without touching the askers.

## ADR-060: aarch64 is cross-built on the host, not emulated

**Status:** accepted (M19)

**Context.** Every package whose recipe runs in an aarch64 melange environment
runs its *compiler* through `qemu-aarch64-static` (ADR-041: "slower but fine").
Measured on this host, that is not fine: the arm64 kernel alone spends ~25
minutes compiling under emulation, and the whole aarch64 image used to take
45-60 minutes - for the same bytes a native compiler produces in a few minutes.
Two facts make most of that avoidable. A melange pipeline runs *inside the
target rootfs*, so a cross build cannot happen in it. And three of the four
built packages are not architecture-specific at all.

**Decision.** Cross-build the arm64 artifacts natively, on the build host, and
have the aarch64 package install them:

* **Kernel** - `melange/kernel-cross.yaml` (an x86_64 build-tool package)
  compiles `arch/arm64/boot/Image` with the kernel's own `LLVM=1` cross mode
  (native clang/lld, no libc, no sysroot: the kernel is freestanding) and runs
  the same config merge and `check-kernel-config.sh` guard as the target
  build. `scripts/build-image.sh` stages the result and `melange/kernel.yaml`'s
  aarch64 branch installs it instead of compiling; the emulated branch stays
  for a checkout that has no staging. `boot/config.aarch64` travels with the
  image so the config that produced it is inspectable. 25 minutes become ~5.
* **Elixir and the factory** - both are bytecode, shell scripts and symlinks
  into the machine's own OTP (`include_erts: false`); nothing in them depends
  on the target architecture. The x86_64 build already builds them natively,
  so the aarch64 packages install that same tree (`native_reuse` in
  `scripts/build-image.sh`, a `prebuilt/` branch in each recipe). One build
  serves both architectures, and an emulated `mix release` disappears.
* **Shim and toolchain** were already native (`zig build -Dtarget=…`).
* **OTP** - `melange/otp-cross.yaml`, the same shape as the kernel's: OTP's
  own cross mode (`erl_xcomp_*` answers configure's runtime probes), the
  x86_64 `elixos-otp` package as the bootstrap ERTS that compiles the target's
  Erlang sources, Alpine's clang as the compiler, and a sysroot of Alpine's own
  aarch64 packages - libc, GCC's runtime and C++ standard library, and
  openssl/ncurses/zlib - installed by apk. About 80 seconds instead of about 13
  minutes. Two properties only a boot would otherwise reveal are checked at
  build time: `dlopen` present in the emulator (without it every NIF fails with
  "Dynamic loading not supported"), and the NIF API in `.dynsym` (without it
  every NIF fails to relocate).

Zig is the cross compiler where the build system is ours: the shim and
`postgres-init` are `zig build -Dtarget=aarch64-linux-none`. For the kernel it
is clang: Kbuild's `LLVM=1` mode appends its own `--target` triple and expects
a clang driver, and Zig's clang-shaped driver accepts those arguments and then
silently produces no output for the `-S` steps Kbuild needs. `build.zig`
cannot drive Kbuild, autotools or Mix - it is not a general make replacement -
so those builds stay their own build systems, with the *compiler* and the
*host* doing the crossing.

**Consequences.** An aarch64 image rebuild costs about five minutes of kernel
plus the assembly, instead of an hour, and nothing in that path emulates a
compiler for the kernel, Elixir, the factory or OTP. The artifacts are verifiable the same way as before - `test-qemu-aarch64` boots
the image on `qemu-system-aarch64` and the M16 acceptance defines a module,
saves it and power-cycles - and the kernel's own config guard still runs on
the cross-compiled config. A cross-built artifact is part of the package
inputs, so changing the kernel config or the OS source invalidates exactly the
packages it should.

## ADR-061: The M20 fixture unwraps the AgentServer state it polls

**Status:** accepted (M20)

**Problem.** `m20_ask_test.exs`'s state poll reads

    Jido.AgentServer.state(Elixos.Agents.whereis("asker")).agent.state

but the pinned Jido (2.4.0) returns `{:ok, %Jido.AgentServer{}}` from
`state/1`; calling `.agent` on that tuple raises `BadMapError` inside the
guest, so the expression can never return `true` and the poll times out. The
M15 acceptance - same library, same call - unwraps the tuple first
(`{:ok, state} = Jido.AgentServer.state(...)`), which is what the API does.
Every earlier assertion in the M20 test passes: the agent starts, the
question reaches the queue, the console prints the notice line, `answer/2`
returns `:ok`, and the guest's dump shows `state: %{answer: "matt"}` - the
action does return the answer into the agent's state; only the fixture's
reading of it is wrong.

**Decision.** Unwrap the tuple in the polling expression, exactly as the M15
fixture does, and keep the assertion identical (the state must contain the
answer). No assertion, regex, retry count or timeout is weakened, and the
test still fails if the action does not put the answer into the state.

**Consequences.** The M20 acceptance tests the claim it was written to test.
The commit that changes it carries this ADR, as the audit requires; the change
is committed on its own, separately from the milestone's implementation.

## ADR-062: Service initialization output goes to its log, not the console

**Status:** accepted (M20)

**Context.** The database and the scheduler start before the image restore
(ADR-057) so that a generation's declarations are collected while it restores.
That puts `initdb` - which narrates every step of creating a cluster, around
forty lines - *during* the first prompt instead of before it. The console is
the shim's and the REPL's (PROTOCOL.md §6), and the QEMU acceptance reads it
byte for byte: M04's `1 + 1` result landed inside an initdb line
(`selecting default "max_connections" ... 2`) and `^2$` was not there.

**Decision.** `postgres-init` - the guard that execs `initdb` (ADR-053) -
points its own stdout and stderr at `/priv/postgres/log/initdb.log` with
`dup2`, mode 0644 in the uid-70-owned log directory, before the exec. The
postmaster already logs there (`logging_collector`), so the cluster's whole
story lives in one place. If the log cannot be opened the output stays on the
console: nothing is ever silently discarded, and the guard never fails for
this. The postmaster's own early errors keep going to the console, where a
rare, fatal startup message belongs.

**Consequences.** A fresh boot's console is deterministic - shim lines, Ask
notices and the REPL - so console assertions no longer race a background
service's narration, and a failed `initdb` is recorded on the disk instead of
scrolling away. PROTOCOL.md §7 carries the new path, and the M04, M18, M19 and
M20 acceptances were re-run against it.

## ADR-063: The agent arc (M21-M24) is deferred; the list resumes at M25

**Status:** superseded by ADR-083 (2026-10-13); the arc is withdrawn, not deferred

**Context.** M21 pins the OMP toolset: an inventory taken from
`@oh-my-pi/pi-coding-agent`, with fixtures that assert our implementation
matches that pin. M22-M24 build on those tools - the on-box coding agent, the
self-modification loop, the native hot paths - and reference them throughout
(the self-modification and native-hot-path tests most of all). That toolset
belongs to the human's own agent work (`~/src/clanklet`), so building it here
means pinning a target that is still moving.

**Decision.** Do not start M21-M24 now; start at M25 instead. Their tests stay
in the suite unchanged and tagged `:deferred`, so the specification for that
arc survives and `make test` keeps meaning something. `test/test_helper.exs`
excludes the tag in both modes, each of the four roadmap sections says in place
that it is deferred, and this ADR is the reason on record.

**Consequences.** `MILESTONE` moves to 25 with M21-M24 not green: the gate is a
linear count, so a deferral has to be expressed by a tag rather than a hole in
the numbering. To resume the arc, delete the `:deferred` lines (this ADR already
covers that change to the shipped tests), set `MILESTONE` back to 21 and work
the tests in order. Nothing in M25-M27 depends on the toolset: the browser
test's two toolset references are re-scoped to `Elixos.Browser` directly, and
M26's tests never mention it.

## ADR-064: M25 ships Lightpanda with a private glibc, not a musl rebuild

**Status:** accepted (M25)

**Context.** M25 wants a headless browser in the image, callable from IEx:
navigate, extract, evaluate JavaScript, screenshot, nothing downloaded at run
time. The milestone's own gate is to run `ldd` on the pinned binary first, and
explicitly allows abandoning M25.

**Gate (measured).** Lightpanda 1.0.0's published `lightpanda-x86_64-linux` is
an ELF "for GNU/Linux" whose only `NEEDED` entries are `libc.so.6`,
`libm.so.6` and `ld-linux-x86-64.so.2` - and it prints `1.0.0` when run through
a *private* copy of exactly those three files:

    ./glibc/lib/ld-linux-x86-64.so.2 --library-path /tmp/lp/glibc/lib ./lp version
    1.0.0

That is the roadmap's second arm. Alpine ships no glibc (`gcompat` is a shim,
not a libc), and rebuilding Lightpanda means rebuilding V8 for musl - the last
resort the roadmap names.

**Decision.** Ship the pinned upstream binary, stripped (188 MB → 70 MB), at
`/system/browser/lightpanda`, and with it the three glibc files it needs from
Debian stable's `libc6` package (2.41-12+deb13u4, 2.8 MB amd64 / 2.5 MB arm64,
pinned by SHA-256, LGPL, unmodified) - installed at the paths glibc itself
insists on: the loader at `/lib64/ld-linux-x86-64.so.2` (arm64:
`/lib/ld-linux-aarch64.so.1`) and the libraries in `/lib/<triple>/`, which is
where the ELF interpreter embedded in the binary looks. Alpine keeps nothing
there (musl lives in `/lib/ld-musl-*.so.1`), so nothing is shadowed and the
*unmodified* upstream binary runs as itself. That matters beyond tidiness: the
ecosystem's server spawns the program it is handed without arguments of ours,
so a loader indirection would not fit. `command/1` still understands a
`loader` entry - the milestone's tests cover that arm - but the shipped manifest
needs no loader. The aarch64 binary takes `ld-linux-aarch64.so.1`.

**Consequences.** Each image grows by about 73 MB (70 MB browser, 3 MB glibc),
which the initramfs carries too. Only Lightpanda sees the private glibc: it
sits in the standard glibc directories, which nothing else on this musl system
reads, and the system stays musl. `Elixos.Browser` starts the adapter in normal
mode only and stops it on poweroff, so rescue never has a browser running - and
the QEMU acceptance asserts exactly that. The musl rebuild stays possible, but
the pinned upstream binary is what the milestone asked to evaluate first.

## ADR-065: The browser leans on the ecosystem, and the box carries Rust

**Status:** accepted (M25; human decision - an earlier draft of this ADR said
"the CDP client is ours", which was overruled)

**Context.** Driving Lightpanda means speaking CDP over a WebSocket: `serve`
starts a WebSocket CDP server and that is its only persistent interface. The
first draft of this milestone hand-wrote that client (about 240 lines) to keep
the OS dependency-free. The human's decision is the opposite, and it is the
better fit for what Elixos is: **lean on the ecosystem while we can**, and own
only the trust decision - which binary, pinned and verified - plus a thin
wrapper. Hex has the pieces, inspected before adopting:

| package | role | deps |
|---|---|---|
| `jido_browser` | the adapter layer the roadmap named as an OS dependency | `jido`, `jido_action`, `zoi`, `splode`, `req`, `jason`, `uniq`, `floki`, `html2markdown`, `extractous_ex`, `nimble_pool`, `domainatrex`, `typed_struct` |
| `cdp_ex` | the CDP client: attach mode (`connect:`), `navigate`, `evaluate`, `html`, `screenshot` | `mint_web_socket`, `jason`, `telemetry` |
| `light_cdp` | what the adapter reaches for by default | `websockex`, `jason`, `req`, **`erlexec`**, `telemetry` |
| `lightpanda` | installer and `Server` for the binary | `castore` |

**Decision.** `Elixos.Browser` stays the surface the milestone's tests describe
(`command/0,1`, `status/0`, `navigate/1`, `eval/1`, `screenshot/0`). The
protocol is the ecosystem's - `cdp_ex`, whose dependencies are `mint_web_socket`,
`jason` and `telemetry` - wrapped in `Elixos.Browser.CDP`: the *same* session
and page interface `jido_browser`'s Lightpanda adapter expects, with the browser
process started here as a `Port`. Two packages are deliberately not
dependencies, each for a reason worth recording:

* `light_cdp` (the adapter's default client) spawns the browser through
  `erlexec`, which prints `SHELL environment variable not set! [exec.cpp:658]`
  and exits 4 before any browser exists. `SHELL` is precisely the variable this
  OS must not invent (ADR-012: no shell in the system), and it would be set for
  a launcher whose whole job here is to start one binary - which a `Port` does,
  and which the shim already does for PID 1.
* `jido_browser` itself hard-depends on `extractous_ex`, whose Rust crate
  downloads a **GraalVM JDK** and **Apache Tika** natives and whose build
  script fails on musl:

      Extracting GraalVM JDK archive …/graalvm-ce-archive.tar.gz
      error: failed to run custom build command for `extractous v0.3.0`

  A JVM-shaped, glibc-shaped document extractor is not something to force into
  this image for a browser.

Because the interface implemented here *is* the one that adapter calls, either
package is one line away if that changes - `{:jido_browser, "~> 2.3"}` and the
two `light_cdp_module:`/`page_module:` options already point at the modules
above. `lightpanda` (the package) is not a dependency either: it exists to
download the binary and to own it, and both are this milestone's own business -
the binary is pinned and verified by `melange/browser.yaml` (ADR-064).

The Rust toolchain in the image (ADR-066) is *not* a M25 requirement: it was
built because the human asked for it as a capability, and M25 turned out not to
need a Rust NIF at all.

Native dependencies are not ruled out - the on-box toolchain carries Rust
precisely so the box can build Rustler NIFs (ADR-066) - but each one has to be
worth the build chain it drags along, and for a browser, `extractous_ex`'s
GraalVM and Tika were not.

**Consequences.** The OS gains a dependency tree it does not control, in
exchange for not maintaining a protocol implementation; the milestone's tests
do not change, because the surface does not. Two real costs are recorded:
the aarch64 image can no longer simply reuse the x86_64 factory byte-for-byte
once NIFs are involved (they are architecture-specific, so the factory is
built per architecture, or the NIFs are cross-built - the existing Zig/clang
cross toolchain has the pieces), and the browser's glibc is shipped at the
standard glibc paths (`/lib64/ld-linux-x86-64.so.2`, `/lib/x86_64-linux-gnu/`)
so that the *unmodified* upstream binary and the ecosystem packages that spawn
it can be used as-is: Alpine has nothing at those paths (musl lives in
`/lib/ld-musl-*.so.1`), so nothing is shadowed.

## ADR-066: The on-box toolchain carries Rust as well as Zig

**Status:** accepted (M25; human decision)

**Context.** ADR-009 ships a toolchain on the machine rather than in the
factory: Zig, fetched into `/priv/toolchain`, with `Elixos.Zig` as its API -
because a NIF is built *on the box*, and Zigler needs Zig. Rustler needs Rust,
and M25 is the first thing that needs Rustler: `jido_browser` depends on
`extractous_ex`, whose published NIFs are glibc only
(`x86_64`/`aarch64-unknown-linux-gnu`), so on a musl system they must be built
from source (`rustler_precompiled` with `force_build`). The same capability is
what the desktop work will want later, so it is built as a capability, not as a
M25 workaround.

**Decision.** `elixos-toolchain` carries Rust beside Zig. Alpine's `rust` and
`cargo` (1.96.1, both architectures) are installed by apk into a prefix of
their own under the toolchain directory - `apk add --root`, so the packages'
whole closure arrives with them and nothing is enumerated by hand. The linker
is the toolchain's own `cc`, the Zig bridge, declared in a `config.toml`
(`[target.<triple>] linker = "/priv/toolchain/cc"`) that `Elixos.Rust` points
`CARGO_HOME` at; the cache lives machine-wide in `/priv/cache/cargo`, the way
`ZIG_GLOBAL_CACHE_DIR` does. `Elixos.Rust` is the API (`init/1`, `cargo/2`,
`rustc/2`), running builds in the calling session's directory like every other
command (ADR-019, ADR-020).

**Consequences.** The disk toolchain grows from about 407 MB to about 630 MB
(rust is 202 MB installed, cargo 22 MB), which the 2 GB data image absorbs but
should not be forgotten. Nothing in the factory or the shim changes: the
toolchain is still a tool on the data disk, never in the root filesystem
(ADR-009), and PID 1 stays Zig. The Rust that runs on the box is the box's own
architecture, from the distribution, so there is no second compiler to
cross-build for the toolchain itself. Rust NIFs are architecture-specific,
which is the one thing this capability costs elsewhere: the day a dependency
carries one, the aarch64 image can no longer reuse the x86_64 factory
byte-for-byte - the factory would be built per architecture, or its NIFs
cross-built with the Zig and clang cross toolchain ADR-060 established. Today
no dependency carries a NIF, so that day is not here; M25 was expected to
bring one and did not (ADR-065).

## ADR-067: M25's acceptance releases the disk before its rescue boot

**Status:** accepted (M25)

**Context.** The browser milestone's acceptance checks two boots of one disk:
the normal system, where the browser runs, and the rescue system, where it must
not. It booted the second the way other milestones do, and QEMU refused:

    Is another process using the image [.../disk.img]?

The VMs in other tests can share a disk file across boots because the *guest*
shuts itself down first. Here the first VM was still running - nothing had
asked it to stop - and a qemu holds its disk image while it lives.

**Decision.** Stop the first VM (`QEMU.stop/1`) before booting the rescue one.
The disk's *contents* are what the second boot is about; the first VM has no
further role in the test.

**Consequences.** The assertion is unchanged - rescue runs no browser,
`{:error, :not_running}` - and the test no longer depends on QEMU's tolerance
for a second opener, which it does not have. This is a change to a test shipped
in the roadmap, so it is called out here and lands in its own commit
(AGENTS.md).

---

## ADR-068: An installed package answers as a Mix SCM

**Status:** accepted (M26)

**Context.** M15 makes an install bring its closure - `install(:hello_app)`
installs `hello_dep` first - and `-pa`s every installed ebin onto the running
VM, which makes the code *loadable*. Mix, building `hello_app` in the child
ERTS, resolves the `{:hello_dep, "~> 0.1"}` its `mix.exs` declares the ordinary
way, and on this box that ends like this (the child's own output, M26's first
red run):

    Mix requires the Hex package manager to fetch dependencies
    Shall I install Hex? (if running non-interactively, use "mix local.hex --force") [Yn]
    ** (Mix) httpc request failed with: {:failed_connect, [{:to_address, {~c"builds.hex.pm", 443}}, {:inet6, [:inet6], :nxdomain}]}
    Could not install Hex because Mix could not download metadata at https://builds.hex.pm/installs/hex.csv.

The box has no network, and hanging a declared dependency on a repository
would also be a second copy of a package that is installed (M10 keeps one
version per package).

**Decision.** The child ERTS that runs the build starts Mix itself and
*prepends* `Elixos.Package.SCM` to the SCM list before `Mix.CLI.main/1`:

    'Elixir.Mix':start(), 'Elixir.Mix.SCM':prepend('Elixir.Elixos.Package.SCM'), ...

`Mix.SCM.available/0` is read lazily, so nothing else has to know. The SCM's
`accepts_options/2` answers a dependency whose name is installed with its
destination set to `/priv/apps/<name>`; `checked_out?/1` is then true, because
it *is* on the disk, so no SCM ever fetches. It declines - returning `nil`, so
the ordinary SCMs decide - when the dependency names its own source (`:path`,
`:git`, ...), when nothing by that name is installed, and when the version
installed does not satisfy the requirement in the `mix.exs`: one version per
package, and never a silently wrong one. A declined dependency resolves the
ordinary way, where a repository is the only place it could come from.

**Alternatives.** Rewriting the project's `deps` before the build edits the
sources it was given, and would have to be repeated for every Mix entry point.
Symlinking `deps/<name>` at the installed directory lies about a source tree
Mix then reads (`mix.exs`, `priv`, lock files) and makes the loaded path the
symlink rather than the package.

**Consequences.** `--no-deps-check` stays: the OS itself is a dependency the
running VM already has and no repository provides. The build child must be
able to load `Elixos.Package.SCM`, which it can - it boots the factory release
and the module ships in `Elixos.Package`'s own app - and `Elixos.Package` now
publishes `installed_dir/1` and `installed_version/1` for it to answer with.

## ADR-069: Emerge renders CPU frames; the image owns the native ABI

**Status:** accepted (M27)

**Context.** Ask questions are OS data with independent front-ends (M20).
The GUI must draw the four question kinds without making the prompt depend
on a window system or a GPU. Emerge 0.4.2 provides a headless raster backend
and binary `VideoInterop.Frame` output. Its native renderer is a Rustler NIF;
selecting only raster backends does **not** select musl rather than glibc.
A GNU NIF cannot be made compatible with the musl BEAM by disabling GPU APIs.

**Decision.** Pin the Elixir dependency and `elixos-gui-renderer` recipe to
Emerge **0.4.2** together. `Elixos.GUI.Dialog` builds an Emerge tree and owns
selection/editing; `Elixos.GUI` subscribes to Ask and renders the oldest open
question. Defaults prefill the view but never answer a question automatically.
Off-screen capture uses the same tree as the live framebuffer.

The service starts asynchronously after Ask, is temporary and non-critical,
and starts nothing in rescue. Its renderer uses `backend: :headless`,
`rendering_api: :raster`, binary RGBA8888 output, and the GUI process as owner.
Received frames are validated before the framebuffer helper receives them.
One frame is in flight; another replaces the pending frame rather than
growing an output queue.

The image packages the NIF independently from the factory BEAM:

* x86_64 uses the checksum-verified upstream **musl embedded-CPU** artifact;
* aarch64 builds that profile from the checksum-verified Hex source,
  its Cargo.lock and pinned rust-skia revision, with Skia's source build forced;
* each target's actual ELF closure is resolved from signed Alpine packages,
  copied beside the NIF, and given private `$ORIGIN` RUNPATHs.

The runtime location is `/system/gui/<arch>-unknown-linux-musl/`.
The factory's Emerge `priv/native` directory links there. Rustler generates
the target loader with native compilation skipped; it does not fetch or
compile a renderer while the factory builds. Compile-time target options
mean the factory is built per architecture; only architecture-neutral Elixir
continues to reuse the host tree. The renderer package has its own input
fingerprint, so factory edits do not invalidate the kernel, OTP or renderer.

**Consequences.** The GUI checks the target artifact before invoking native
code, and load/start errors leave the text console available. This is not
process isolation: an actual NIF crash can take the entire BEAM down. The
shim remains outside that VM and retains its recovery responsibilities.
The pinned internal tree-capture API must be reviewed together with the
recipe and host rendering acceptance when Emerge is upgraded.

## ADR-070: Framebuffer input and fbcon handover are a leased native boundary

**Status:** accepted (M27)

**Context.** Emerge's headless renderer does not inject evdev input into the
dialog. Writing `/dev/fb0` while fbcon owns it can lose the UI to console
repaints, but the BEAM must not regain root privileges or accept arbitrary
sysfs writes.

**Decision.** Two libc-free Zig executables implement this boundary:

* `/usr/bin/elixos-gui-io` runs with the user's identity, maps `/dev/fb0`,
  discovers `/dev/input/event0` through `event255` and grabs those devices;
* the allow-listed `console-handover` helper starts
  `/usr/bin/elixos-console-handover` as root, or leaves its existing broker
  running when the root-owned lock is already held.

The broker's fixed Unix socket is `/run/elixos-console.sock`, root:1000,
mode 0660; it admits only peers whose real uid is 1000. Publishing those
permissions happens after `listen`, forming the startup readiness barrier.
No client supplies a path, executable, uid or sysfs command. The broker
discovers the kernel's actual framebuffer vtconsoles, grants group-only
access to root-owned framebuffer/input character devices and unbinds fbcon
for one connected lease.

The IO Port uses packet-4 framing. It announces `READY <width> <height>`,
accepts exact-size RGBA frames and acknowledges each completed framebuffer
write with `PRESENTED`. Native evdev packets carry keycodes/values, pointer
positions and button values; position changes precede a click in the same
input batch. Elixir translates the default US keyboard layout and calls the
same dialog-input seam as other front-ends. Autorepeat edits text and moves
selection, but cannot submit, confirm, dismiss or repeatedly toggle a choice.

A zero-length frame requests shutdown. The IO helper releases input grabs,
requests lease release, waits for the broker's `C` acknowledgement **after**
fbcon has been rebound, and exits. `GUI.stop/0` waits for that successful
exit instead of treating Port closure as proof of console handback.
Unexpected helper/GUI/BEAM death also closes the lease and causes rebind.

**Consequences.** The helper supports packed true-color 16/24/32-bit
framebuffers with up-to-eight-bit channels, including stride and visible
offsets. Device discovery is bounded and happens at startup; hotplug needs
a GUI restart. A lost evdev packet fails the session rather than inventing
modifier releases. Broker SIGKILL cannot run cleanup; restarting the broker
restores abandoned bindings before granting a new lease.

The shim's `refAllDecls` test now includes both helper modules, strengthening
lazy-analysis coverage. No shipped acceptance assertion, timeout or vector
is removed or relaxed.

## ADR-072: Hardware-accelerated live_gpui ships in vendor image profiles

**Status:** accepted requirement; implementation pending

**Context.** The human's `~/src/live_gpui` project combines **GPUI and
LiveView via Rustler**. Its native-editor screenshot is a smoke test, not a
finished integration. The human has specified AMD and NVIDIA Elixos variants
using it for hardware-accelerated graphics.

**Decision.** Integrate the completed stack as shared Elixos GUI code and
ship separate **AMD** and **NVIDIA** image profiles. Vendor drivers, firmware
and graphics userspace libraries belong to those profiles; OS, LiveView and
agent behavior do not fork by GPU vendor. Pin and package native dependencies
for each supported architecture and profile, with their required licenses.
Keep profile cache inputs separate so a prompt, agent or GUI-source edit
does not rebuild an unchanged kernel or unrelated vendor package.

The current Emerge CPU framebuffer path and its acceptance are not evidence
of GPUI hardware acceleration. Each profile needs a real renderer startup,
native input and editing, callback-busy/reorder/restart behavior, and its own
hardware-acceleration verification. The kernel remains unmodified mainline
Linux (ADR-001); driver availability is a configuration/package concern.

**Consequences.** `live_gpui` remains the human's in-progress project, not an
already-shipped Elixos backend. The AMD and NVIDIA variants are separate
deliverables, not labels on an unverified generic image.

## ADR-083: Elixos is the OS; the bundled OMP port is withdrawn

**Status:** accepted (human decision, 2026-10-13)

**Context.** The human rejected the OMP port and the parallel LLM, provider,
tool-host and agent infrastructure built for it. They will pursue a
capability-oriented Oh-My-Jido project separately. Leaving M21–M24 deferred
would retain a commitment they explicitly withdrew.

**Decision.**
- Restore the OS source checkpoint `d757f7e` (M27 Ask dialogs and framebuffer
  handover), preserving the independent HTTPS hostname-verification fix
  `5398cd9`, GitHub funding metadata, MIT license and README badges.
- Withdraw M21–M24 and ADR-047 through ADR-050; supersede ADR-063's deferral.
  Remove their unimplemented `Toolset`, `Coder`, `Candidate`, `Health` and
  `Native` scaffolds, the OMP inventory, and the five host/four QEMU acceptance
  suites for that rejected contract. Remove its obsolete deferral filter.
  This is an explicit scope withdrawal, not weaker tests or a delivered
  milestone; retained OS tests, vectors and timeouts are not relaxed.
- Preserve existing Jido agents, Ask, browser, GUI, native toolchains,
  generation recovery/sealing and OS build fixes. Retain ADR-072's independent
  AMD/NVIDIA graphics requirement without touching `~/src/live_gpui`. Keep
  `MILESTONE=27`; the known ARM64 renderer issue still blocks its full gate.
- Preserve the port's committed history and verified snapshot of tracked,
  uncommitted and untracked work in a private recovery archive outside
  `build/`. Do not rewrite Git history or touch other projects or OS caches.
  The detour's ADR-071 and ADR-073 through ADR-082 remain in archived history;
  their numbers are not reused. ADR-072 remains an independent OS requirement.

**Consequences.** Oh-My-Jido has no implementation or runtime dependency here.
M21–M24 stay reserved to preserve later milestone/test identities. The
rejected acceptance material is retired in its own ADR-carrying commit;
the OS rollback follows separately. M27 remains unfinished, not reclassified
as complete by this rollback.

## ADR-084: Source-pinned Oh-My-Jido is an opt-in native factory library

**Status:** accepted for the human-approved Candidate/Health and disposable
T10 factory refresh (2026-10-13); guest acceptance is not yet verified.

**Context.** ADR-083 withdrew the OMP port, not the independently maintained
Oh-My-Jido library. The human subsequently approved this library's real Elixos
host adapter, isolated Candidate/Health implementation, and an actual no-NIC
disposable guest healthy/fallback demonstration. The library needs the licensed
Jido 2.4.0 and ReqLLM 1.28.0 source snapshots with their recorded private-
diagnostic patches. Substituting the unmodified Hex releases is incorrect.
Factory, OTP and Elixir modules remain protected from candidate overlays.

**Decision.** Add the canonical `oh_my_jido` Mix project as a pure-BEAM OS
dependency, with its licensed `vendor/jido` and `vendor/req_llm` source trees.
The existing OS Jido dependency changes source in place; ReqLLM retains the
canonical library's transitive path override. These are staged verbatim from
the separately maintained checkout, not a copied implementation or another
runtime. `scripts/stage-coding.exs`
requires a human-selected SHA256 content pin before staging; it records every
selected source byte, including both upstream inventories, local notices,
licenses, fixture source, and lockfiles. Source symlinks and generated build
trees are not accepted as package inputs.

The factory builds all code with its installed OTP 29.1.1 and Elixir 1.20.4.
The real `examples/elixos` adapter is compiled as an ordinary Mix application
against the full `os/` project, sharing that build and lock. Its independent
host-test `host_source/` application is never used in the factory. The adapter
is installed in the ordinary `/factory/lib/elixos_host-0.1.0/{ebin,priv}` layout.
It is not an OS startup callback and does not replace existing services.
The library application starts no runtime/session implicitly; the human
explicitly starts the example under the existing package service supervisor.
This avoids an OS-to-adapter-to-OS dependency cycle.

`/factory/coding/source.json` and `beams.json` bind the selected canonical and
copied OS/test/vector/assembly sources, resolved lock, compiler/runtime
identity, application metadata, emitted BEAM bytes and preserved redistribution
notices. Application notices use native `priv/licenses` directories.
Dependency resolution must leave the committed OS lock unchanged; native image
assembly regenerates its apko lock against the resulting factory APK.
The portable system tests, fixture/vector inputs, Mix and ExUnit remain factory
assets; validation copies them into private evidence workspaces. Candidate and
Health keep using direct, non-distributed child ERTS workers and bounded JSON,
not unrestricted RPC, peers, hot-loading frameworks or a custom VM build.

The no-NIC T10 scenario uses actual public library sessions and tools under
the real host adapter. It performs deterministic read/edit/build/test/propose
operations, not a fabricated model response or browser service. Build, test
and proposal each retain the existing Ask consent boundary. NEXT is not a
promotion acknowledgment. A human separately reboots; only normal boot's
verified Health and AutoCommit may send COMMIT. A deliberate fallback uses
an approved, non-protected user module's boot-MFA exception, never corrupt
bytes, protected-module replacement, un-sticking, or host-root helpers.

**Alternatives.** A separate coding VM/transport, vendoring another fork into
Elixos, rebuilding ERTS, changing dependency source at runtime, bypassing
protected-module checks, and treating host fixtures as a guest gate are
rejected. Shipping optional QuickBEAM or Python/Snakepit solely for this
scenario would add native/runtime closure unrelated to the approved T10
effects; they are not selected as OS core dependencies.

**Consequences.** This is a new OS runtime dependency, explicitly authorized
by this ADR. Its closure is resolved once with the OS lock; existing OS
services keep their native behavior. New source bytes require a new explicit
pin and factory rebuild. The target-native F05/T9 QuickBEAM and Python backend
packaging/acceptance requirements remain open; T10 does not waive or satisfy
them. No source, host test, receipt, or NEXT write claims the guest gate green:
the actual disposable-disk boot/health/seal/fallback transcript is required.

## ADR-085: Normal Live boots keep all writable state in RAM

**Status:** accepted (2026-10-15).

**Context.** The first real laptop boot reached IEx in diskless rescue mode.
The human wants the normal OS services without an installer, automatic SSD
mounts, partition changes or formatting. Manual mounts and save/restore are
separate work; native recording is deferred.

**Decision.** Add `elixos.live[=1|0]`, default off. Live keeps `/priv` on the
RAM-backed initramfs root and never calls the physical data-device mount or
wait path, even when `elixos.data` or `elixos.safe` is also present. Existing
`normal|rescue` launch values, uid boundaries, sealing, recovery accounting
and shim-panic handoff remain unchanged. Safe still selects rescue.

The Live packer extends a pristine packaged initramfs with a second gzip/newc
archive containing the existing service SquashFS and toolchain APK payload.
It accepts only the pristine account-home directories under `/priv`, not a
captured session. It normalizes PostgreSQL's parent to root ownership before
the unchanged service-directory checks; no privileged check is relaxed.
Neither another tmpfs mount nor a boot-time tree copy hides these seeds.

`build-uefi-image.sh --live` embeds that archive and hard-locks the panel
console and Live command line with `CONFIG_CMDLINE_OVERRIDE`. x86_64 kernel
RAID autodetection is disabled so an existing array is not activated before
PID 1 selects storage. The framebuffer GUI is opt-in in Live, preserving
the only local IEx keyboard and screen.

**Consequences.** The full toolchain costs RAM and image size; this profile
is exercised with 4 GiB guest RAM. `Elixos.save/1`, files, database rows,
installed packages and keys remain in RAM and disappear on a kernel reboot
or power loss. This is not durable persistence or a BEAM heap snapshot.
The Nerves immutable-firmware/separate-application-data model is the storage
precedent, not its automatic application-partition formatting behavior.
No Nerves runtime, recorder, new mount service or parallel application
runtime is added. Docker, Firecracker, Fly deployment and the public SDK
are subsequent, separately verified targets.

## ADR-086: Docker distributes a real Live VM, not another userland port

**Status:** superseded by ADR-091 (2026-10-15). Historical VM proof only;
the Docker/QEMU wrapper is removed and is not a deployment recommendation.

**Decision.** Package upstream QEMU on Alpine 3.24.2 with the existing
x86_64 kernel and RAM-backed Live initramfs. The Docker build sees only its
launcher and the two boot artifacts, not repository sources or credentials.
The entrypoint execs QEMU so Docker signals reach the owned VMM directly.

Guest PID 1 remains the Zig shim and the guest runs its own pinned Linux
kernel. Defaults are serial IEx, 4 GiB RAM, two CPUs and user-mode DHCP
networking. No host disk, host networking, host PID namespace, privileged
container, GUI or listening management socket is required.
`QEMU_ACCEL=kvm` fails without KVM; `tcg` explicitly selects emulation;
`auto` reports its initialization/fallback choice.

**Verification.** Two fresh Docker Desktop guests under forced KVM booted
normal Elixos, reported Linux 7.2.9 and init as PID 1, obtained DHCP
addresses and answered PostgreSQL queries. The same two-boot scenario passed
under explicit TCG without host devices. File/database changes vanished on
the next guest boot. This is not cloud deployment, a production jailer,
or a claim that Fly accepts arbitrary guest kernels.

## ADR-087: Firecracker reuses the packaged kernel and RAM Live root

**Status:** accepted (2026-10-15).

**Decision.** Pin upstream Firecracker 1.17.0 and its published archive
SHA256, install it locally under `build/`, and launch it with the existing
x86_64 `bzImage` and Live initramfs. Upstream added bzImage support in this
release; no kernel patch, alternate kernel build or copied OS is necessary.
The launcher supplies explicit empty drives, serial console and RAM Live
configuration, requires KVM, exposes no API socket, and forwards termination
to its owned VMM. It changes no host routes, firewall, disk or TAP devices.

**Verification.** Two Firecracker KVM boots reached normal IEx, reported
Linux 7.2.9/init, queried PostgreSQL and lost a file/database row on the next
launch. Guest reboot cleanly shut down services and ended the owned VMM.
This verifies serial and loopback operation only, not external networking,
PCIe passthrough, production isolation or a hosted Fly deployment. Production
uses the upstream jailer and an explicitly provisioned network/storage policy.

**Source:** [Firecracker 1.17.0 release](https://github.com/firecracker-microvm/firecracker/releases/tag/v1.17.0).

## ADR-088: The application SDK packages source; the real OS compiles it

**Status:** accepted (2026-10-15).

**Decision.** Use an ordinary dependency-free Mix archive, `elixos_sdk`,
for project generation and target-effective Hex source packaging. Keep
`MIX_TARGET=elixos` separate from dev/test/prod. The human selected native
compilation inside Elixos, not a host cross-SDK, copied OS or fake API.
`elixos: os()` is an ordinary Mix project helper returning the existing
services/oban/persist/min_os/boot schema.

Packaging evaluates a fresh prod/Elixos project and filters both dependency
environment and target. It never fetches or compiles target applications.
Native contracts retain a required versioned `:elixos` requirement; portable
libraries need none. Existing Hex tarballs, RSA-signed static registries and
explicit public-key trust remain the distribution protocol. Build-time
config must remain host-evaluable; runtime OS calls belong in native code.
No new guest dependency or application runtime is introduced.

The installer checks real target app identity, OS requirements and the
system-wide dependency plan before compilation/replacement. A clean child
ERTS sees real OS/Mix/installed ebins but does not start another OS
application. Its exact target output is verified; an externally changed
version refreshes only a stale application resource, not all native code.
The native SCM binds `:elixos` to the executing OS's own resource, including
when a source project supplies an alternate path.

State lives under `/priv/data/<app>`, not replaceable app code. Relative
persist directories reject traversal and symlink components; reinstall,
upgrade and removal retain state. One journal record carries full spec,
actual requirements and target config. Ordinary v1 generation preparation
MFAs restore metadata before scheduler/services; historical journal tuples
and generation files remain readable. Explicit installs start declarations;
saved boots start only automatic services/queues, not manual ones.

**Failure policy.** A boot MFA returning `{:error, reason}` stops boot before
later actions, as a throw/exception does; a refused service is not a healthy
half-started generation. Existing boot deadlines and shim recovery policy
are unchanged. Durable application decoders must load their own schema
before safe ETF decoding on a fresh VM; service-only restarts do not prove
cold-boot recovery.

**Consequences.** Host tests remain useful without an OS facade. Native code,
shared dependencies, configuration and data must also be exercised in a
real guest/device. `persist` is filesystem policy, not manual Live export:
all Live state still disappears on kernel reboot. This does not add disk
formatting, automatic mounting, terminal recording or Fly persistence.

## ADR-089: Fly runs the packaged application as a nested guest

**Status:** superseded by ADR-091 (2026-10-15). The authorized historical
trial is recorded below; nested-QEMU Fly deployment is withdrawn.

**Decision.** Use Fly's documented OCI image path, retaining its own Machine
boot boundary. The container runs QEMU TCG with the actual Elixos kernel,
Zig PID 1, BEAM and natively installed SDK application. This is not a claim
that Fly's Machines API accepts an arbitrary kernel/initrd or nested KVM.

Build in the full real OS first; a separate deployment disk may omit its
build toolchain while retaining installed runtime code, saved metadata,
application data and normal services. The verified full SDK/Live image is
unchanged. Every attached guest disk is an explicit baked regular file,
never a discovered host device. Container-layer writes are ephemeral, not
Fly persistence.

**Verification.** A single isolated personal-org Machine in `iad`, with
4096 MiB RAM and two shared CPUs, booted a 2048 MiB Elixos guest. Its SDK
client reported Linux 7.2.9/init, normal mode, real OS/data-directory APIs,
prod/Elixos config, restored counter 7 and measurement mean 21.75. No
public service or Volume was configured. The trial manifest, scoped token,
app and Machine were removed; temporary credentials were deleted.

**Limits.** TCG is slow. Public ingress, durable Fly storage/recovery and
health promotion are unverified. Registry transfer used a short-lived
app-scoped token; the current account capped Machines at 4096 MiB.
The temporary verifier initially mishandled Fly's multi-line JSON logs;
correct decoding of the already captured event proved the boot without
redeployment. The failed driver result was preserved rather than rewritten
as success.

**Sources:** [Fly image registry/deployment](https://docs.fly.io/blueprints/using-the-fly-docker-registry/),
[scoped access tokens](https://docs.fly.io/security/tokens/).

## ADR-090: Verify Cargo with a real build instead of an environment echo

**Status:** accepted (2026-10-15).

**Problem.** The M25 Cargo fixture prints arguments and environment variables
without compiling anything. It equates the child working directory with
`File.cwd!/0`, despite ADR-020 requiring the caller's session directory.
Inside the isolated on-device health worker, the VM's source directory and
the existing `/priv/home` legitimately differ. The fixture therefore rejects
correct session behavior while providing no evidence that Rust can link.

**Decision.** Remove that environment-echo test rather than repin its strings
or change runtime working-directory behavior to satisfy it. Keep the other
Rust tests. Add a real offline Cargo integration scenario: enter an explicit
session directory, compile and run a program that reads relative input and
writes the computed result there, and verify the VM's cwd and environment
remain unchanged. Compiler, linker, execution and session-path failures must
fail that scenario. No health check is skipped, loosened or given a larger
deadline; the default health gate remains mandatory for image export.

## ADR-091: Native OCI shares the provider kernel and reuses the real OS

**Status:** accepted (2026-10-15), following the human's rejection of VM wrappers.

**Decision.** Remove QEMU-in-Docker and nested-QEMU Fly deployment. An OCI
image is the native Elixos userland on the runtime/provider's Linux kernel,
not a claim that Docker boots the packaged kernel or that Fly accepts an
arbitrary customer kernel. Bare-metal EFI/Live and direct KVM Firecracker
retain the existing machine profile and packaged kernel.

Compile explicit OCI boundaries into the existing Zig shim. Keep the same
BEAM application, PostgreSQL, Oban, package/generation machinery, control
protocol, helper identities and health gate. Support namespace PID 1 and a
provider init's child through subreaping. Validate explicit image/runtime
markers and procfs; refuse initial-namespace PID 1 without exiting it.
Native shutdown signals only owned children and exits the supervisor:
poweroff/halt/SIGTERM mean 0; reboot means 75 for orchestrator restart.
No native mount/unmount, host-network setup, kernel reboot or global kill.

Bake the service tree read-only, add immutable `/toolchain` only to the SDK,
and require runtime-supplied writable `/priv`. Default headless; explicit
console and rescue switches are environment policy, never host cmdline.
Forward ordinary runtime application environment while replacing reserved
launch values and excluding ERTS/loader overrides. No VM cwd or environment
mutation is introduced.

`mix elixos.image` source-packages on the host, installs/compiles natively,
saves, cold-restores and requires the ordinary default health gate and shim
commit before exporting verified deployment metadata/code. The runtime image
contains a read-only seed, not a cloned writable disk or database. Seed only
a pristine volume, with an interruption marker and `boot.state` published
last. Existing state always wins. App data and runtime secrets are supplied
separately; unknown secrets embedded in app code/config remain the author's
responsibility.

Factory repository presets are imported explicitly during application
initialization, not as a side effect of reading an empty trust store.
`/priv/hex/repos.exs` remains the complete trust decision. Native CLI paths
include `/usr/local/bin` so the packaged Elixir/OTP tools actually execute.
PostgreSQL treats both `ENOENT` and `ESRCH` procfs races as process
disappearance while still requiring real SQL readiness.

**Deployment limits.** A matching-architecture OCI daemon/host is required;
there is no implicit emulator. Hardware GUI, physical mounts and network
administration belong to machine deployments. Fly owns its Machine kernel
and init; `/priv` uses an explicit per-Machine Fly Volume. A single local
volume is not replicated or highly available; backups, migrations, resource
limits, application ingress/readiness and restart policy remain explicit.
The public guides record exercised proof separately from these contracts.

**Sources:** [Fly application/lifecycle configuration](https://docs.fly.io/reference/configuration/),
[Fly Volume durability and redundancy](https://docs.fly.io/volumes/overview/).

## ADR-092: Eval is an explicitly selected native factory profile

**Status:** accepted for source implementation under the human's optional Eval
packaging approval (2026-10-16). Both target builds and guest acceptance remain
unverified until their actual receipts and serial transcripts exist.

**Decision.** Keep the ADR-084 default factory pure BEAM. The separate
`ELIXOS_EVAL_PROFILE=1` image profile selects `elixos-factory-eval` and
`elixos-coding-eval-python`, never an installer or an OS startup callback.
It uses the image's OTP 29.1.1/Elixir 1.20.4, target musl, QuickBEAM 0.11.3's
published checksummed native artifacts, and the canonical MIT-licensed
Snakepit 0.14.0 private-diagnostics source snapshot. These are new optional
runtime package dependencies authorized only in this profile.

The factory builds the same OS sources through native Mix post-configuration:
optional direct dependencies and release `:load` applications are selected
before compilation. In particular Oh-My-Jido's Python adapter must compile
with Snakepit present; grafting a Python app onto a previously compiled
pure-BEAM factory is not equivalent. A separate merged lock keeps every OS
pin authoritative and adds only previously absent canonical lock entries.
Neither checkout nor committed lock is rewritten.

QuickBEAM's transitive OXC 0.19.0 lacks complete musl precompiled coverage
(no aarch64 parser, and neither musl formatter/linter). Build its actual
upstream Rust NIF crates with the OS-pinned Rustler 0.38.0 and Alpine's
target-native Cargo toolchain, retaining Cargo.lock. This is a build-time
toolchain, not a Rust helper process or another agent/runtime framework.
For aarch64, native target melange execution may use an explicitly configured
binfmt/QEMU build runner; never transplant x86_64 native artifacts.

Python uses the pinned Alpine 3.14 system interpreter and a package-created,
read-only venv. Its grpcio, protobuf, numpy and typing-extensions wheels are
explicit upstream URL/SHA256 pins for CPython 3.14 and musllinux 1.2.
The package copies the canonical Snakepit SDK and its already generated gRPC
stubs unchanged. grpcio-tools, pytest and showcase/telemetry extras are not
needed by the Eval adapter's actual import closure; no protoc regeneration,
pip, uv, setup, dependency fetching or global environment mutation runs in
the guest. Worker-local PYTHONPATH remains Oh-My-Jido's existing adapter
contract; interpreter site-packages supplies the pinned binary wheels.

The shared packaging pipeline records actual emitted BEAM/native/source
bytes, ELF machine/libc, resolved native dependency links, and the target
ERTS's exported NIF symbols. Missing/empty artifacts, unresolved links,
foreign-machine ELF, wrong OTP/Python, changed locks or absent licensed
source provenance fail the build. No target digest is pre-invented.
The explicit IEx frontend starts only native OTP prerequisites and a
host-configured Oh-My-Jido runtime. Elixir/JavaScript run in its JSON-only,
non-distributed separate ERTS; Python remains exclusively Snakepit-managed.
All are trusted-code crash separation, not a security sandbox.

**Operations.** Optional builds require a separate `ELIXOS_BUILD` directory;
their apko locks and image outputs are separate from the default profile.
No packaging entrypoint creates, rewrites or discovers a disk image.
The packaged finite opt-in smoke runs real two-cell state, granted/denied
Jido tool calls, errors/output quotas, timeout/reset, cancellation, actual
worker termination, host survival and process cleanup for all three
backends. Only that guest run produces a smoke receipt; package assembly
does not claim F05/E01–E07 or either architecture verified.

## ADR-093: Oh-My-Jido approvals replace the Ask queue

**Status:** accepted (2026-10-22), decided by the human. Supersedes the M20
Ask milestone (ADR-059, ADR-061) and the Ask-dialog parts of M27.

**Problem.** Elixos had two human-in-the-loop systems. `Elixos.Ask` was proposed
before Oh-My-Jido was part of the plan. Oh-My-Jido's managed sessions already
pause an effect or clarification, carry its context (session, run, capability,
effect) and fail closed. A separate OS queue strips that context.

**Decision.** Delete `Elixos.Ask`, its Jido action, its console notice and its
tests. Oh-My-Jido approvals and questions are the only human-in-the-loop
mechanism. Anything that asked through Ask asks through an Oh-My-Jido session.
Retire M20 and its acceptance (`ask_test.exs`, `m20_ask_test.exs`) and the
M27 subscription test. The `elixos-ask:` console line is removed from
PROTOCOL.md §6. Retired tests were added after the scaffold baseline, so
`make audit` reports no deletions.

**Detached agents.** The library covers waiting: a session belongs to its
runtime, not to the REPL that started it, so agents started in the background,
from an Oban job, or resumed after a reboot ask the same way. A question waits
up to `question_timeout_ms` and then fails closed; cancellation, session exit
and non-approving answers deny; restored sessions never revive old questions
(Oh-My-Jido's sessions-and-recovery contract). It does not provide one place to
find questions across sessions. Elixos adds that:

- `Elixos.Approvals.Host`, the OS's `OhMyJido.Host`, delegates policy to
  `OhMyJido.Host.Local` and leaves every question pending while registering it.
- `Elixos.Approvals` indexes every open question of those sessions under a
  small OS-local number, from the session's own event stream, and drops it when
  Oh-My-Jido reports it answered, withdrawn or expired, or the session exits.
- The boot tree starts it and the OS's `Elixos.Coding` runtime (file-backed
  checkpoints under `/priv/coding/sessions`, one-hour question timeout) as a
  non-critical service; rescue starts neither.
- Any login IEx or SSH session has `approvals/0`, `approve/1`, `deny/1` and
  `answer/2`. Answers go through `OhMyJido.answer/3` unchanged; nothing in the
  OS answers on its own.

**GUI.** The framebuffer GUI never starts at boot; Elixos boots to `iex(1)>`.
It is an optional front-end for these requests opened with
`Elixos.GUI.start/0`, which refuses to take the screen when nothing is
pending. Escape or F12 hands the screen back, as does the last request being
resolved. Escape no longer dismisses: denial is an explicit "no". The M27
acceptance is rewritten for this behavior.

**Escape hatch.** Approvals decide what an agent may do. The unprivileged
BEAM, the shim's helper allow-list and sealed commits decide what it cannot do
even after an approval; none of them changes.

**Consequences.** M15 Jido agents that are not Oh-My-Jido sessions no longer
have an OS ask action; they ask by running work in a session. The OS-local
index is in memory: after a reboot it is empty because Oh-My-Jido revived
nothing to answer. Oh-My-Jido's bundled `examples/elixos` host, which called
`Elixos.Ask`, lives in that separate project and must move to approvals there.

## ADR-094: No compiler runs under emulation

**Status:** accepted (2026-10-22), decided by the human. Extends ADR-060.

**Context.** ADR-060 cross-built the arm64 kernel and ERTS but left two
packages compiling inside the emulated aarch64 melange environment: the Emerge
renderer (Rust and Skia, hours under qemu-user) and the factory (every Elixir
compiler process emulated). The human's rule: cross compile everything.

**Decision.** Every package that compiles anything for a foreign
architecture builds in the build host's native environment and is staged
through `cross_build`/`stage_prebuilt`; the target-architecture recipe only
installs the staged tree and fails if it is missing, instead of falling back
to an emulated compile.

* `melange/gui-renderer-cross.yaml` builds the Emerge NIF with a pinned Rust
  toolchain plus the target's `rust-std`, Alpine clang/lld and an aarch64
  sysroot from Alpine's own packages (the `otp-cross.yaml` pattern), and ships
  its private ELF closure resolved against that sysroot.
* `melange/factory-cross.yaml` runs the same `scripts/package-factory.sh` on
  the native OTP/Elixir with `FACTORY_ARCH`/`TARGET_ARCH` set for the target
  (the Nerves convention RustlerPrecompiled and Emerge read). The factory has
  no native code; its receipt records the target's `system_architecture`
  (`FACTORY_SYSTEM_ARCHITECTURE`), not the build host's.
* The aarch64 Eval profile (ADR-092) builds Rust NIFs and has no cross recipe
  yet; `build-image.sh` refuses it on aarch64 rather than emulate.

Packages that only download and repack (browser, toolchain) or already run a
host-architecture compiler (shim via `ELIXOS_ZIG_HOST_ARCH`) are unchanged;
their target environment still unpacks under emulation, which compiles
nothing.

**Consequences.** An aarch64 image needs the x86_64 OTP and Elixir APKs first
(already true for `otp-cross`). The riscv64 port (M28) follows the same rule
from the start: kernel, ERTS (interpreter, no JIT), renderer and factory are
all host cross builds.

## ADR-095: AutoCommit uses a boot gate; the full suites gate candidates and export

**Status:** accepted (2026-10-23).

**Context.** AutoCommit's default gate had become the full `Elixos.Health`
run: the portable system suite and the tool smoke suite in child ERTS
workers, on every boot. In the 1 GiB QEMU guest the initramfs root holds
~420 MiB and the login BEAM ~125 MiB; a suite child grows past what is left
(the whole suite peaks near 770 MiB with `+S 2:2`), the OOM killer took it and
no generation was ever committed. Even at 2 GiB the suites do not finish in
the commit windows the M05, M06 and M17 acceptance tests require (a commit
within 60 s of `elixos.commit_after=2`). Those tests are the contract.

**Decision.** `Elixos.Health.boot/0` is AutoCommit's default: liveness, the
running-generation identity check (each loaded module's MD5 equals its
SHA256-verified store BEAM), and for a generation that came from
`Elixos.Candidate.propose/1`, that its candidate is unchanged and its recorded
suites passed (`Candidate.proposal_validated/1`). The suites already ran
before NEXT was written. `Elixos.Health.run/0` keeps the full suite gate, and
image export and explicit checks still require it. `:elixos, :health_checks`
overrides both gates as before.

The identity check had never passed for any saved module: it matched
`:beam_lib.md5/1`'s result as a list. That is fixed and covered by
`test/elixos/running_generation_test.exs`.

**Consequences.** A prompt `Elixos.save/1` is committed on liveness and code
identity, as before the suite gate. Running the full suites on a booted
generation is explicit: `Elixos.Health.run/0` or `run_generation/1`.

## ADR-096: Acceptance changes for the retained candidate gates, the SDK and native OCI

**Status:** accepted (2026-10-23).

**Context.** ADR-083 withdrew the agent arc but kept its generation
machinery: candidate builds in child ERTS workers, health gates, retained
evidence and generation provenance (ARCHITECTURE §4.5, TESTING "Candidate and
Health host gates"). ADR-049 described that machinery and is withdrawn with
the arc, so the shipped tests it changed have no accepted ADR. Each change
below follows an interface change; none weakens an assertion.

**Decision.** These protected tests change, in their own commit:

* `test/elixos/boot/auto_commit_test.exs` - AutoCommit records each check under
  an evidence directory, so the test gives it a temporary one
  (`:evidence_dir`); a commit callback must return `:ok`, because a
  control-write failure is now retained as failure (ADR-095), so the stub
  returns `:ok` instead of the message it sent.
* `test/elixos/image/generation_test.exs` - adds a case: the version-one
  manifest's optional `provenance` round-trips and legacy manifests read `nil`.
* `test/elixos/package/mix_target_test.exs` - tagged `:host_orchestration`: it
  starts a second Mix build, which candidate suite children exclude so a
  validation never recursively builds itself.
* `test/elixos/package/spec_test.exs` - `Spec.read_project/1` returns the app,
  version, dependencies and spec together (ADR-088); it runs `async: false`
  because reading a project takes Mix's global project lock.
* `shim/src/main.zig` `refAllDecls` - adds `container` and `seed` (ADR-091),
  so the native OCI modules are analysed by the Zig unit tests.
* `test/elixos/candidate_test.exs` - Elixir 1.20's compiler never loads the
  modules it compiles, so a candidate's `@on_load` first runs when a suite
  child loads its beams. The origin-frame and counterfeit-receipt attacks are
  asserted at that phase (the suite output, and `:invalid_child_receipt` for
  both suites with no proposal), not at build. The OS checkout test now builds
  for real because candidate children receive the Oh-My-Jido source location
  and link dependencies into Mix's per-environment build path.
* `test/elixos/coding_factory_test.exs` - a `mix.lock` evaluates to atom keys;
  the identity comparison now names apps as strings on both sides.

**Consequences.** `make audit` covers these files through the commit that
names this ADR.

## ADR-097: riscv64 is the third architecture

**Status:** accepted (2026-10-23), M28.

**Context.** The K230 cyberdeck track (M28–M33) runs Elixos on the K230's
1.6 GHz RISC-V core. Before the board, the image has to exist and boot on
`qemu-system-riscv64 -machine virt`. Alpine has signed riscv64 indexes for
v3.24 (key `60ac2099`), and every Alpine package the image and its build
recipes pin resolves there at the same versions as on aarch64 and x86_64.

**Decision.**
- riscv64 joins x86_64 and aarch64 (ADR-041). Like aarch64 it is a foreign
  architecture: the kernel (`LLVM=1 ARCH=riscv`), OTP, the factory and the
  renderer attempt are built on the build host and staged (ADR-060, ADR-094);
  the riscv64 recipes only install those trees. Cross builds are keyed by
  target (`build/apk-cross/<arch>/<name>`) and get the target through
  `ELIXOS_CROSS_ARCH`.
- OTP's JIT covers only x86-64 and ARM64, so the riscv64 ERTS is built
  `--disable-jit` and runs the interpreter (`:emu_flavor` is `:emu`).
- The kernel stays mainline 7.2.9 with `kernel/config.riscv64` for QEMU virt
  (8250 UART on `ttyS0`, virtio-mmio and gpex PCIe, Goldfish RTC, syscon
  poweroff). QEMU loads its bundled OpenSBI, which starts the `-kernel` Image.
- The on-box Zig toolchain ships the pinned riscv64 SDK, verified by sha256
  and against ziglang.org's minisign key. Its `cc` bridge is now compiled by
  the build host's Zig for every architecture, so no compiler runs under
  emulation there either.
- Lightpanda publishes no riscv64 build, so the riscv64 service image is
  `apko/system-riscv64.yaml`: `system.yaml` without `elixos-browser`.
  `scripts/build-image.sh` refuses any other difference between the two.
  `Elixos.Browser` reports `{:error, :not_running}` there, as it does when the
  adapter is missing anywhere else.
- `make image-riscv64` builds the image and disk; `make test-qemu-riscv64`
  runs the M28 smoke set (`:riscv64`, excluded from other runs).

- The Emerge renderer builds for riscv64 musl from source on the build host
  (`riscv64gc-unknown-linux-musl`, Alpine riscv64 sysroot) and ships at
  `/system/gui/riscv64-unknown-linux-musl`.

**Consequences.** riscv64 boots are TCG-only on this host: 22.7 s to
`iex(1)>` with the interpreter (ROADMAP M28). The deck console (M33) still
must not depend on Emerge: the renderer is built, but its framebuffer path is
exercised only on x86_64 and the K230 panel is unknown until M30.
