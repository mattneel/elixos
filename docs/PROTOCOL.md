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

## §2 The control protocol (BEAM → shim)

**Transport.** Before exec'ing ERTS the shim creates a pipe. The BEAM gets
the write end as an inherited fd (number in `ELIXOS_CTL_FD`, see §3); the shim
keeps the read end. The BEAM opens it with
`File.open("/proc/self/fd/<n>", [:write, :raw, :binary])` (`Elixos.Shim.Sink.Fd`).
Traffic is one way. Writes are far below `PIPE_BUF`, so they are atomic.

**Framing.** ASCII lines terminated by `\n`. A line longer than 64 bytes
(excluding the newline) is `too_long`, whatever its content: the shim discards
up to the next newline and logs it. Anything else that is not exactly a
message below is `invalid`: logged and ignored, never fatal.

| line             | message            | effect in the shim (`recovery.applyMessage`)            |
|------------------|--------------------|---------------------------------------------------------|
| `HB`             | `:heartbeat`       | resets the heartbeat deadline; no state change          |
| `COMMIT <gen>`   | `{:commit, gen}`   | if `gen == current`: `last_good = gen`, `attempts = 0`; else ignored |
| `NEXT <gen>`     | `{:next, gen}`     | `current = gen`, `attempts = 0` (boots next time)       |
| `REBOOT`         | `:reboot`          | remembered; carried out when the BEAM exits             |
| `POWEROFF`       | `:poweroff`        | remembered; carried out when the BEAM exits             |
| `HALT`           | `:halt`            | remembered; carried out when the BEAM exits             |

Every state change is persisted to `boot.state` (§4) before the next line
is read. After requesting a shutdown, the BEAM stops itself
(`:init.stop/0`); the shim then reaps it and performs the shutdown.

**Golden vectors.** `spec/protocol.vectors` lists wire lines and their
meaning. Both `shim/src/protocol.zig` and `os/test/elixos/shim/protocol_test.exs`
run every line, and valid lines must round-trip through encode.

## §3 The launch contract (shim → ERTS)

The shim forks and execs `erlexec` from the generation's ERTS directly. No
shell script runs, ever (ADR-012); set what the release's `bin/` scripts would
have set (like Nerves' erlinit does): `ROOTDIR`, `BINDIR`, `EMU`, `PROGNAME`,
plus `HOME=/data/home`, `TERM=linux`, `LANG=C.UTF-8`, and:

| variable            | value                                                  |
|---------------------|--------------------------------------------------------|
| `ELIXOS_GENERATION` | generation being booted; `0` is the factory            |
| `ELIXOS_MODE`       | `normal` or `rescue`                                   |
| `ELIXOS_ATTEMPT`    | `next_state.attempts` of the plan that launched it     |
| `ELIXOS_CTL_FD`     | fd of the control pipe's write end (not CLOEXEC, ≥ 3)  |

- fds 0, 1, 2 are `/dev/console`. The working directory is `/` and stays
  there (ADR-016).
- The BEAM must send its first `HB` within `elixos.boot_grace` seconds and then
  at least every `elixos.hb_timeout` seconds; it sends one per second.
- When the BEAM exits, the shim logs `beam exited status=<n>` or
  `beam killed by signal <n>` (§6) and asks `recovery.onBeamExit` what next.

Parsed BEAM-side by `Elixos.Boot.Env.parse/1`.

## §4 `boot.state`

Path: `/data/boot.state`. Single writer: the shim (ADR-006). The BEAM may read
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

Writes are atomic: write `/data/boot.state.tmp`, fsync it, rename it over
`boot.state`, fsync `/data`.

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
| `elixos.data=/dev/<dev>`        | /dev/vda   | ext4 device mounted on `/data`                  |
| `elixos.data_wait=<s≥0>`        | 10         | seconds to wait for that device to appear        |

BEAM side (`Elixos.Boot.Cmdline`):

| parameter                  | default | meaning                                   |
|----------------------------|---------|-------------------------------------------|
| `elixos.commit_after=<s≥1>`| 30      | healthy seconds before auto-commit        |

Test hooks, honored only by shims built with `-Dtest-hooks=true` (QEMU test
images; never real hardware):

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
| `re-exec after panic: <message>`                                       | the new shim, after a panic           | M8   |
| `ignored control line (<error>)`                                       | a control line was not a message      | M4   |

`attempt=<n>` is the plan's `next_state.attempts`. When planning from an
unreadable or unmountable state, the shim uses the defaults (`0/0/0`).

## §7 The persistent disk

ext4, label `ELIXOS`, mounted on `/data`:

```
/data/boot.state        §4, written only by the shim
/data/store/            Elixos.Image.Store blobs: <2 hex>/<62 hex>
/data/journal.log       Elixos.Image.Journal (record format in its moduledoc)
/data/generations/      <n>.gen manifests (Elixos.Image.Generation)
/data/user.exs          Elixos.User settings (a keyword list literal)
/data/home/             the user's home; .ssh/authorized_keys (M12)
/data/ssh/              SSH host keys (M12)
/data/cache/zig/        ZIG_GLOBAL_CACHE_DIR for on-box builds (M11)
/data/apps/             installed apps (M11)
```
