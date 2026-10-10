# Ctrl+C on the Elixos console

What the M5 Ctrl+C test exercises, why the obvious wrapper fails, and why the
test types `^C` followed by Enter. Traced against OTP 29.1.1's sources;
reproduced with stock `iex --erl "+Bc"` on a pty.

## The path a ^C takes

1. `+Bc` clears the tty's `VINTR` (erts/emulator/sys/unix/sys.c,
   `erts_replace_intr`): ^C is not a signal and the byte reaches the program.
2. The console tty is **cooked** — user_drv's default for `-noshell` — so the
   kernel line-edits: a lone ^C waits in its buffer until a newline arrives.
3. `user_drv` classifies each read (`contains_ctrl_g_or_ctrl_c`). A chunk
   that contains Ctrl+C with more bytes after it is `ctrl_c`: it runs
   `exit(CurrentGroup, interrupt)` and **discards the rest of that chunk**. A
   lone Ctrl+C byte is `none` and is forwarded as ordinary input.
4. The console's group (kernel/src/group.erl) traps exits and forwards the
   break to the shell pid it was given: `exit(Shell, interrupt)`.
5. `IEx.Server` traps exits, so it takes `{:EXIT, group, :interrupt}` itself,
   exactly as under `iex`: prints `** (EXIT) interrupted`, kills its
   evaluator, and starts a fresh one — banner, prompt, same input path.

## `Login.start_iex/1` stays out of the way

```elixir
spawn_link(fn -> IEx.Server.run(iex_options(boot, image)) end)
```

No restart loop: IEx already implements the break, and a wrapper that
restarts the whole session opens a window in which input typed during the
restart is lost. The loop was tried, measured, and removed.

## Raw input is not the answer

`input: :raw` (via `user_drv:start_shell/1`) was tried in the guest and makes
Ctrl+C *stop* interrupting: a lone ^C byte is `none`, so nothing happens.
Cooked plus `\x03\r` — Ctrl+C then Enter, what a keyboard sends — is the
reference behaviour (ADR-024), and is what the M5 test sends before it waits
for `** (EXIT) interrupted`.

## Verified

- `erl +Bc` on a pty (raw): a lone ^C interrupts, the prompt returns, the same
  shell keeps running. `erl` arranges something else here than IEx does.
- `iex --erl "+Bc"` on a pty (cooked): `^C` → `** (EXIT) interrupted` + a
  fresh `iex(1)>`; a later line evaluates. ^C and a line in one write lose the
  line.
- The M5 QEMU test: `^C` + Enter during `Process.sleep(:infinity)`, then
  `40 + 2` evaluates (`42`) in the restarted session.
