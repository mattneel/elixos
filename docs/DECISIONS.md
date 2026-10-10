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
`elixir_make` needs) as a package fetched into `/data` on first use, never in
the factory. `ZIG_GLOBAL_CACHE_DIR=/data/cache/zig`.

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

---

## Open questions

Decide these with the human. Until then, follow the proposed default.

- **Q1: Package versions.** One version per package system-wide (proposed,
  ADR-015), or something cleverer, such as per-app module renaming?
- **Q2: Process state.** Rebuild from supervisors and `/data` at boot
  (proposed), or persist some process state across boots?
- **Q3: Wi-Fi.** `wpa_supplicant`/`iwd` as a package, or nl80211 from Elixir?
- **Q4: The cyberdeck hardware.** Which machine? It decides the kernel
  options and firmware blobs needed beyond the QEMU set.
- **Q5: Kernel and factory upgrades on hardware.** Two ESP entries with
  `BootNext`, or something simpler?
- **Q6: gsh.** Packaging the `gleam` compiler that gsh drives.
