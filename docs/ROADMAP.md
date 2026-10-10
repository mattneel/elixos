# Roadmap

Each milestone has a goal, the acceptance tests that define it (already in the
repo), notes on how to get there, and a done checklist. Work them in order;
`MILESTONE` holds the current one. The loop is in AGENTS.md.

Fast tests: `make test`. QEMU tests: `make test-qemu` (M3 onward).

---

## M0: Harness (done in the scaffold)

**Goal.** A green baseline: everything below exists as tests and is skipped.

**Acceptance.** `make test` passes with `MILESTONE=0`;
`os/test/meta_test.exs` enforces the test conventions.

**Already verified while building the scaffold.**
- `make kernel` builds 7.2.9 and all 45 fragment options survive.
- A throwaway probe `/init` booted under QEMU (TCG) to PID 1 in about two
  seconds, mounted the virtio ext4 disk and wrote to it; the QEMU and disk test
  helpers drove that boot end to end.
- The console helpers drove a real IEx on a pty: results, multi-line input,
  prompt redraws, Ctrl-G job control into erl and back to shared state.
- The NIF fixture builds with `zig cc` as `cc` and loads.
- Every pure Zig and Elixir test was run against a throwaway reference
  implementation (not shipped): 37/37 Zig, 159/159 ExUnit.

**Done when.** `make check-tools` is happy on your machine and `make test` is green.

- [x] Done (2026-10-09): `make check-tools` happy (flex/bison installed), `make test` green (2 passed, 190 excluded at M0).

---

## M1: The shim's pure core (Zig, host only)

**Goal.** The decisions PID 1 makes, as pure functions with exhaustive tests.

**Acceptance.** `make test-shim` with `MILESTONE=1`:
- `shim/src/decimal.zig`: canonical u32 (PROTOCOL.md §1)
- `shim/src/protocol.zig`: parse/encode, all of `spec/protocol.vectors`
- `shim/src/statefile.zig`: strict `boot.state` (PROTOCOL.md §4)
- `shim/src/cmdline.zig`: `elixos.*` parameters (PROTOCOL.md §5)
- `shim/src/recovery.zig`: the recovery policy (ARCHITECTURE.md §3.3)

**Notes.** No syscalls in these files. Use `decimal.parseU32` everywhere a
number is parsed. Saturating `+|` for attempts.

**Done when.** 36 tests that were skipped now pass; nothing else changed.

- [x] Done (2026-10-09): 37/37 Zig tests pass (the 36 gated M1 tests plus `refAllDecls`); `make ci` green; reviewer subagent found no hard-rule violations.

---

## M2: The BEAM's control plane (Elixir, host only)

**Goal.** The Elixir half of the shim contract, byte-compatible with M1.

**Acceptance.** `make test-os` with `MILESTONE=2`:
- `test/elixos/decimal_test.exs`
- `test/elixos/shim/protocol_test.exs` (the same golden vectors)
- `test/elixos/shim/control_test.exs` (heartbeats, requests, pause/resume)
- `test/elixos/boot/env_test.exs` (PROTOCOL.md §3)

**Notes.** `Elixos.Shim.Control` writes through a sink behaviour; tests use
`Elixos.Test.ProcessSink`. Validate generations in the caller.

- [x] Done (2026-10-09): `make ci` green; 76 ExUnit tests pass (71 shipped + 5 added). Reviewer subagent found two real defects (`ELIXOS_CTL_FD` accepted below 3; an expired heartbeat timer could start a second loop), both fixed with red-then-green regression tests.

---

## M3: First boot (QEMU, shim only)

**Goal.** The real PID 1: mounts, cmdline, `/priv`, `boot.state`, plan,
persist, log, and a clean power off, all without ERTS yet.

**Acceptance.** `make test-qemu` with `MILESTONE=3`:
`test/integration/m03_first_boot_test.exs`.

**Notes.**
- The initramfs has `/dev/console`, so fds 0-2 work before devtmpfs is
  mounted. Mount devtmpfs on `/dev` yourself; `CONFIG_DEVTMPFS_MOUNT` does not
  apply to an initramfs.
- Every log line follows PROTOCOL.md §6 exactly.
- Persist with temp file + fsync + rename + fsync of the directory.
- `elixos.test.stop_before_launch` (test-hook builds only): after persisting
  the plan, log `test hook stop_before_launch`, then shut down as `poweroff`.
- Until M4 there is no `/factory`: when it is missing, log that and power off.
  Never return from `main`.
- Debug interactively with `make qemu` (Ctrl-A X quits).

- [x] Done (2026-10-09): `make ci` green (37/37 Zig, 76 ExUnit, 6/6 QEMU M3 tests). Reviewer subagent found five defects in the first draft — a failed write still renamed over boot.state, states the policy calls "untouched" were persisted, `elixos.safe` skipped mounting/reading `/priv`, errno names printed `NOENT` instead of `ENOENT`, and an oversized device name could drop the required mount-failure line — all fixed, with the rescue and safe paths re-verified end to end on real boots.

- [x] Demo recorded: `demos/m03-first-boot.mp4` (`make demo M=3`).

---

## M4: Boot to IEx

**Goal.** The pitch: power on, get `iex(1)>`.

**Acceptance.** `test/integration/m04_boot_to_iex_test.exs`.

**Notes.**
- Write `scripts/build-factory.sh` (ADR-008): build OpenSSL and OTP 29.1.1
  for `x86_64-linux-musl` with `zig cc`, dynamically linked; Elixir 1.20.4 is
  pure BEAM. Produce `build/rootfs/factory/` (a `mix release` of `os/` with
  `include_erts` pointing at the cross-built ERTS works well) and
  `build/rootfs/lib/ld-musl-x86_64.so.1`. Cross-building OTP needs a host OTP
  of the same version for bootstrap; `.tool-versions` pins it.
- The shim execs `erlexec` directly with ROOTDIR/BINDIR/EMU/PROGNAME set (no
  release scripts, no sh) plus the PROTOCOL.md §3 contract.
- `Elixos.Application` starts `Elixos.Shim.Control` with `Elixos.Shim.Sink.Fd`
  when `Elixos.Boot.Env.current/0` is `{:ok, %Env{}}`, then the login IEx via
  `:shell.start_interactive/1`. `IEx.Server.run/1` is the entry point (Elixir
  1.20 has no public `IEx.start`).
- `Elixos.info/0`, `reboot/0`, `poweroff/0`, `halt/0`: send the request, then
  `:init.stop/0`. The shim performs the shutdown after reaping the VM.
- If the cross-build blocks you, ADR-008 allows a temporary stand-in; keep going.

- [x] Demo recorded: `demos/m04-boot-to-iex.mp4` (`make demo M=4`).

- [x] Done (2026-10-09): `make ci` green at MILESTONE=4 (37/37 Zig, 79 ExUnit,
  11 QEMU: the M3 and M4 files). The factory is built by
  `scripts/build-factory.sh` — musl cross gcc with pinned downloads
  (ADR-022, docs/notes/factory-build.md) — and the console lands at `iex(1)>`.

---

## M5: The shim supervises the BEAM

**Goal.** Crashes and hangs are survived, attempts are counted, healthy boots commit.

**Acceptance.** `test/elixos/boot/cmdline_test.exs`,
`test/elixos/boot/auto_commit_test.exs`,
`test/integration/m05_beam_supervision_test.exs`.

**Notes.** epoll + signalfd + timerfd in the shim; reap with `wait4(-1, WNOHANG)`
in a loop; relaunch with a short backoff. `Elixos.Boot.AutoCommit` runs only in
normal mode and commits once.

- [x] Demo recorded: `demos/m05-beam-supervision.mp4` (`make demo M=5`).

---

## M6: The live image

**Goal.** Code typed at the prompt survives power cycles once saved.

**Acceptance.** `test/elixos/image/{store,journal,generation,capture}_test.exs`,
`test/elixos/image_test.exs`, `test/integration/m06_live_image_test.exs`.

**Notes.**
- Capture: read `Elixos.Image.Capture`'s moduledoc first. Its findings were
  verified on Elixir 1.20.4 and save a lot of guessing.
- The login IEx gets the capture env (`IEx.Server.run(env: ...)`) and a
  process that records captured modules into the image.
- `Elixos.save/1`: `Image.save`, then `Control.next(n)`. At boot, restore the
  generation from `ELIXOS_GENERATION` before starting the REPL.
- The shim applies `NEXT` and logs `next generation=<g>`.

- [x] Demo recorded: `demos/m06-live-image.mp4` (`make demo M=6`).

---

## M7: Recovery

**Goal.** Bad generations fall back; nothing typed is ever lost; the base is sticky.

**Acceptance.** `test/elixos/image/{bisect,recover}_test.exs`,
`test/integration/m07_recovery_test.exs`.

**Notes.** A boot spec entry that raises must exit the VM non-zero. Rescue
mode loads no user code. Stick the factory's code directories with
`:code.stick_dir/1`. `Elixos.unsaved/1` and `Elixos.recover/1` sit on the
`Elixos.Image` functions.

- [x] Demo recorded: `demos/m07-recovery.mp4` (`make demo M=7`).

---

## M8: The shim survives its own panics

**Goal.** ADR-004, verified.

**Acceptance.** `test/integration/m08_shim_self_recovery_test.exs`.

**Notes.** `pub const panic = std.debug.FullPanic(handler)` in `main.zig`;
the handler re-execs `/init` with a pre-built argv carrying the BEAM pid and
control fd; the new shim adopts the running BEAM instead of launching one.
`elixos.test.shim_panic_after` triggers it.

- [x] Demo recorded: `demos/m08-shim-self-recovery.mp4` (`make demo M=8`).

---

## M9: REPLs are the login shells

**Goal.** IEx, erl (and gsh when installed) as login shells sharing one world.

**Acceptance.** `test/elixos/repl_test.exs`, `test/elixos/user_test.exs`,
`test/integration/m09_repl_login_test.exs`, `test/elixos/session_test.exs`,
`test/integration/m09_session_dir_test.exs`.

**Notes.** The console login reads `/priv/user.exs` (`Elixos.User`) and starts
`Elixos.REPL.mfa(repl)`. Parse the user file, never evaluate it.

**Session directories (ADR-020).** Each REPL session has its own working
directory, starting at `/priv/home`, keyed by the session's process-group
leader (which everything spawned from that REPL inherits). The login REPLs
replace `cd/1`, `pwd/0` and `ls/0,1` with session-aware versions: for IEx they
are the helpers imported into its evaluation environment, for erl they come
from `user_default`. Relative paths typed at a prompt resolve against the
session directory, native tools run with `cd:` set to it, and nothing changes
the VM's working directory (ADR-016).

- [x] Demo recorded: `demos/m09-repl-login.mp4` (`make demo M=9`).

---

## M10: Regular apps opt into Elixos

**Goal.** The `elixos:` key, `MIX_TARGET=elixos`, and system-wide resolution.

**Acceptance.** `test/elixos/package/{spec,resolver,mix_target}_test.exs`.

**Notes.** `Spec.read_project/1` must not change the VM's cwd (ADR-016); its
doc has a verified approach. Remember Elixir's `~> 0.1` means `< 1.0.0`.

---

## M11: Self-hosting

**Goal.** Build and install Mix projects, NIFs included, on the box.

**Acceptance.** `test/integration/m11_self_hosting_test.exs`.

**Notes.**
- The toolchain package (ADR-009): zig as `cc`/`c++`, make, BusyBox sh.
- `Elixos.Package.install/1` builds in a child ERTS exec'd directly with
  `MIX_TARGET=elixos`, satisfies `:elixos` from the running OS (never builds
  it), resolves with `Resolver.plan/3`, loads the result, starts the `services`,
  and records the modules in the image.
- Ship a CA bundle so Hex works; the acceptance test itself needs no network.

- [x] Demo recorded: `demos/m11-self-hosting.mp4` (`make demo M=11`).

---

## M12: SSH into your REPL

**Goal.** Public-key SSH lands in the user's REPL on the same VM.

**Acceptance.** `test/integration/m12_ssh_test.exs`.

**Notes.** OTP `ssh` daemon; the shell fun gets user and peer, returns
`Elixos.REPL.mfa(...)`'s shell pid. Keys in `/priv/home/.ssh/authorized_keys`,
host keys in `/priv/ssh/`. No passwords. Networking in QEMU uses kernel
`ip=dhcp` until Elixos has its own DHCP client.

- [ ] Demo recorded: `demos/m12-ssh.mp4` (`make demo M=12`).

---

## M13: Real hardware

**Goal.** Boot the cyberdeck: UEFI → EFI stub → shim → IEx on the panel.

**Acceptance.** `test/integration/m13_uefi_boot_test.exs` (OVMF), then the
manual checklist below on the real machine.

**Notes.** `scripts/build-uefi-image.sh`: a second kernel config with the
initramfs and cmdline built in (configuration, not a patch), packed into a FAT
ESP as `EFI/BOOT/BOOTX64.EFI` with mtools. The hardware variant uses
`console=tty0 fbcon=font:TER16x32`.

**Notes on hardware the tests cannot cover.** The kernel runs `/init` without
waiting for USB or SD storage, so the shim waits up to `elixos.data_wait`
seconds for the data device to appear (it logs `waiting for <device> up to
<n>s` first); QEMU virtual disks are ready immediately, so no test exercises
that path.

**Manual checklist (human).**
- [ ] Boots from USB with Secure Boot off (or with your own enrolled keys).
- [ ] IEx on the built-in panel in a readable Terminus font.
- [ ] The internal disk works as `/priv` (`elixos.data=/dev/nvme0n1p2` or similar).
- [ ] Keyboard, including Ctrl-G job control.
- [ ] `Elixos.poweroff()` really powers the machine off.

- [ ] Demo recorded: `demos/m13-uefi.mp4` (`make demo M=13`).

---

## M14: Packages by name

**Goal.** Hex is the package manager (ADR-019): trusted repositories, install
by name, and commands are functions rather than CLIs.

**Acceptance.** `test/elixos/package/repo_test.exs`,
`test/elixos/package/install_by_name_test.exs`,
`test/integration/m14_packages_test.exs`, and, for the toolchain half,
`test/integration/m11_toolchain_test.exs`.

**Notes.**
- Repo configuration and trusted keys live under `/priv/hex/` (PROTOCOL.md §7).
  A repo is added with its public key or a verified fingerprint, and an install
  never trusts a repository implicitly: adding it is the consent step.
- `Elixos.Package.install/1` by name: find the package among the trusted repos
  (a name in two repos is an error naming both), fetch and unpack its tarball,
  then hand the directory to the M11 path. `install/1` with a path keeps its
  M11 meaning.
- The apt verbs are functions on `Elixos.Package`: `add_repo/3`, `remove_repo/1`,
  `repos/0`, `search/1`, `info/1`, `upgrade/0,1`, `remove/1`. A static repo has
  no search API, so `search/1` matches against the registry's names index.
- `:elixos` is always satisfied by the running OS and is never fetched; a
  package that bundles it is refused (M10).
- `os/test/fixtures/hex_repo/` is a real static Hex repo (built with
  `mix hex.registry build`, see its README): the tests add it with its public
  key and install `hello_pkg` from it. The official `elixos` repository is a
  static repo on GitHub Pages, built and published by
  `.github/workflows/hex-repo.yml` from `hex/packages/`; the factory ships its
  public key (`hex/keys/elixos.pub`) and presets the entry in `/factory/hex/`.
- Native tools are exec'd directly with `cd:` set to the caller's session
  directory — never through a shell (ADR-012), never by changing the VM's cwd
  (ADR-016). The M11 toolchain package's first instance is `Zig.init/1` and
  `Zig.build/2`.

**Done when.** `make ci` is green with `MILESTONE=14`, both QEMU files pass, and
the repo/install unit tests cover trust (a repo without a trusted key is
refused), the one-name-per-repo clash, and an install by name from the fixture
repo.

- [ ] Demo recorded: `demos/m14-packages.mp4` (`make demo M=14`).

---

## M15: Built-in AI agents (Jido)

**Goal.** Agents are ordinary Elixos code: define one at a prompt, save it,
and it is there after the next boot, holding its state and answering commands.
The LLM is a provider, not the definition — an agent without one still works.

**Acceptance (to be written).** `test/elixos/agent*_test.exs` and one QEMU
test: a Jido agent defined at the prompt, `Elixos.save()`, power cycle; the
next boot has it supervised and answering a command, and an agent whose action
calls an LLM talks to a stubbed provider over the loopback.

**Notes.** Jido is the framework: `jido` (agents, directives, runtime),
`jido_action` (validated actions), `jido_signal`, and `jido_ai` + `req_llm`
for providers. They arrive as packages (M14/ADR-019), so this milestone is
almost entirely wiring and conventions: an agent's module is a user module
(the M6 image already journals and restores those), its supervision is a tree
built at boot (the answer to Q2), and its memory belongs on `/priv` with the
rest of the machine's state. `~/src/jido-skills` on the development host
(`jido-core`, `jido-agent`, `jido-action`, `jido-ai`, `jido-testing`) is the
authority for the API and its conventions; see docs/notes/jido.md.

- [ ] Demo recorded: `demos/m15-jido-agents.mp4` (`make demo M=15`).

---

## Later (not yet scheduled)

Wi-Fi (Q3), a DHCP client in Elixir, power-button handling from input events,
kernel/factory upgrades on hardware (Q5), process-state persistence (Q2),
gsh packaging (Q6), CRIU as a stretch goal, aarch64.
