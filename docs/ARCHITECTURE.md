# Architecture

Read docs/VISION.md first. Exact formats live in docs/PROTOCOL.md; the reasons
behind each choice live in docs/DECISIONS.md.

## §1 The boot chain

```
UEFI firmware (hardware)            QEMU -kernel/-initrd (development)
        │                                     │
        └──► bzImage (x86_64) / Image (aarch64) ◄──┘   mainline, unmodified (ADR-001)
                     │
                     ▼
          initramfs: /init = Zig shim (PID 1)      never exits (ADR-002)
                     │  mounts /proc /sys /dev /run /tmp, /priv (ext4)
                     │  reads cmdline + /priv/boot.state, plans, persists
                     │  control + reply pipes; drop uid/groups/capabilities; exec erlexec
                     ▼
          ERTS (dynamic musl, ADR-041), uid/gid 1000, running generation G
                     │  Elixos.Application: Control → Privileges → managers → restore G
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

`kernel/elixos.config` is the common fragment; `kernel/config.x86_64` and
`kernel/config.aarch64` hold architecture-specific options. The merge is
checked by `scripts/check-kernel-config.sh`. On the x86_64 build host,
`melange/kernel-cross.yaml` and `melange/otp-cross.yaml` cross-build the
aarch64 kernel and ERTS natively (ADR-060). Elixir bytecode is reused across
architectures; the factory is packaged separately for each target because
Emerge's native loader must select that target's musl renderer (ADR-069).

`scripts/build-image.sh` keys APK reuse on each recipe's inputs and the
published APK checksum, and keys image assembly separately. An OS source
edit affects the factory, not the kernel or OTP recipes. `FORCE=1` bypasses
those caches. `make image` builds the host architecture; `make images`
builds both. Each rebuilt rootfs and service image is assembled twice for
digest agreement and carries an SBOM.

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
its client, pgvector, TimescaleDB and their Alpine library closure (M18,
ADR-052), plus Lightpanda and its private glibc under `/system/browser`
(M25, ADR-064), and the target-specific Emerge raster NIF with its private
musl library closure under `/system/gui` (M27, ADR-069).
PID 1 mounts `/priv/system/system.squashfs` only in normal mode. ICU and
timezone data are exported through read-only bind mounts at
their compiled-in `/usr/share/icu` and `/usr/share/zoneinfo` paths; the
factory declares only empty mount points. Rescue needs neither the service
image nor its binaries.

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

### §4.7 Process state

Boot reconstructs processes from supervisors, code and data in `/priv`, not
from a saved BEAM heap. Agents opt into snapshots: their saved state is
restored as initial state on the next start (ADR-032, §10). Arbitrary
process-state persistence remains future work (DECISIONS.md Q2).

## §5 The BEAM side of boot

`Elixos.Application` starts the installed-service supervisor, then
`Elixos.Shim.Control` on the inherited fd (heartbeats start) and
`Elixos.Privileges` on the separate reply fd. The asynchronous PostgreSQL and
Oban managers are created **before** generation restore (M18, M19), so
restored apps can register their `Elixos.Oban.configure_app!/2` declarations
without starting queues prematurely.

Restore is followed by the recorder, agent supervisor and agent manager,
Ask's question queue, the browser manager, SSH, console login and auto-commit.
`Elixos.Oban.activate/0` runs only after the whole tree, restore included, is
up. Auto-commit runs only in normal mode. A boot-critical restore failure
exits the VM non-zero so the shim counts the attempt (ADR-007); database,
scheduler, browser and SSH startup failures remain non-critical.

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

**The question queue (ADR-059).** Questions are data in `Elixos.Ask`, one queue
in the OS supervision tree: an id, a kind, the prompt, the options and the
asking process, with `ask/2` blocking the asker until the question is resolved.
Every front-end is only a view over that queue. The console REPL is the first
one and prints a notice line per new question — `elixos-ask: question <id>
(<kind>): <prompt>`, PROTOCOL.md §6 — so a watching human sees an agent's
question the moment it exists (M27 adds the framebuffer view). An answer is
validated against the question that asked it before it is accepted, so a
front-end cannot hand back a value the question never allowed.
`Elixos.Ask.Action` (`ask_human`) is the Jido action an agent uses to ask and
to carry the answer back into its state.

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
- **Installed packages are Mix dependencies (M26, ADR-068).** The build child
  starts Mix and prepends `Elixos.Package.SCM` before dependency loading.
  It resolves an installed dependency to `/priv/apps/<name>` after checking
  its `.app` version against the requirement. Explicit path/git sources,
  missing packages and incompatible installed versions fall through to the
  normal SCMs. Installed ebins are also on the child's code path; the project
  sources are not rewritten.

## §7a Packages by name (ADR-019, M14)

Software is installed from **Hex repositories**: a repository is a name, a URL
and a public key, and `/priv/hex/repos.exs` is the entire trust decision
(PROTOCOL.md §8). The official `elixos` repository is a static repository on
GitHub Pages, built and published by CI (`.github/workflows/hex-repo.yml`); the
factory ships its public key and presets the entry in `/factory/hex/`, so it is
trusted out of the box. Adding a repository with its key is the consent step; an
install never trusts one implicitly, and on a single-user machine there is
nothing else to consent to (no sudo).

`Elixos.Package.install/1` by name resolves the dependency closure among the
trusted repos (a name in two repos is an error naming both), checks the
system-wide plan and installs dependencies before dependents. Verified
tarballs are unpacked into `/priv/apps/<name>-<version>/` for building;
the installed runtime tree is `/priv/apps/<name>/`, with `ebin/` and `priv/`.
The apt verbs are functions: `add_repo/3`, `remove_repo/1`, `repos/0`,
`search/1`, `info/1`, `upgrade/0,1`, `remove/1`.

**Programs are packages, commands are functions.** A package exposes an Elixir
API and no CLI; when it must run a native tool it execs it directly with `cd:`
set to the caller's session directory (ADR-020), never through a shell
(ADR-012) and never by changing the VM's working directory (ADR-016). The M11
toolchain's `Zig` module (`Zig.init/1`, `Zig.build/2`) is the first instance of
that.

## §8 The toolchain on the box (ADR-008, ADR-009)

- ERTS links dynamically against musl so NIFs can `dlopen`; statically
  linked musl cannot. musl's loader is its libc, so this costs almost nothing,
  and a matching musl NIF can load when its required shared libraries are present.
- `zig cc` is the system C/C++ compiler and cross compiler. The signed
  `elixos-toolchain` APK is unpacked by `scripts/mkdisk.sh` into
  `/priv/toolchain` when the pristine disk is created, not fetched on first
  use. `Zig.init/1`, `Zig.build/2` and `Zig.cc/2` expose it to sessions.
  `ZIG_GLOBAL_CACHE_DIR=/priv/cache/zig` keeps libc builds across boots.
- Rust and Cargo are included under `/priv/toolchain/rust` with their Alpine
  library closure (M25, ADR-066). `Rust.init/1`, `Rust.cargo/2` and
  `Rust.rustc/2` exec them directly; Cargo uses `/priv/toolchain/cc` as linker.
  Native commands use the session's directory without changing the VM's cwd.
- BusyBox sh is supplied by the Alpine base for tooling (ADR-041), not as a
  login shell or shim launch path. The acceptance NIF fixture invokes `cc`
  directly rather than relying on shell-based `elixir_make` recipes.
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

## §11 Browser service (ADR-064, ADR-065, M25)

`Elixos.Browser` starts asynchronously in normal mode. A pinned manifest
under `/system/browser` chooses the executable, arguments and private glibc
loader; the binary is built into the image, never downloaded by the guest.
The process is a Port, and `cdp_ex` speaks CDP through the
`Elixos.Browser.CDP` session/page interface. `jido_browser` itself is not an
OS dependency: ADR-065 records why it and `light_cdp` were rejected.

`navigate/1` returns the page's text, `eval/1` evaluates JavaScript,
`screenshot/0` returns PNG bytes, and `stop/0` closes the adapter.
The browser does not run in rescue and cannot block console startup.

## §12 Framebuffer GUI (M27, in progress)

`Elixos.GUI` starts asynchronously after the Ask queue in normal mode, and
only when `/dev/fb0` exists. Rescue remains console-only. The GUI renders
text, choice, multi-choice and confirmation dialogs from the existing Ask
queue; resolving a dialog uses `Elixos.Ask.answer/2` or `dismiss/1`, not a
second question store. Ask subscriptions provide an atomic initial snapshot
and subsequent queue changes.

Emerge 0.4.2 runs a headless CPU raster renderer. It delivers RGBA8888
`VideoInterop.Frame` binaries to the GUI owner process, which validates the
dimensions, format and stride before sending them to the libc-free
`elixos-gui-io` Port. The helper writes the fbdev mapping and acknowledges
each presented frame. One frame is in flight; newer pending frames replace
older pending frames rather than building an unbounded queue.

The same helper reads evdev keyboard and pointer events. Elixir owns focus,
text editing, selections and Ask validation. A root-owned console-handover
broker grants a single lease to uid 1000, unbinds the framebuffer console
while the GUI owns it, and rebinds it before acknowledging a graceful stop
or admitting another lease. Closing the lease also restores the console
after an ordinary GUI/helper failure (ADR-070).

The image owns the renderer ABI: the x86_64 musl artifact is checksum-pinned;
ARM64 uses the locked source build because upstream ships no ARM64 musl
artifact. Each target's factory points at its own renderer and private
dependency closure. A renderer-only change does not invalidate kernel or
OTP packages. Backend selection alone does not choose musl.

GUI startup failures are non-critical and the login REPL still starts. The
renderer is a NIF inside the BEAM, however: a native crash can still terminate
the VM. Input-device hotplug currently requires restarting the GUI.

The host suite, four off-screen raster dialogs and the x86_64 GPU acceptance
have passed. The [development recording](../demos/m27-gui.mp4) exercises real
evdev keys and console handback. ARM64 packaging and the full milestone gate
are not yet complete; the roadmap checklist remains unticked.
