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
                     │  control + reply pipes; drop uid/groups/capabilities; exec erlexec
                     ▼
          ERTS (dynamic musl, ADR-041), uid/gid 1000, running generation G
                     │  Elixos.Application: Control → Privileges → restore G → AutoCommit
                     ▼
          login REPL on /dev/console: IEx, erl or gsh (ADR-012)
```

There is no bootloader. In QEMU the kernel is loaded with `-kernel`; on
hardware UEFI runs the kernel image itself through its EFI stub (ADR-014).

## §2 Filesystems

**initramfs** (M16, ADR-041: melange builds our packages, apko assembles the
root filesystem from the pinned set, and `scripts/mkinitramfs.sh` writes it as
a gzipped newc cpio - ownership, modes and device numbers come from the layer
tar, so nothing here needs root):

```
/init                          the shim (elixos-shim)
/boot/bzImage | /boot/Image    the kernel the firmware loads (elixos-kernel)
/factory/                      generation 0: the release the shim execs; it
                               points at the machine's OTP install (elixos-factory)
/usr/local/lib/erlang/         OTP 29.1.1 and the ERTS (elixos-otp)
/usr/local/lib/elixir/         Elixir 1.20.4 (elixos-elixir)
/bin/busybox, /lib/…           Alpine's base: busybox, baselayout, musl
/etc/ssl/certs/…               the CA bundle (ca-certificates-bundle)
/etc/elixos/helpers           root-owned named-helper allow-list (M17)
/usr/bin/elixos-postgres-init  libc-free guard which directly execs initdb (M18)
/proc /sys /dev /dev/shm /run /tmp  mount points, declared in the apko config
/priv                          mount point for the persistent disk
```

The initramfs is the immutable base: the factory image cannot be broken by
anything done at runtime, so rescue mode always has something to boot.

**/priv** is the persistent ext4 disk (layout in PROTOCOL.md §7). Everything
the user creates lives there.

**/system** is a separate, read-only gzip SquashFS containing PostgreSQL 17,
its client, extensions and Alpine library closure (M18, ADR-052). PID 1
mounts `/priv/system/system.squashfs` only in normal mode. ICU and timezone
data are exported through read-only bind mounts at their compiled-in
`/usr/share/icu` and `/usr/share/zoneinfo` paths; the factory declares only
empty mount points. Rescue needs neither the service image nor its binaries.

## §3 The shim (PID 1, Zig)

Source: `shim/src/`. Pure logic (`decimal`, `protocol`, `statefile`,
`cmdline`, `recovery`, `helpers` and the sealing parser) is unit tested on the
host; `main.zig` and the sealing filesystem syscalls are syscall glue
tested in QEMU.

### §3.1 Duties

1. Mount `/proc`, `/sys`, `/dev` (devtmpfs), `/dev/shm`, `/run`, `/tmp`; recreate
   `/dev/shm` after devtmpfs hides the initramfs directory. Then mount `/priv`,
   waiting up to `elixos.data_wait` seconds for that device to appear (the
   kernel does not wait for USB or SD storage before running `/init`).
2. Parse `/proc/cmdline`, read the fixed helper list, prepare root-owned sticky
   store/generation directories and the private sealing workspace, then read
   `/priv/boot.state`, plan, persist and log.
   Normal launches also prepare the read-only system image and PostgreSQL's
   uid-70 data/log directories; failure disables the service, not the prompt.
3. Fork and exec ERTS as uid/gid 1000, groups `input`/`video`, with only
   `CAP_NET_BIND_SERVICE` and `PR_SET_NO_NEW_PRIVS` (PROTOCOL.md §3, ADR-046).
4. Event loop on epoll: a signalfd (SIGCHLD, SIGTERM, SIGINT, SIGPWR), the
   control pipe, and a timerfd for the heartbeat deadline.
5. Reap every child. As PID 1 it inherits orphans; zombies must never pile up.
6. Relaunch the BEAM after an exit nobody asked for (short backoff), or carry
   out a requested shutdown. After the BEAM exits, give PostgreSQL SIGINT and
   up to 30 seconds to finish fast shutdown; then SIGTERM/SIGKILL remaining
   helpers and stragglers, sync, unmount the data exports, `/system` and
   `/priv`, and call `reboot(2)`.

The helper allow-list supplies the executable, literal argv and uid/gid;
the BEAM supplies only the name. Replies use a separate pipe. The shim owns
and reaps helper children, and stops them after the BEAM during shutdown.
COMMIT publishes verified, fresh root-owned manifest/blob inodes before
updating `last_good`. Atomic `boot.state` writes use a fresh inode in the
root-private `/priv/.seal` directory, not a BEAM-writable temporary path.

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
`execve` keeps PID 1, the BEAM and helpers stay its children, and both pipe
fds, the BEAM's pid, its actual generation and the live helper pids are handed
over in argv. Build that argv in fixed storage before arming the handler;
the handler never allocates or reconstructs a generation from a pending NEXT.

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
forgotten) as a candidate manifest `/priv/generations/<n>.gen` with a boot
spec, then sends `NEXT <n>` so the shim boots it next time, provisionally.
COMMIT seals that manifest and its blobs as fresh root-owned, read-only
inodes; retained writable descriptors cannot change the sealed paths.
Generation 0 is the factory and never touches the disk.

Booting generation G means: read and verify every module blob of G against
its content hash before loading any, load the verified bytes, run G's boot
spec, then start the login REPL. Boot never replays the journal tail:
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

`Elixos.Application` opens `Elixos.Shim.Control` on the inherited fd
(heartbeats start), then `Elixos.Privileges` on the separate reply fd, before
restoring the generation and running its boot spec. `Elixos.Postgres` and
`Elixos.Oban` construct their asynchronous managers next (M18, M19): the
restore's boot spec includes each installed app's `Elixos.Oban.configure_app!/2`
MFAs, so the scheduler's declarations are collected while modules and services
restore. The recorder and agent supervisors follow, then SSH and the console
login REPL. `Elixos.Oban.activate/0` runs once the tree - restore included -
is up, and only then may a queue run a job; `Elixos.Boot.AutoCommit` runs only
in normal mode. A boot-critical restore failure exits the VM non-zero so the
shim counts the attempt (ADR-007); database, scheduler and SSH startup
failures remain non-critical.

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
  oban, persist, min_os, boot); plain Mix ignores it. Validated by
  `Elixos.Package.Spec`. The `oban:` declaration (`queues:`, `cron:`) is
  persisted with the app and becomes part of the generation's boot spec, so an
  installed app's queues and cron come back with the image (ADR-057).
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
