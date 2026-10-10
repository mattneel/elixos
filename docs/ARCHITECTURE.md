# Architecture

Read docs/VISION.md first. Exact formats live in docs/PROTOCOL.md; the reasons
behind each choice live in docs/DECISIONS.md.

## §1 The boot chain

```
UEFI firmware (hardware)            QEMU -kernel/-initrd (development)
        │                                     │
        └──► mainline bzImage via EFI stub ◄──┘    unmodified, configured (ADR-001)
                     │
                     ▼
          initramfs: /init = Zig shim (PID 1)      never exits (ADR-002)
                     │  mounts /proc /sys /dev /run /tmp, /priv (ext4)
                     │  reads cmdline + /priv/boot.state, plans, persists
                     │  fork + exec erlexec (no shell), control pipe on fd ≥ 3
                     ▼
          ERTS (dynamic musl, ADR-008) running generation G
                     │  Elixos.Application: Control → restore G → AutoCommit
                     ▼
          login REPL on /dev/console: IEx, erl or gsh (ADR-012)
```

There is no bootloader. In QEMU the kernel is loaded with `-kernel`; on
hardware UEFI runs the kernel image itself through its EFI stub (ADR-014).

## §2 Filesystems

**initramfs** (built by `scripts/build-initramfs.sh` with the kernel's own
`usr/gen_init_cpio`, so no root is needed):

```
/init                          the shim
/dev/console, /dev/null        device nodes, so PID 1 has stdio before devtmpfs
/proc /sys /dev /run /tmp      mount points
/priv                          mount point for the persistent disk
/factory/                      generation 0: ERTS + OTP apps + Elixir + Elixos (M4)
/lib/ld-musl-x86_64.so.1       musl's dynamic loader, also its libc.so (M4)
```

The initramfs is the immutable base: the factory image cannot be broken by
anything done at runtime, so rescue mode always has something to boot.

**/priv** is the persistent ext4 disk (layout in PROTOCOL.md §7). Everything
the user creates lives there.

There is no `/bin`, no `/usr`, no `/etc` beyond what a feature needs (for
example a CA bundle for Hex in M11).

## §3 The shim (PID 1, Zig)

Source: `shim/src/`. Pure logic (`decimal`, `protocol`, `statefile`,
`cmdline`, `recovery`) is unit tested on the host; `main.zig` is syscall glue
tested in QEMU.

### §3.1 Duties

1. Mount `/proc`, `/sys`, `/dev` (devtmpfs), `/run`, `/tmp`; then `/priv`,
   waiting up to `elixos.data_wait` seconds for that device to appear (the
   kernel does not wait for USB or SD storage before running `/init`).
2. Parse `/proc/cmdline`, read `/priv/boot.state`, plan, persist, log.
3. Fork and exec ERTS with the launch contract (PROTOCOL.md §3).
4. Event loop on epoll: a signalfd (SIGCHLD, SIGTERM, SIGINT, SIGPWR), the
   control pipe, and a timerfd for the heartbeat deadline.
5. Reap every child. As PID 1 it inherits orphans; zombies must never pile up.
6. Relaunch the BEAM after an exit nobody asked for (short backoff), or carry
   out a requested shutdown: SIGTERM, then SIGKILL stragglers, sync, unmount
   `/priv`, `reboot(2)`.

Allocate nothing after startup. Single-threaded. Raw `std.os.linux` syscalls.

### §3.2 Heartbeats

Before the first `HB` the deadline is `elixos.boot_grace`; after it,
`elixos.hb_timeout`. When the deadline passes, the shim SIGKILLs the BEAM and
treats it like a crash. To the shim, a crash and a hang are the same event.

### §3.3 Recovery policy (ADR-007)

The pure function `recovery.planLaunch(state, policy, overrides)` decides what
to boot; the shim persists `next_state` **before** launching, so a crash, a
hang or a power cut mid-boot still counts.

```
safe override (elixos.safe, unreadable state, no /priv)  → factory, rescue, state untouched
generation override (elixos.generation=N)                → N once, state untouched
attempts < max_attempts                                  → current, attempts + 1
attempts ≥ max and current ≠ last_good                   → last_good, attempts = 1  (fallback)
attempts ≥ max and current = last_good                   → factory, rescue, state untouched
```

`COMMIT` (sent by `Elixos.Boot.AutoCommit` after healthy uptime) is what turns
a generation good and resets attempts. After an unrequested exit the shim
re-plans with the generation override dropped and the safe override kept.
`shim/src/recovery.zig` has one test per rule, plus a crash-loop walk.

### §3.4 Surviving its own panic (ADR-004, M8)

Override the root panic handler (`pub const panic = std.debug.FullPanic(f)`)
so that a panic re-execs `/init` in a recovery mode instead of returning.
`execve` keeps PID 1, the BEAM stays its child, and the inherited control fd
and the BEAM's pid are handed over in argv. Build that argv at startup so the
handler never allocates.

### §3.5 Test hooks

`elixos.test.*` parameters (PROTOCOL.md §5) exist only in `-Dtest-hooks=true`
builds. `stop_before_launch` lets M3 tests check planning and persistence in
every later milestone; `shim_panic_after` drives the M8 tests.

## §4 The live image (ADR-005)

The BEAM has no `save-lisp-and-die`, so the image is **code plus data**,
rebuilt into a running system at every boot. Smalltalk is the model: an image
plus a changes log that every definition is appended to.

### §4.1 Capture

Every module defined at a REPL is captured with its exact bytecode via a
compilation tracer's `{:on_module, bytecode, _}` event. Verified on Elixir
1.20.4 (details in `Elixos.Image.Capture`'s moduledoc): the tracer must be in
the env passed to `Code.eval_quoted_with_env/4`; `Code.eval_string/3` and the
global `:tracers` option do not see modules defined in evaluated code. IEx
evaluates with `eval_quoted_with_env/4` and `IEx.Server.run/1` accepts an
`:env`, so the login IEx carries the tracer from its first prompt.

### §4.2 Store

Module bytecode goes into a content-addressed store
(`/priv/store/<2 hex>/<62 hex>`, SHA-256). Writes are atomic; reads verify the hash.

### §4.3 Journal

Each change (`{:module, mod, hash}`, `{:forget, mod}`, `{:generation, n}`) is
appended to `/priv/journal.log` and fsync'd before anything else happens.
Records are length-prefixed and CRC'd; a torn tail from a crash is detected
and truncated, while damage in the middle is reported and left for a human.

### §4.4 Generations

`Elixos.save/1` writes the working set (latest hash of every module not
forgotten) as an immutable manifest `/priv/generations/<n>.gen` with a boot
spec, then sends `NEXT <n>` so the shim boots it next time, provisionally,
until it commits. Generation 0 is the factory and never touches the disk.

Booting generation G means: load every module of G from the store, run G's
boot spec, then start the login REPL. Boot never replays the journal tail:
unsaved work is recoverable on request, never applied by surprise.

### §4.5 Recovery tools

- `Elixos.unsaved(n)` / `Elixos.recover(modules)`: Smalltalk's "recover lost
  changes", from the journal.
- `Elixos.Image.Bisect.first_bad/2`: find the journal entry that broke things.
- `Generation.diff/2`: what changed between two generations.
- Rescue mode: the factory with `/priv` mounted and no user code loaded.

### §4.6 The sticky base

The factory's code directories are marked sticky (`:code.stick_dir/1`), the
BEAM's answer to SBCL's package locks: a REPL slip cannot redefine `Enum` and
take the image down.

### §4.7 Process state (OPEN)

Proposed default: process state is not persisted. Supervisors rebuild it at
boot from code and from data the app keeps in `/priv` (files, DETS, Mnesia).
See DECISIONS.md, open questions.

## §5 The BEAM side of boot

`Elixos.Application`, in order: `Elixos.Shim.Control` on the inherited fd
(heartbeats start) → restore the generation and run its boot spec →
`Elixos.Boot.AutoCommit` (normal mode only) → the login REPL on the console via
`:shell.start_interactive/1`. A failure before the REPL must exit the VM
non-zero so the shim counts the attempt (ADR-007).

## §6 REPLs are the shells (ADR-012)

`Elixos.REPL` maps names to OTP's shell contract, an MFA returning the shell's
pid: `:erl` is `{:shell, :start, []}`, `:iex` spawns `IEx.Server.run/1` with
the capture env, `:gsh` appears only when installed. The same MFA serves:

- the console, via `:shell.start_interactive/1` at boot;
- Ctrl-G job control (`s shell`, `c`, `j`), several REPLs on one tty;
- SSH, through the `ssh` daemon's per-user shell fun (M12).

All of them see one world. There is no uid between them, and OTP's restricted
shell only vets what is typed at the prompt, so it is a guardrail, not a
security boundary. That is fine for a single-user machine (ADR-013).

**Session directories (ADR-020).** Each session has its own working directory,
starting at `/priv/home`, keyed by its process-group leader — which everything
spawned from that REPL inherits. The login REPLs therefore carry session-aware
`cd/1`, `pwd/0` and `ls/0,1` (IEx by importing Elixos's helpers into its
evaluation environment, erl through `user_default`), relative paths resolve
against the session's directory, and native tools run with `cd:` set to it.
The VM's working directory never moves (ADR-016).

## §7 Apps on Elixos (ADR-010, ADR-011, ADR-015)

- **Target, not environment.** `MIX_TARGET=elixos` keeps dev/test/prod intact.
  An app adds one line to `config/config.exs`:
  `if config_target() == :elixos, do: import_config("elixos.exs")`.
  Builds land in `_build/elixos_<env>`.
- **Install metadata in `mix.exs`.** The `elixos:` project key (services,
  persist, min_os, boot); plain Mix ignores it. Validated by
  `Elixos.Package.Spec`.
- **The OS provides the API.** Apps depend on
  `{:elixos, "~> 0.1", targets: :elixos}`; the installer satisfies it with the
  running OS and refuses a bundled copy.
- **One namespace, one version.** All apps share the VM's module namespace, so
  `Elixos.Package.Resolver` keeps one version of each package system-wide and
  refuses installs that would break an installed app.
- **Builds run in a child BEAM.** Mix changes the working directory while it
  builds (`Mix.Project.in_project/4` cd's), and on Elixos that would move it
  for every program (ADR-016). `Elixos.Package.install/1` therefore execs a
  second ERTS (erlexec directly, no shell) to compile, then loads the result.

## §7a Packages by name (ADR-019, M14)

Software is installed from **Hex repositories**: a repository is a name, a URL
and a public key, and `/priv/hex/repos.exs` is the entire trust decision
(PROTOCOL.md §8). The official `elixos` repository is a static repository on
GitHub Pages, built and published by CI (`.github/workflows/hex-repo.yml`); the
factory ships its public key and presets the entry in `/factory/hex/`, so it is
trusted out of the box. Adding a repository with its key is the consent step; an
install never trusts one implicitly, and on a single-user machine there is
nothing else to consent to (no sudo).

`Elixos.Package.install/1` by name finds the package among the trusted repos
(a name in two repos is an error naming both), fetches and unpacks the tarball
into `/priv/apps/`, and hands the directory to the M11 path below. The apt
verbs are functions: `add_repo/3`, `remove_repo/1`, `repos/0`, `search/1`,
`info/1`, `upgrade/0,1`, `remove/1`.

**Programs are packages, commands are functions.** A package exposes an Elixir
API and no CLI; when it must run a native tool it execs it directly with `cd:`
set to the caller's session directory (ADR-020), never through a shell
(ADR-012) and never by changing the VM's working directory (ADR-016). The M11
toolchain's `Zig` module (`Zig.init/1`, `Zig.build/2`) is the first instance of
that.

## §8 The toolchain on the box (ADR-008, ADR-009)

- ERTS links dynamically against musl so NIFs can `dlopen`; statically
  linked musl cannot. musl's loader is its libc, so this costs almost nothing,
  and precompiled musl NIFs from packages load as-is.
- `zig cc` is the system C/C++ compiler and cross compiler, shipped in a
  toolchain package fetched into `/priv` on first use, never in the factory.
  `ZIG_GLOBAL_CACHE_DIR=/priv/cache/zig` keeps libc builds across boots.
- `elixir_make` shells out to `make`, and make runs recipes with `/bin/sh`, so
  the toolchain package carries make and a BusyBox sh. They exist only for
  builds; nobody ever gets an sh prompt.
- Hex needs CA certificates; ship a bundle where `:public_key.cacerts_get/0`
  finds it.
- gsh needs the `gleam` binary, which would also live in a package; LFE and
  Clojerl are Hex packages of their own (`lfe`, `clojerl`). `Elixos.REPL`
  offers a language only when its shell entry point is really callable.

## §10 Agents on Elixos (ADR-032, ADR-036, M15)

An agent is an ordinary module: Jido's `use Jido.Agent` for the framework's
agents, or any module with `start_link/1` (and `snapshot/1` if it remembers
something). `Elixos.Agents.start/2` runs it under `Elixos.Agents.Supervisor`
and records it in the image's journal, so the next boot starts it again - the
answer to Q2 (rebuild from supervisors and `/priv`, ADR-032). What it
remembers is written to `/priv/agents/<id>.term` when the image is written
(`Elixos.save/1`) and when it stops; a Jido agent's memory is its state map,
handed back as `initial_state` on the next start.

Jido is a dependency of the OS itself (ADR-036): the factory ships it, and
mnesia (jido_signal's OTP dependency) rides in the release with it, so no
installation stands between a prompt and an agent. The model is a
provider, not the definition: `Elixos.Agents.LLM` speaks chat completions and
the Responses API over OTP's own sockets, with an API key, with nothing, or
with a ChatGPT subscription (`~/.codex/auth.json`, refreshed as needed) - so
an agent without a model works, and a model without an API key works.

## §9 Real hardware (ADR-014, M13)

- A FAT ESP whose `EFI/BOOT/BOOTX64.EFI` is the kernel itself, with the
  initramfs and command line built in (`CONFIG_INITRAMFS_SOURCE`,
  `CONFIG_CMDLINE`: configuration, never a patch). The built-in line is the
  default - what the firmware passes when it passes nothing - and an owner who
  needs other arguments (`elixos.data=/dev/nvme0n1p2`, say) supplies their own
  at the firmware level, which then takes over.
- Console on the panel: `console=tty0 fbcon=font:TER16x32` (Terminus 16x32 is
  built into the kernel), simpledrm on the firmware framebuffer.
- Generation fallback lives in the shim, so the firmware needs no A/B logic.
  Only kernel or factory upgrades would need a second boot entry; not yet planned.
- Wi-Fi needs a WPA supplicant (`wpa_supplicant` or `iwd` as a package, or
  nl80211 from Elixir); not yet scheduled.
