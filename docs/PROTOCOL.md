# Interfaces that are API

Everything in this file is matched byte for byte by tests. Change it only
together with the tests, both implementations and an ADR.

## §1 Numbers

Every number crossing a boundary (control lines, `boot.state`, the boot
environment, `elixos.*` parameters) is a **canonical decimal u32**:
`0` or `[1-9][0-9]*`, value at most 4294967295, ASCII digits only, no sign,
no leading zeros, no whitespace.

Implementations: `shim/src/decimal.zig` (`parseU32`) and `Elixos.Decimal`
(`parse_u32/1`). Their tests mirror each other case for case.

## §2 Control and helper replies

**Transport.** Before exec'ing ERTS the shim creates two pipes. The BEAM gets
the control pipe's write end in `ELIXOS_CTL_FD` and the reply pipe's read end
in `ELIXOS_REPLY_FD` (§3). The shim keeps the opposite ends; they survive its
panic re-exec. The pipe inodes belong to uid/gid 1000: control mode 0200,
reply mode 0400, so the unprivileged BEAM can reopen `/proc/self/fd/<n>`.
Each direction has one writer. Writes are below `PIPE_BUF` and atomic.

**Framing.** ASCII lines terminated by `\n`. A line longer than 64 bytes
(excluding the newline) is `too_long`, whatever its content: the shim discards
up to the next newline and logs it. Anything else that is not exactly a
message below is `invalid`: logged and ignored, never fatal.

| line             | message            | effect in the shim (`recovery.applyMessage`)            |
|------------------|--------------------|---------------------------------------------------------|
| `HB`             | `:heartbeat`       | resets the heartbeat deadline; no state change          |
| `COMMIT <gen>`   | `{:commit, gen}`   | if `gen == current` and the running generation: seal and verify its recovery files, then `last_good = gen`, `attempts = 0`; else ignored |
| `NEXT <gen>`     | `{:next, gen}`     | `current = gen`, `attempts = 0` (boots next time)       |
| `REBOOT`         | `:reboot`          | remembered; carried out when the BEAM exits             |
| `POWEROFF`       | `:poweroff`        | remembered; carried out when the BEAM exits             |
| `HALT`           | `:halt`            | remembered; carried out when the BEAM exits             |
| `HELPER <name>`  | `{:helper, name}`  | request the fixed image-declared helper; no boot-state change |

Every state change is persisted to `boot.state` (§4) before the next line
is read. After requesting a shutdown, the BEAM stops itself
(`:init.stop/0`); the shim then reaps it and performs the shutdown.

**Helpers.** Names are ASCII `[a-z0-9-]{1,32}`. The shim reads
`/etc/elixos/helpers` once at startup: up to 32 records, each at most 1024
bytes excluding its newline, with `<name> <uid>:<gid> <absolute path> [args...]`.
Blank/comment lines are ignored; tokens are separated by spaces or tabs.
Arguments are literal image-owned bytes, never shell syntax or caller input.
Any malformed, duplicate or overflowing list disables the entire list.

The reply pipe carries `HELPER <name> OK <pid>\n` (positive canonical u32)
or `HELPER <name> REFUSED\n`. Unknown names and failed forks are refused and
logged (§6); PostgreSQL helpers are also refused in rescue or without the
read-only service tree (mounted on machines, baked into native OCI images).
One live child per name is reused; exited children are reaped. `OK`
acknowledges a fork, not successful exec or SQL readiness.
Helpers run as the declared uid/gid, without the BEAM's supplementary groups
or capabilities. PostgreSQL helpers receive a fixed child-only library/PATH
environment rooted in `/system`; caller argv and environment are never used.
After the BEAM stops, the shim sends PostgreSQL SIGINT and waits up to 30
seconds for fast shutdown before stopping other helpers. Deadline expiry is
logged before SIGKILL, never presented as clean shutdown (ADR-053).

`Elixos.Privileges` serializes requests independently of Control's heartbeat.
Timeouts do not replay effects: an active timed-out request retains its place
until its late reply drains, while queued timeouts never write a request.
A failed reply channel remains closed until the next VM. The raw reader does
not use fixed multi-byte reads, which OTP waits to fill on a live pipe.

**Golden vectors.** `spec/protocol.vectors` lists wire lines and their
meaning. Both `shim/src/protocol.zig` and `os/test/elixos/shim/protocol_test.exs`
run every line, and valid lines must round-trip through encode.

## §3 The launch contract (shim → ERTS)

The shim forks and execs `erlexec` from the generation's ERTS directly.
No shell script runs in this launch path (ADR-012, amended by ADR-041 to
permit BusyBox sh for tooling). Set what the release's `bin/` scripts would
have set (like Nerves' erlinit does): `ROOTDIR`, `BINDIR`, `EMU`, `PROGNAME`,
plus `HOME=/priv/home`, `TERM=linux`, `LANG=C.UTF-8`,
`PATH=/priv/toolchain:/usr/local/bin:/bin:/usr/bin` when writable `/priv`
is available (`/usr/local/bin:/bin:/usr/bin` otherwise), and:

| variable            | value                                                  |
|---------------------|--------------------------------------------------------|
| `ELIXOS_GENERATION` | generation being booted; `0` is the factory            |
| `ELIXOS_MODE`       | `normal` or `rescue`                                   |
| `ELIXOS_ATTEMPT`    | `next_state.attempts` of the plan that launched it     |
| `ELIXOS_CTL_FD`     | fd of the control pipe's write end (not CLOEXEC, ≥ 3)  |
| `ELIXOS_REPLY_FD`   | fd of the helper reply pipe's read end (not CLOEXEC, ≥ 3) |
| `ELIXOS_RUNTIME`   | `machine` or `container`; shim-owned boundary marker |

- Machine fds 0, 1, 2 are `/dev/console`; native OCI retains the container
  runtime's stdio. The working directory is `/` and stays there (ADR-016).
  With writable `/priv`, the shim sets `ERL_CRASH_DUMP` to
  `/priv/crash/gen<g>-attempt<n>.dump` (§7, ADR-025) and
  `ERL_CRASH_DUMP_BYTES` to 1 MiB. Without writable state both are unset.
- The BEAM runs as `elixos`, real/effective/saved/filesystem uid 1000 and gid
  1000, with supplementary `input` (23) and `video` (27). Its permitted,
  effective, inheritable and ambient capabilities contain only
  `CAP_NET_BIND_SERVICE` (bit 10, mask `0000000000000400`), for SSH's port 22.
  The child drops groups, gid and uid before exec and sets
  `PR_SET_NO_NEW_PRIVS`; no program can regain privilege through exec.
- The emulator runs `-mode interactive`: Elixos loads code at run time (the
  live image restores modules, and the box builds Mix projects), and the
  embedded code server refuses to load anything from the code path.
- The emulator is launched with `+Bc`. The console is cooked: type Ctrl+C
  **then Enter** to deliver the interrupt byte to OTP's console driver.
  Anything following that byte in the same input chunk is discarded; wait
  for the interrupted prompt before typing the next expression (ADR-024).
  Ctrl-G job control likewise needs Enter on this console.
- The BEAM must send its first `HB` within `elixos.boot_grace` seconds and then
  at least every `elixos.hb_timeout` seconds; it sends one per second.
- When the BEAM exits, the shim logs `beam exited status=<n>` or
  `beam killed by signal <n>` (§6) and asks `recovery.onBeamExit` what next.

The four boot variables are parsed by `Elixos.Boot.Env.parse/1`; the required
reply descriptor is validated by `Elixos.Privileges` before opening its client.
Panic adoption preserves both pipe ends, the actual running generation
(which may differ from NEXT's `current`), and live helper pids.

### Native OCI launch and shutdown

The native build (`-Dcontainer=true`) requires `container=oci` and a
root-owned regular `/etc/elixos/runtime` containing exactly `container\n`.
It validates procfs and its PID namespace, rejects initial-namespace PID 1,
and becomes a child subreaper when launched below a provider's init.
`/priv` must already be a writable, safely owned directory supplied by the
runtime. This build never mounts/unmounts filesystems or reboots the kernel.
An invalid initial-namespace PID 1 idles instead of exiting.

Its PATH is `/toolchain:/usr/local/bin:/bin:/usr/bin`; `/toolchain` exists
only in the SDK image. `ELIXOS_CONSOLE=1` enables IEx; all other values keep
the default headless startup. Exact `ELIXOS_SAFE=1` selects rescue. Host
`/proc/cmdline` is never used for shim or BEAM boot policy.

Ordinary OCI application environment and runtime secrets are forwarded from
the immutable startup environment. The shim supplies authoritative release,
identity and control values: caller `ROOTDIR`, `BINDIR`, `EMU`, `PROGNAME`,
`HOME`, `TERM`, `LANG`, `PATH`, all launch variables in the table above and
`ELIXOS_CONSOLE` are replaced. `ERL_*`, `ERTS_*` and `LD_*` are excluded so
caller flags/loaders cannot override the launch or recovery contract.
Forwarding allocates pointer slots once at startup, not copies of secrets;
panic re-exec retains the original environment. Nothing mutates the running
BEAM's cwd or environment.

Control-line bytes and `boot.state` are unchanged. The shim supervises and
signals only its own children; hardware/mount helpers are refused even if
listed in the image. PostgreSQL helpers retain their existing uid and
child-only environment. SIGTERM/INT/PWR request an orderly poweroff; after
the BEAM and helpers stop, poweroff/halt exit 0 and reboot exits 75. The
orchestrator decides whether to start another process. No global signal
broadcast, system-wide sync, unmount or kernel reboot occurs.

`Elixos.Boot.Env.runtime/1` requires the complete ordinary boot contract
before recognizing `ELIXOS_RUNTIME`. A marker alone is not an OS. Legacy
complete contracts without the marker mean `:machine`; an unknown explicit
marker is an error. Hosts without a shim contract remain `:host`.

## §4 `boot.state`

Path: `/priv/boot.state`. Single writer: the shim (ADR-006). The BEAM may read
it, never write it.

Canonical form, exactly (encode always writes this):

```
current=<gen>
last_good=<gen>
attempts=<n>
```

Parse rules (`shim/src/statefile.zig`):

1. Strip one trailing `\n` if present. Empty text has no lines.
2. Split on `\n`. Each line must contain `=` with a non-empty key before it,
   otherwise `BadLine` (so an empty line is `BadLine`).
3. The key must be `current`, `last_good` or `attempts`, else `UnknownKey`.
4. A key seen twice is `DuplicateKey`.
5. The value must be a canonical decimal (§1), else `BadValue`.
6. After all lines, any key never seen is `MissingKey`.

Lines are checked in order and the first error wins.

Writes are atomic: create a fresh root-owned `/priv/.seal/boot.state.tmp`
with EXCL and NOFOLLOW, fsync it, rename it over `boot.state`, fsync `/priv`.
The staging parent is root-only mode 0700; stale temporary paths are removed,
never truncated or followed. Retained writable candidate descriptors cannot
reach published recovery inodes.

If `boot.state` is missing, the shim plans from the defaults (`0/0/0`).
If it exists but does not parse, the shim plans from the defaults with the
rescue override **and never writes the file**, so the evidence survives.

## §5 Kernel command line

Shim side (`shim/src/cmdline.zig`); the last valid occurrence of a key wins,
and malformed or unknown `elixos.*` tokens are counted and logged, never applied:

| parameter                       | default    | meaning                                         |
|---------------------------------|------------|-------------------------------------------------|
| `elixos.safe[=1\|0]`            | off        | boot the factory in rescue mode                 |
| `elixos.live[=1\|0]`            | off        | keep writable `/priv` in RAM; never mount the data device |
| `elixos.generation=<gen>`       | none       | boot `<gen>` once, outside attempt accounting   |
| `elixos.max_attempts=<n≥1>`     | 3          | launches before falling back                    |
| `elixos.hb_timeout=<s≥1>`       | 10         | seconds without `HB` before killing the BEAM    |
| `elixos.boot_grace=<s≥1>`       | 120        | seconds allowed before the first `HB`           |
| `elixos.data=/dev/<dev>`        | /dev/vda   | ext4 device mounted on `/priv`                  |
| `elixos.data_wait=<s≥0>`        | 10         | seconds to wait for that device to appear        |
| `elixos.coproc_link=<if>,<ip>/<len>` | none  | give interface `<if>` IPv4 `<ip>/<len>` (len 1-32) and bring it up: the coprocessor link (M29) |

`elixos.coproc_link` is applied by the shim before the BEAM starts, because
the BEAM has no `CAP_NET_ADMIN`. `<if>` is a kernel interface name of 1-15
characters `[A-Za-z0-9_.-]`; `<ip>` is a canonical dotted quad. The BEAM only
reads it: `Elixos.Coproc` binds Erlang distribution to `<ip>` (ADR-098).

Live is a storage choice, not a third launch mode. Normal Live uses the
embedded service image; `elixos.safe` still selects rescue. With Live enabled,
`elixos.data` and `elixos.data_wait` never trigger a physical mount or wait.
The `--live` x86_64 EFI profile hard-locks this flag and its panel console;
firmware arguments cannot select another data device. The GUI remains opt-in
so IEx retains the local keyboard and framebuffer.

These kernel parameters apply only to machine builds. Native OCI uses the
explicit console/rescue environment switches in §3 and ordinary recovery
defaults; it does not inherit the host's kernel boot policy.

BEAM side (`Elixos.Boot.Cmdline`):

| parameter                  | default | meaning                                   |
|----------------------------|---------|-------------------------------------------|
| `elixos.commit_after=<s≥1>`| 30      | healthy seconds before auto-commit        |

Every parameter belongs to exactly one side, and the shim knows both tables
(ADR-023): it *validates* a BEAM-side parameter's syntax and never applies it,
while `invalid` counts only keys that neither side defines and values that are
malformed by the rule of the side that owns them. `elixos.commit_after=2` is
therefore silent; `elixos.commit_after=abc` and `elixos.nonsense=1` are
counted and logged.

Test hooks are honored only by shims built with `-Dtest-hooks=true` (ADR-018).
The current melange image recipe enables them; its initramfs is also embedded
by the UEFI builder. A hook-free deployment-image target remains unfinished.

| parameter                             | effect                                              |
|---------------------------------------|-----------------------------------------------------|
| `elixos.test.stop_before_launch[=1\|0]` | do everything up to the launch, log, power off    |
| `elixos.test.shim_panic_after=<s≥1>`  | panic the shim `<s>` seconds after launching ERTS   |

## §6 Console log contract

Machine builds write these lines to `/dev/console`; native OCI writes to
the runtime's stdout. Each has prefix `elixos-shim: `. Placeholders:
`<g>` generation, `<n>` number, `<m>` `normal|rescue`,
`<k>` `reboot|poweroff|halt`, `<E>` an errno or error name.

| line (after the prefix)                                                | when                                  | from |
|------------------------------------------------------------------------|---------------------------------------|------|
| `pid 1, version <version>`                                             | machine startup                       | M3   |
| `container supervisor pid=<n>, version <version>`                      | native OCI startup; actual supervisor PID | native OCI |
| `ignored <n> invalid elixos.* parameters`                              | n > 0                                 | M3   |
| `waiting for <device> up to <n>s`                                      | the data device is absent, so the shim waits | M13  |
| `cannot mount <device> (<E>), entering rescue`                         | data disk missing or unmountable      | M3   |
| `state file unreadable (<E>), entering rescue`                         | boot.state does not parse             | M3   |
| `fallback to last_good=<g> after <n> attempts of generation=<g>`       | planLaunch fell back                  | M3   |
| `plan generation=<g> mode=<m> attempt=<n>`                             | every plan, before persisting it      | M3   |
| `test hook <name>`                                                     | a test hook acts                      | M3   |
| `shutdown <k>`                                                         | before machine reboot(2) or native OCI exit | M3   |
| `launching generation=<g> mode=<m>`                                    | right before exec                     | M4   |
| `beam exited status=<n>`                                               | BEAM exited by itself                 | M5   |
| `beam killed by signal <n>`                                            | BEAM died from a signal               | M5   |
| `heartbeat timeout after <n>s, killing beam`                           | deadline passed                       | M5   |
| `commit generation=<g>`                                                | a COMMIT was applied                  | M5   |
| `next generation=<g>`                                                  | a NEXT was applied                    | M6   |
| `re-exec after panic: <message>`                                       | a panic re-execs /init                | M8   |
| `adopting beam pid=<n>`                                                | a re-exec adopts the running BEAM     | M8   |
| `ignored control line (<error>)`                                       | a control line was not a message      | M4   |
| `helper refused name=<name>`                                           | unknown helper or failed fork         | M17  |
| `helper list unavailable (<error>), no helpers`                         | allow-list could not be read          | M17  |
| `helper list invalid (<error>), no helpers`                             | entire allow-list was rejected        | M17  |
| `commit refused generation=<g> (<error>)`                              | sealing or reference verification failed | M17 |
| `cannot prepare unprivileged state (<error>), powering off`            | recovery boundary cannot be prepared  | M17  |
| `cannot drop BEAM privileges (<error>), exiting`                        | credential/capability drop failed     | M17  |
| `cannot drop helper privileges name=<name>, exiting`                   | helper identity could not be set      | M17  |
| `cannot exec helper name=<name>, exiting`                              | fixed helper executable failed        | M17  |
| `cannot format helper handoff, powering off`                           | panic handoff could not be prepared   | M17  |
| `cannot own crash directory (<error>)`                                 | writable dump directory could not be prepared | M17 |
| `system image unavailable (<error>), services disabled`                 | normal-mode image preparation failed  | M18  |
| `postgres directories unavailable (<error>), services disabled`        | safe database ownership preparation failed | M18 |
| `cannot unmount system image (<error>)`                                | a service mount could not be released | M18  |
| `helper shutdown timeout name=postgres, killing`                       | PostgreSQL exceeded its fast-shutdown grace | M18 |
| `coproc link <if> <ip>/<len>`                                          | `elixos.coproc_link` was applied      | M29  |
| `coproc link <if> failed (<E>)`                                        | the interface could not be configured; the boot goes on | M29 |

`attempt=<n>` is the plan's `next_state.attempts`. When planning from an
unreadable or unmountable state, the shim uses the defaults (`0/0/0`).

The BEAM's former `elixos-ask:` notice line is withdrawn with `Elixos.Ask`
(ADR-093). Oh-My-Jido approvals are the only human-in-the-loop mechanism; the
OS indexes them for every session (§10) and logs a `Logger` notice per new
request, which is not a byte-for-byte console contract.

## §7 The persistent disk

In persistent mode: ext4, label `ELIXOS`, mounted on `/priv`:

```
/priv/boot.state        §4, written only by the shim
/priv/crash/            ERTS crash dumps, `gen<g>-attempt<n>.dump`, newest five kept
/priv/store/            Elixos.Image.Store blobs: <2 hex>/<62 hex>
/priv/journal.log       Elixos.Image.Journal (record format in its moduledoc)
/priv/generations/      <n>.gen manifests (Elixos.Image.Generation)
/priv/.seal/            root-only temporary recovery publication
/priv/user.exs          Elixos.User settings (a keyword list literal)
/priv/home/             the user's home; .ssh/authorized_keys (M12)
/priv/ssh/              SSH host keys (M12)
/priv/cache/zig/        ZIG_GLOBAL_CACHE_DIR for on-box builds (M11)
/priv/cache/cargo/      CARGO_HOME for on-box Rust builds (M25, ADR-066)
/priv/toolchain/        unpacked elixos-toolchain APK: Zig, cc/c++, Rust and Cargo
/priv/apps/             installed apps (M11)
/priv/data/<app>/       stable application state; `persist` paths live beneath it
/priv/agents/           agent memory, `<id>.term` (M15, ADR-032)
/priv/llm.exs           LLM provider settings (a keyword list, M15)
/priv/hex/repos.exs     trusted Hex repositories (M14, ADR-019)
/priv/hex/keys/         each repo's public key, `<name>.pub`
/priv/hex/cache/        fetched registries and tarballs
/priv/system/system.squashfs  root-owned immutable service image, mode 0444 (M18)
/priv/postgres/data/    PostgreSQL cluster, uid/gid 70, mode 0700 (M18)
/priv/postgres/log/     uid/gid 70, mode 0755; logs are mode 0644 (M18)
/priv/postgres/log/initdb.log  a fresh cluster's initialization output (M20)
/priv/coproc/config.exs the coprocessor peer: `node:`, `port:`, `listen_port:` (M29)
/priv/coproc/cookie     the distribution cookie shared with it, mode 0600 (M29)
/priv/home/.erlang.cookie  OTP's own cookie, created when distribution starts (M29)
```

Live uses the same layout in RAM, with the service image and toolchain seeded
from packages (ADR-085). Saving a generation does not export it to USB:
all runtime changes, PostgreSQL data and generated keys disappear on a
kernel reboot or power loss. No physical volume is automatically mounted,
formatted or partitioned. Manual mounts and durable save/restore are not
implemented by this boot profile.

The system database itself is not on this list: it lives inside the cluster
above. The BEAM (uid 1000) reaches it over loopback as the `postgres` role,
trust-authenticated (ADR-053), and the scheduler's jobs are rows in the
`oban_jobs` table there (M19, ADR-057) - a job enqueued at the prompt and a
job still scheduled after a power cycle are the same row.

`/priv/crash` belongs to uid/gid 1000 so ERTS can create its dumps. PID 1
prepares it before each launch, including a relaunch after a crash. Ownership
does not follow symlinks, and retention opens the directory without following
one. It is writable state, not part of the sealed recovery store.

## §8 Trusted Hex repositories (M14)

Software comes from Hex repositories (ADR-019). `/priv/hex/repos.exs` is a
keyword list, one entry per repository, and **it is the whole trust decision**:
a repository is trusted exactly when it appears here, so an install can never
trust one implicitly.

```elixir
[
  elixos: [url: "https://repo.example/elixos", key: "-----BEGIN PUBLIC KEY-----\n..."],
  team: [url: "/priv/mirrors/team", key: "-----BEGIN PUBLIC KEY-----\n..."]
]
```

  * `url` is `http(s)://` or a local path (`/priv/mirrors/team`), so an offline
    mirror is a directory.
  * `key` is the repository's public key, PEM, RSA: the same bytes the repo
    serves as `public_key`, and what every resource it serves is verified
    against. The same key is written to `/priv/hex/keys/<name>.pub`.
  * A repository name and a package name may contain lowercase letters,
    digits, `_` and `-`; a package name belongs to exactly one trusted
    repository, and a clash is an error naming both.
  * `:elixos` is not a package: a dependency on it is satisfied by the running
    OS, and a package that bundles it is refused.

The factory ships the official repository preconfigured — its key in
`/factory/hex/keys/elixos.pub` and the entry

```elixir
[elixos: [url: "https://mattneel.github.io/elixos", key: "<the shipped key>"]]
```

in `/factory/hex/repos.exs`. Application initialization imports this preset
only when the writable trust file is absent. Reading/listing repositories
never imports it or modifies an empty custom trust store; an explicit `[]`
remains empty across boots. The file is the machine owner's (single user,
ADR-013), and it is the one configuration file Elixos reads by evaluating
it (`Code.eval_file/1`), because it holds PEM keys.

Reads and writes of `repos.exs` are atomic (temporary file, fsync, rename,
fsync of each directory), like every other file Elixos keeps.

## §9 Framebuffer GUI and console lease (M27)

The GUI is an optional view of `Elixos.Approvals` (§10), never its owner, and
never starts at boot. `Elixos.GUI.start/0` returns `{:error, :nothing_pending}`
without taking the screen or keyboard when no request is open. Escape or F12
hands the screen back, as does the last open request being resolved; Escape
never answers or denies. Answers go to `Elixos.Approvals.answer/2`.

`Elixos.GUI.status/0` returns `{:ok, pid}` only after the first frame has
been presented. `stop/0` stops rendering, releases input grabs and waits for
console handback; success is `:ok`. Rescue does not start a GUI.
`render_dialog/1` works without a display and returns
`{:ok, %{width: 640, height: 480, pixels: rgba_binary}}`.

### IO Port

`/usr/bin/elixos-gui-io` runs as uid 1000. Stdin and stdout use **packet-4**:
a four-byte big-endian unsigned payload length followed by that many bytes,
without a trailing newline. Helper-to-BEAM payloads are ASCII:

| Payload | Meaning |
|---|---|
| `READY <width> <height>` | Framebuffer validated and input devices acquired |
| `PRESENTED` | The complete supplied frame has been written to the framebuffer |
| `KEY <code> <value>` | Linux evdev keycode; value 0 release, 1 press, 2 repeat |
| `POINTER <x> <y>` | Pixel position, bounded to the visible framebuffer |
| `BUTTON <code> <value>` | Linux evdev button code and value |

BEAM-to-helper payloads are tightly packed RGBA8888, exactly
`width * height * 4` bytes. A zero-length payload requests shutdown.
Unsupported framebuffer formats, malformed packets and lost evdev input
fail the session rather than being silently accepted. The helper converts
RGBA into the framebuffer's validated true-color layout.

### Root-owned lease

The fixed allow-listed `console-handover` helper starts the broker or reuses
the existing one. `/run/elixos-console.sock` is root:1000, mode 0660; the
broker also checks `SO_PEERCRED` for uid 1000. There is one active lease.

The connected IO helper receives byte `R` only after fbcon has been
unbound. For a graceful release it sends byte `C`; the broker rebinds fbcon,
replies `C`, then closes the lease. EOF, unexpected data or an error also
releases the lease and triggers rebind before another lease is granted.
No peer supplies a path or a sysfs command. Broker SIGKILL cannot perform
cleanup; starting the broker again restores abandoned console bindings.

## §10 Oh-My-Jido approvals (ADR-093)

Oh-My-Jido sessions own every approval and question: their timeout, failure
and restart semantics are the library's (`question_timeout_ms`, fail closed,
no revival after restore). Sessions using `Elixos.Approvals.Host` register each
question with `Elixos.Approvals`; the OS's `Elixos.Coding` runtime uses that
host with a one-hour question timeout (`:approval_timeout_ms`).

`Elixos.Approvals.pending/0` lists open requests, oldest first:

```
id           pos_integer, OS-local, unique while the index runs
session_id   the Oh-My-Jido session; session is its %OhMyJido.SessionRef{}
question_id  Oh-My-Jido's id, passed to OhMyJido.answer/3
run_id       the run that asked, or nil
kind         :confirm (an effect approval) | :text | :choice | :multi
prompt       what is being asked, derived from the question
question     Oh-My-Jido's original (redacted) question map
options      [String.t()], labels of the offered choices (else [])
choices      the original option terms, in the same order
requested_at DateTime.t()
```

`approve/1` sends `true`; `deny/1` sends `:deny`, which Oh-My-Jido treats as a
denial. `answer/2` takes a boolean for `:confirm`, one label for `:choice`
(the original option term is sent), a non-empty list of distinct labels for
`:multi` and a non-empty binary for `:text`; anything else is
`{:error, :invalid_answer}` and the request stays open. An id that is no
longer open is `{:error, :unknown_request}`. `subscribe/0` returns the open
requests and then sends `{:elixos_approvals, requests}` on every change.
Login IEx sessions import `approvals/0`, `approve/1`, `deny/1` and
`answer/2`. Nothing in the OS answers a request on its own.

## §11 The inter-core ring (M31)

The two K230 cores share a reserved region (docs/notes/k230.md; on the host
and in tests, a file of the same size). It holds two single-producer,
single-consumer rings, one per direction, carrying IP packets: the link
between Elixos and the coprocessor is plain IP, and distribution is plain TCP
over it (ADR-098).

**Region.** Size `S`, a multiple of 4096. Ring **A** (big core writes, little
core reads) occupies `[0, S/2)`, ring **B** (little writes, big reads)
`[S/2, S)`. All integers are little-endian `u32`.

**Ring header** (64 bytes at the start of each half):

| Offset | Field | Written by |
|--------|-------|------------|
| 0 | magic `0x52584C45` ("ELXR") | initialiser |
| 4 | version `1` | initialiser |
| 8 | capacity: data bytes, the largest power of two not above `S/2 - 64` (at most 2^31) | initialiser |
| 12 | writer epoch | writer |
| 16 | head: bytes ever written, wrapping at 2^32 | writer |
| 20 | reader epoch | reader |
| 24 | tail: bytes ever consumed, wrapping at 2^32 | reader |
| 28 | dropped: frames the reader discarded as corrupt | reader |
| 32-63 | zero | - |

The data area follows the header; byte `p` of the stream lives at
`64 + (p mod capacity)`, so frames wrap around the end. `head - tail` (mod
2^32) is the bytes in flight and never exceeds the capacity. The capacity is a
power of two so that `p mod capacity` stays continuous when the counters wrap
at 2^32 (with any other capacity, unread bytes just before the wrap and new
bytes just after it would share slots). Bytes of a half beyond the data area
are unused; `S = 2 × capacity + 4096` leaves under 2 KiB per half. `spec/ring.vectors` holds
golden capacities, headers, frames and a wrap.

**Frame:** a 16-byte header `len, seq, crc, 0` followed by `len` payload
bytes, padded with zeros to a multiple of 8. `len` is 1-65535 and at most a
quarter of the capacity; `seq` counts the writer's frames from 0 per epoch;
`crc` is CRC-32 (IEEE, as zlib's `crc32`) over `len`, `seq` (8 little-endian
bytes) and the payload. A frame occupies `16 + align8(len)` bytes.

**Publishing.** The writer copies the whole frame, then (after a write fence)
advances `head`; the reader reads `head`, then (after a read fence) the frame,
and advances `tail` only when done with it. A writer with too little free
space does not write: the frame waits, or the caller is told the ring is full
(backpressure); nothing unread is ever overwritten.

**Corruption.** A frame whose `crc` does not match is dropped and counted in
`dropped`; the reader skips it by its `len`. A `len` outside 1-65535, or
larger than the bytes in flight, or fewer bytes in flight than a frame header,
or `head - tail` beyond the capacity, means the stream cannot be parsed: the
reader counts one drop and resynchronises by setting `tail = head`.

**Initialisation and restarts.** The big core initialises a ring whose magic,
version or capacity is wrong: zero header and data, then write capacity,
version and, last, magic. A side that (re)starts finds a valid ring and keeps
it: as a writer it bumps its epoch and continues at `head`; as a reader it
bumps its epoch and sets `tail = head`, discarding frames meant for its
previous incarnation. Frames written after a restart are therefore never
lost. The little core waits for a valid magic before using either ring.

**Signalling.** Polling: each side checks its incoming ring at least every
millisecond while idle. The K230 mailbox may replace polling later; the
layout does not change.

**The big-core helper.** `elixos-link` (static Zig, `shim/src/link.zig`)
bridges the region to a TUN device:

```
elixos-link --region <path> --size <S> [--offset <bytes>] --tun <ifname>
            [--side big|little] [--address <ip>/<len>]
```

It maps the region (a file, or a UIO device on the board), initialises the
rings if needed (`--side big`, the default), creates the TUN interface
(`IFF_TUN | IFF_NO_PI`), optionally assigns the address and brings it up, then
moves every packet read from TUN into its outgoing ring and every frame from
its incoming ring onto TUN. A full outgoing ring drops the packet (IP's own
retransmission handles it) and counts it, as it counts a packet longer than
the ring carries (`len` above a quarter of the capacity). `--side little`
swaps the rings and waits for the big side's initialisation, so two helpers
on one file form a complete link for tests. Its stderr lines:
`elixos-link: up <ifname> region <S> bytes` once ready, and
`elixos-link: stats tx <n> rx <n> full <n> dropped <n>` on SIGUSR1 and on exit
(SIGTERM or SIGINT, status 0): packets moved TUN → ring, frames moved
ring → TUN, packets dropped as above, and frames this incarnation discarded
as corrupt. `--offset` is page-aligned; a regular file must hold
`offset + S` bytes. Without `--address` the interface is created but left
down.
