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
in `ELIXOS_REPLY_FD` (§3). PID 1 keeps the opposite ends; they survive its
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
mounted system image. One live child per name is reused; exited children are
reaped. `OK` acknowledges a fork, not successful exec or SQL readiness.
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
`PATH=/priv/toolchain:/bin:/usr/bin` when the persistent disk is mounted
(`/bin:/usr/bin` otherwise), and:

| variable            | value                                                  |
|---------------------|--------------------------------------------------------|
| `ELIXOS_GENERATION` | generation being booted; `0` is the factory            |
| `ELIXOS_MODE`       | `normal` or `rescue`                                   |
| `ELIXOS_ATTEMPT`    | `next_state.attempts` of the plan that launched it     |
| `ELIXOS_CTL_FD`     | fd of the control pipe's write end (not CLOEXEC, ≥ 3)  |
| `ELIXOS_REPLY_FD`   | fd of the helper reply pipe's read end (not CLOEXEC, ≥ 3) |

- fds 0, 1, 2 are `/dev/console`. The working directory is `/` and stays
  there (ADR-016). When the persistent disk is mounted, the shim also sets
  `ERL_CRASH_DUMP` to `/priv/crash/gen<g>-attempt<n>.dump` (§7, ADR-025) and
  `ERL_CRASH_DUMP_BYTES` to 1 MiB, so a crash leaves its evidence on the disk
  the next boot mounts. Without the disk both are left unset and ERTS keeps
  its default.
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

Shim side (`shim/src/cmdline.zig`); the last occurrence of a key wins, and
malformed or unknown `elixos.*` tokens are counted and logged, never applied:

| parameter                       | default    | meaning                                         |
|---------------------------------|------------|-------------------------------------------------|
| `elixos.safe[=1\|0]`            | off        | boot the factory in rescue mode                 |
| `elixos.generation=<gen>`       | none       | boot `<gen>` once, outside attempt accounting   |
| `elixos.max_attempts=<n≥1>`     | 3          | launches before falling back                    |
| `elixos.hb_timeout=<s≥1>`       | 10         | seconds without `HB` before killing the BEAM    |
| `elixos.boot_grace=<s≥1>`       | 120        | seconds allowed before the first `HB`           |
| `elixos.data=/dev/<dev>`        | /dev/vda   | ext4 device mounted on `/priv`                  |
| `elixos.data_wait=<s≥0>`        | 10         | seconds to wait for that device to appear        |

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

The shim writes these lines to `/dev/console`, each prefixed `elixos-shim: `.
Placeholders: `<g>` generation, `<n>` number, `<m>` `normal|rescue`,
`<k>` `reboot|poweroff|halt`, `<E>` an errno or error name like `ENOENT`.

| line (after the prefix)                                                | when                                  | from |
|------------------------------------------------------------------------|---------------------------------------|------|
| `pid 1, version <version>`                                             | first thing                           | M3   |
| `ignored <n> invalid elixos.* parameters`                              | n > 0                                 | M3   |
| `waiting for <device> up to <n>s`                                      | the data device is absent, so the shim waits | M13  |
| `cannot mount <device> (<E>), entering rescue`                         | data disk missing or unmountable      | M3   |
| `state file unreadable (<E>), entering rescue`                         | boot.state does not parse             | M3   |
| `fallback to last_good=<g> after <n> attempts of generation=<g>`       | planLaunch fell back                  | M3   |
| `plan generation=<g> mode=<m> attempt=<n>`                             | every plan, before persisting it      | M3   |
| `test hook <name>`                                                     | a test hook acts                      | M3   |
| `shutdown <k>`                                                         | right before reboot(2)                | M3   |
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

`attempt=<n>` is the plan's `next_state.attempts`. When planning from an
unreadable or unmountable state, the shim uses the defaults (`0/0/0`).

The BEAM prints one further console line, prefixed `elixos-ask: ` (M20), when
a question is added to `Elixos.Ask`: the console REPL is the first front-end
of the question queue (docs/ARCHITECTURE.md §6, ADR-059), so a human watching
the console sees the question the moment it exists - an agent's question
included.

| line (after the prefix)                       | when                       | from |
|-----------------------------------------------|----------------------------|------|
| `question <id> (<kind>): <prompt>`            | a question enters the queue | M20 |

`<id>` is the queue's own id (a positive integer), `<kind>` is one of `text`,
`choice`, `multi`, `confirm`, and `<prompt>` is the question's text, verbatim.
The line is API: the M20 acceptance matches it, so it changes like any other
console line. Questions do not survive the session that asked them.

What a front-end renders is the question itself (`Elixos.Ask.pending/0`)
under these fields, and what `Elixos.Ask.answer/2` accepts is checked against
them:

```
id           pos_integer, unique while it is open (oldest first in pending/0)
kind         :text | :choice | :multi | :confirm
prompt       the question, verbatim
options      [String.t()], the choices a choice or multi offers (else [])
allow_other  boolean, whether free text is accepted beside those options
default      term, a suggestion a front-end may pre-fill (optional)
timeout      pos_integer milliseconds or nil; expiry resolves {:error, :timeout}
asker        pid, the process blocked on the answer
asked_at     DateTime.t()
```

`:text` takes any binary; `:confirm` a boolean; `:choice` one of `options`, or
any binary when `allow_other` is true; `:multi` a non-empty list of `options`.
Anything else is `{:error, :invalid_answer}`, and the question stays open.
Resolving a question the queue does not hold is `{:error, :unknown_question}`.

## §7 The persistent disk

ext4, label `ELIXOS`, mounted on `/priv`:

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
/priv/agents/           agent memory, `<id>.term` (M15, ADR-032)
/priv/llm.exs           LLM provider settings (a keyword list, M15)
/priv/hex/repos.exs     trusted Hex repositories (M14, ADR-019)
/priv/hex/keys/         each repo's public key, `<name>.pub`
/priv/hex/cache/        fetched registries and tarballs
/priv/system/system.squashfs  root-owned immutable service image, mode 0444 (M18)
/priv/postgres/data/    PostgreSQL cluster, uid/gid 70, mode 0700 (M18)
/priv/postgres/log/     uid/gid 70, mode 0755; logs are mode 0644 (M18)
/priv/postgres/log/initdb.log  a fresh cluster's initialization output (M20)
```

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

in `/factory/hex/repos.exs` — so it is trusted without any consent step; the
box's `/priv/hex/repos.exs` wins once it exists. The file is the machine
owner's (single user, ADR-013), and it is the one configuration file Elixos
reads by evaluating it (`Code.eval_file/1`), because it holds PEM keys.

Reads and writes of `repos.exs` are atomic (temporary file, fsync, rename,
fsync of each directory), like every other file Elixos keeps.
