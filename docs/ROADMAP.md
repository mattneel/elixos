# Roadmap

Each milestone has a goal, the acceptance tests that define it (already in the
repo), notes on how to get there, and a done checklist. Work them in order;
`MILESTONE` holds the current one. The loop is in AGENTS.md.

Fast tests: `make test`. Focused agent-arc iteration: `make check M=21`.
Full QEMU suite: `make test-qemu` (M3 onward); milestone gate: `make ci`.
The ARM64 smoke test is separate: `make test-qemu-aarch64`.

**Current state:** M1–M20, M25 and M26 are delivered. M21–M24 have resumed
against a fresh upstream OMP inventory (ADR-071), without a `clanklet`
prerequisite. `MILESTONE=21` selects that resumed arc. The in-progress M27
GUI's host and x86_64 QEMU suites passed before this gate selection;
ARM64 packaging remains in progress.

---

## M0: Harness (done in the scaffold)

**Goal.** A green baseline: everything below exists as tests and is skipped.

**Acceptance.** `make test` passes with `MILESTONE=0`;
`os/test/meta_test.exs` enforces the test conventions.

**Already verified while building the scaffold.**
- At scaffold time, `make kernel` built 7.2.9 and all 45 fragment options
  survived. M16 replaced that target with the melange kernel packages.
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

- [x] Demo recorded: `demos/m12-ssh.mp4` (`make demo M=12`).

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

- [x] Demo recorded: `demos/m13-uefi.mp4` (`make demo M=13`).

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

- [x] Demo recorded: `demos/m14-packages.mp4` (`make demo M=14`).

---

## M15: Built-in AI agents (Jido)

**Goal.** Agents are ordinary Elixos code: define one at a prompt, save it,
and it is there after the next boot, holding its state and answering commands.
The LLM is a provider, not the definition — an agent without one still works.

**Acceptance.** `test/elixos/agents_test.exs`,
`test/elixos/agents_llm_test.exs`, `test/elixos/package/install_closure_test.exs`
and `test/integration/m15_jido_agents_test.exs`: a Jido agent defined at the
prompt, `Elixos.save()`, power cycle; the next boot has it supervised and
answering a command, and an agent whose action calls an LLM talks to a stubbed
provider over the loopback.

**Notes.** Jido is the framework: `jido` (agents, directives, runtime),
`jido_action` (validated actions), `jido_signal`, and `jido_ai` + `req_llm`
for providers. It is a dependency of Elixos itself (ADR-036): the factory ships
it, nothing installs it at run time, and `mnesia` - jido_signal's OTP
dependency - comes from the same cross-built OTP as the rest of the release.
So this milestone is almost entirely wiring and conventions: an agent's module
is a user module (the M6 image already journals and restores those), its
supervision is a tree built at boot (the answer to Q2), and its memory belongs
on `/priv` with the rest of the machine's state. `~/src/jido-skills` on the
development host (`jido-core`, `jido-agent`, `jido-action`, `jido-ai`,
`jido-testing`) is the authority for the API and its conventions; see
docs/notes/jido.md.

- [x] Demo recorded: `demos/m15-jido-agents.mp4` (`make demo M=15`).

---

## M16: The image build is Alpine packages (melange + apko)

**Goal.** The image stops being hand-built. Our own APKs - the kernel from the
kernel.org tarball plus our fragments, OTP 29.1.1, Elixir 1.20.4, the shim
(`build.zig`, still ReleaseSafe), the factory release and the on-box toolchain
- are built by melange from pinned sources; everything else comes from a
pinned Alpine release, locked in a lockfile with checksums and served from a
local mirror; apko assembles the root filesystem. The result is the image the
QEMU tests already boot, for **x86_64 and aarch64**, reproducible from the
lockfile, each with an SBOM. ADR-041: the old cross-build and the musl.cc
download are gone, no dual pipeline, and the make targets keep their names.

**Acceptance.**
- x86_64: `make ci` green with every QEMU test through M15, on the image the
  new pipeline builds.
- aarch64: `make test-qemu-aarch64` (qemu-system-aarch64, `virt`): boot to
  `iex(1)>`, `Elixos.info` reports the architecture, save a module, reboot,
  the module is still there, poweroff - the smoke set only; TCG is slow.
- Reproducible: `make reproducible` builds the rootfs twice from the same
  lockfile and compares the digests.
- The SBOM next to each image lists at least the kernel, OTP and Elixir
  versions; `make image` runs that check.
- The kernel config is per architecture: `kernel/elixos.config` (common) plus
  `kernel/config.x86_64` and `kernel/config.aarch64`, each applied over its
  defconfig and guarded by `scripts/check-kernel-config.sh`.

**Notes.** melange's default runner needs bubblewrap, and aarch64 packages
built on an x86_64 host run under QEMU user emulation through binfmt_misc;
`make check-tools` reports both, plus `qemu-system-aarch64` and the pinned
melange/apko. The dev signing key for APKs stays out of git (gitignored); a
release key is a later decision. Sources and versions are pins like the
kernel's (ADR-001): `melange/` carries the package definitions, the lockfile
and the local mirror carry everything else, and nothing is fetched at run time
on the box. apko runs no package install scripts, so users an image needs
(M18's postgres) are declared in the image config. Alpine edge is allowed
package by package, each with a note in DECISIONS.md. Emerge ships no aarch64
musl NIF (only aarch64 GNU), so M27 needs a source build for aarch64. Out of
scope here: OCI/container runtime mode, which gets a separate write-up from
the human.

**Image size.** Before (hand-built, x86_64): initramfs 44M, unpacked rootfs
108M (factory 82M, libs 27M), kernel 14.3MiB. Measured package-built artifacts:

| architecture | initramfs (`.cpio.gz`) | apko archive (`rootfs.tar`) | kernel artifact |
|--------------|-----------------------|-----------------------------|-----------------|
| x86_64 | 92.0 MiB | 114.0 MiB | 14.5 MiB |
| aarch64 | 90.7 MiB | 94.5 MiB | 40.1 MiB |

MiB is 1,048,576 bytes. The apko archive is an OCI-format build intermediate,
not the old unpacked rootfs measurement. The x86_64 kernel is a compressed
`bzImage`; aarch64's `Image` is uncompressed. The initramfs carries Alpine's
base, the kernel, a full OTP install and the factory release; excluding ERTS
from the release removed 18M of duplication.

**Done when.** `make ci` is green with `MILESTONE=16` on the new x86_64
image, `make test-qemu-aarch64` passes its smoke set, `make reproducible`
prints one digest twice, the SBOM check passes, and `make audit` is still 0.

- [x] Demo recorded: `demos/m16-aarch64.mp4` (`make demo M=16`, driving
  qemu-system-aarch64).

---

## M17: The escape hatch: an unprivileged BEAM and sealed commits

**Goal.** The shim becomes the trusted base and the BEAM a tenant. erlexec
runs as a dedicated `elixos` uid with only the capabilities it needs;
`boot.state`, every committed generation and the store blobs it references
belong to root and are read-only. Code running in the BEAM - an agent included
- can write candidates but can never alter `last_good` or the factory. What
needs root moves behind the shim: a small allow-list of privileged helpers that
the image declares and the BEAM can only ask for by name. This is what makes
the milestones after it safe: an agent that can change Elixos's own code still
cannot take away the way back.

**Acceptance.** `test/integration/m17_escape_hatch_test.exs`:
- the BEAM's uid is not 0, and its effective capabilities are exactly the ones
  PROTOCOL.md §3 lists;
- writing `/priv/boot.state`, or a committed generation's manifest, from IEx
  fails with `{:error, :eacces}`;
- candidates still work end to end: a module saved at the prompt goes through
  NEXT and COMMIT and is there after a power cycle;
- a broken candidate still falls back to `last_good`;
- an unknown helper name is refused - `{:error, :refused}` at the prompt - and
  logged on the console (`elixos-shim: helper refused name=<name>`).

Plus `test/elixos/privileges_test.exs` on the host (helper names are validated
before anything reaches the pipe; the request and reply lines encode and parse
as PROTOCOL.md §2 will say) and the shim's own Zig tests for the allow-list and
the reply lines (`shim/src/helpers.zig`, gated at 17).

**Notes.**
- *The uid.* `elixos` (uid and gid 1000, home `/priv/home`) is declared in the
  apko config with its supplementary groups (`video`, `input`): apko runs no
  install scripts (ADR-041), so accounts are configuration. The shim forks,
  drops to it - setgroups, setgid, setuid, in that order - keeps only the
  ambient capabilities PROTOCOL.md §3 will name (`CAP_NET_BIND_SERVICE`, for
  M12's SSH on port 22; nothing else is known to be needed), sets
  `PR_SET_NO_NEW_PRIVS`, and execs erlexec directly, as today. Anything that
  turns out to need more becomes a helper, never a capability.
- *What the BEAM may write.* The journal, new store blobs, candidate manifests,
  `/priv/home`, `/priv/apps` and `/priv/cache` remain writable. Root owns
  `/priv`, `/priv/generations`, `/priv/store` and its fan-out directories;
  writable shared parents are mode 1777. The shim prepares the fan-out
  directories before dropping uid. Sticky directories owned by the BEAM would
  not protect root-owned children: a directory owner may unlink them.
  `boot.state` is root's, mode 0644: only the control pipe changes it.
  On COMMIT the manifest and every referenced blob become root-owned, mode
  0444; the BEAM cannot write, unlink, rename or replace them. The factory and
  helper allow-list are root-owned in the initramfs, never user-writable.
  chmod/chown do not revoke already-open writable descriptors. New candidate
  inodes therefore become fresh, verified root-owned copies before publishing
  their sealed paths and updating `last_good` (or are sealed before the BEAM
  can open them). Hash the copied bytes before publication; a retained old
  descriptor must never change the committed manifest or blob.
- *Restore verifies.* A blob's name is its hash; restore checks every blob it
  reads against its name before loading anything, so a blob swapped underneath
  - by a bug, a disk, or anything that got past the sealing - stops the restore,
  and the boot falls back like any other broken one.
- *Helpers.* The image declares the allow-list in `/etc/elixos/helpers` (root's,
  read-only, in the initramfs): one helper per line - a name, the uid and gid it
  runs as, an absolute path and its arguments - exec'd directly by the shim,
  never through a shell (ADR-012, ADR-041). The BEAM asks with a control line,
  `HELPER <name>` (names are `[a-z0-9-]{1,32}`, so the line fits the 64-byte
  limit); the answer comes back on a second pipe, shim to BEAM, whose fd is in
  the launch contract (`ELIXOS_REPLY_FD`, PROTOCOL.md §3): `HELPER <name> OK
  <pid>` or `HELPER <name> REFUSED`, a refusal also logged on the console. The
  shim reads the list once, at startup, so the BEAM cannot add to it. Helpers
  are the shim's children: it reaps them, and on poweroff, halt or reboot it
  stops them - SIGTERM, a grace period, SIGKILL - after the BEAM has stopped.
  The first entries are M18's Postgres (`initdb` and the server) and M27's
  console handover; access that only needs a group (`video`, `input`) uses the
  group, never the list.
- *The shim stays small.* No allocation after startup (ADR-003): the list is
  parsed into fixed storage at boot; one that does not fit is a boot error on
  the console, and the BEAM then gets no helpers rather than some.
- *What does not change.* The shim still owns `boot.state` and the generation
  plan (M3-M8), and rescue still boots the factory. `Elixos.save/0`, NEXT and
  COMMIT keep their meaning, so M6's and M7's tests keep passing.
- PROTOCOL.md §2 (the HELPER request and its reply lines), §3 (the uid, the
  capabilities, `ELIXOS_REPLY_FD`) and §6 (the refusal line) are written when
  this starts, and `spec/protocol.vectors` grows the HELPER vectors in that
  same commit: both suites read them, so they cannot land before the code.

**Done when.** `make ci` is green with `MILESTONE=17`, both test files and the
Zig tests pass, PROTOCOL.md §2, §3 and §6 carry the new lines, and ADR-046
holds.

- [x] Demo recorded: `demos/m17-escape-hatch.mp4` (`make demo M=17`): the VM's
  uid, a refused write to `boot.state`, a refused helper, and a save that still
  commits.

---

## M18: The system database (Postgres)

**Goal.** A real PostgreSQL runs on Elixos as a system service: reachable from
the prompt, its data on the persistent disk, and a power-off is a *clean*
shutdown, not crash recovery. The heavy services stop living in the factory:
they move to a read-only system image on `/priv`, mounted and started only in
normal mode.

**Acceptance.** `test/integration/m18_postgres_test.exs`: Postgres answers a
query from the prompt; it runs as its own uid, never root; `/etc/passwd` has
that uid and the data directory is owned by it, mode 0700; pgvector and
TimescaleDB's Apache-only build load and answer; the binaries come from the
read-only `/system` mount; `elixos.safe` starts none of it; and the boot after
a power cycle logs a clean shutdown (`database system was shut down at`), not
recovery.

**Notes.** Postgres refuses to run as root, and ADR-013's single user is one
*person*, not one uid. The uid switch comes from M17's helper allow-list
(ADR-046), not from a helper the BEAM execs: the image declares `initdb` and
the server as privileged helpers that the shim runs as the `postgres` uid, and
the BEAM asks for them by name over the control protocol and cannot add to the
list. `initdb` looks its own uid up with
`getpwuid` and refuses to run without a passwd entry, so `/etc/passwd` and
`/etc/group` carry `postgres` (a few bytes, built into the initramfs), and the
data directory is owned by that uid, mode 0700. `CONFIG_SYSVIPC=y` is named in
`kernel/elixos.config` - `x86_64_defconfig` enables it, but the fragment names
it so `check-kernel-config.sh` guards it: Postgres always creates a small
System V shared-memory segment as a lock, and its dynamic shared memory wants
`/dev/shm`, which the shim mounts as a tmpfs (mode 1777) beside `/run` and
`/tmp`. Postgres comes from Alpine's packages through the M16 pipeline
(`postgresql17`; pgvector and Apache-only TimescaleDB from the tagged PG17
package set in ADR-052): pinned in the system lockfile and assembled by apko,
never a second cross-build. The service binaries and their library closure
live in a gzip SquashFS on `/priv`, mounted read-only at `/system` in normal
mode only (ADR-052). Licensing: pgvector is
PostgreSQL-licensed; TimescaleDB's Apache-only build gives hypertables and
`time_bucket` without a question. TimescaleDB is a *preload library*: the
cluster's `shared_preload_libraries` must name `timescaledb` before the
postmaster starts, or `CREATE EXTENSION timescaledb` fails ("could not access
file \"timescaledb\"") - the acceptance does exactly that `CREATE EXTENSION`,
so the setting is part of this milestone, not tuning. Compression and
continuous aggregates are under the Timescale License and get their own ADR -
read the license before publishing images. `Elixos.Postgres` asks the shim for
the server once the prompt's machinery is up and *not* in rescue; a failure is
logged and the prompt still comes up. The server is the shim's child, so the
shim stops it on `Elixos.poweroff` and `halt` - SIGINT, Postgres's `fast`
shutdown - after the BEAM has stopped and before the power goes: every
power-off is clean, and Oban's Repo (M19) keeps its database to the end.
Generations vs migrations: a generation may only ship migrations the
*previous* generation can ignore; drops and renames run after the commit.
ADRs to write when this starts: the system image, the Postgres entries on the
helper allow-list with their shutdown order, and the disk layout PROTOCOL.md §7
gains - the cluster at `/priv/postgres/data`, the postmaster log at
`/priv/postgres/log/`.

**Done when.** `make ci` is green with `MILESTONE=18`, the QEMU test passes,
the ADRs above are written (system image; the Postgres helpers and their
shutdown order), and PROTOCOL.md §7 carries the layout the ADR decides.

- [x] Done (2026-10-11): `os/test/integration/m18_postgres_test.exs` passes
  (1/1): PostgreSQL 17 runs as uid/gid 70 from the read-only `/system` squashfs
  on `/priv`, owned 0700, with pgvector and Apache-only TimescaleDB, and logs a
  clean shutdown across a power cycle (ADR-052, ADR-053).

- [x] Demo recorded: `demos/m18-postgres.mp4` (`make demo M=18`).

---

## M19: Jobs that survive reboots (Oban)

**Goal.** Oban is Elixos's scheduler: a job enqueued at the prompt runs, a
failed one is retried, and a machine that powers off mid-queue still has the
job next boot. Apps declare their queues and cron the way they declare
services.

**Acceptance.** `test/elixos/oban_test.exs` (the `elixos:` key gains
`oban: [queues: ..., cron: ...]`, validated like `services:`, and a
declaration becomes Oban options) and
`test/integration/m19_oban_test.exs`: a worker defined at the prompt writes a
line to `/priv`, a job scheduled for later survives a power cycle and runs on
the next boot, and `elixos.safe` runs no Oban.

**Notes.** `oban`, `ecto_sql` and `postgrex` become OS dependencies (ADR; pure
BEAM, no NIFs), with a Repo against M18's Postgres; Oban's migrations run
before it starts, once, before any queue. `Elixos.Oban` owns the child spec:
queues with their concurrency and `Oban.Plugins.Cron` entries collected from
every installed app's `elixos:` declaration (M11's spec machinery, extended),
the system's own jobs under a reserved prefix. Not boot-critical and not in
rescue, like Postgres - but it *is* stopped by the same shutdown hook, or a
power-off would cost a retry. A worker is an ordinary user module: the M6
image journals it and M15's agents already wrote the pattern down.

**Done when.** `make ci` is green with `MILESTONE=19`, both test files pass,
and the ADR for the dependencies is written.

- [x] Done (2026-10-11): `os/test/elixos/oban_test.exs` (4 tests),
  `os/test/elixos/oban_lifecycle_test.exs` (6 tests),
  `os/test/elixos/oban_image_test.exs` (2 tests) and
  `os/test/integration/m19_oban_test.exs` (1 test) pass: Oban 2.24.1, ecto_sql
  3.14.0 and postgrex 0.22.4 are pinned and ship in the factory release; queues
  run only after `Elixos.Oban.activate/0`, declarations are validated and
  persisted with the app, and rescue runs none of it (ADR-057, ADR-058).

- [x] Demo recorded: `demos/m19-oban.mp4` (`make demo M=19`).

---

## M20: Ask the human

**Goal.** Questions are data in the OS; front-ends are only views. `Elixos.Ask`
keeps a queue of open questions, any front-end can answer one, and the asking
process blocks until it is answered - so an agent can ask a person something
and act on the answer, from IEx, from an ssh session, or (M27) from the GUI.

**Acceptance.** `test/elixos/ask_test.exs` (the queue on the host: ordering,
several askers at once, a timeout, a dismissal, and answers checked against
the question) and `test/integration/m20_ask_test.exs`: an agent defined at the
prompt asks through the Jido action, the console shows the notice, the test
answers at the prompt, and the action returns the answer.

**Notes.** A question has an `id`, a `kind` (`:text`, `:choice`, `:multi`,
`:confirm`), the options a choice or multi offers (with an optional "other"
free-text answer), the asking process, an optional default and an optional
timeout. `ask/2` blocks and returns `{:ok, answer}` or
`{:error, :timeout | :dismissed}`; `pending/0` lists what is open; `answer/2`
and `dismiss/1` resolve by id. Every answer is validated against its question
(a choice must be one of its options, a multi a subset, a confirm a boolean),
so a front-end cannot hand back something the question never allowed. The
first front-end is the REPL: one notice line per new question on the console,
`elixos-ask: question <id> (<kind>): <prompt>` - a console line is API
(PROTOCOL.md §6), so it is written into PROTOCOL.md and matched byte for byte
by the test. A Jido action wraps `ask/2` with a schema, so agents get it as a
tool (Jido ships in the factory since M15). The queue is not boot-critical; a
question still open when its session ends is dismissed, never answered by
guesswork, and rescue runs none of it.

**Done when.** `make ci` is green with `MILESTONE=20`, both test files pass,
and the notice line and the question shape are in PROTOCOL.md.

- [x] Done (2026-10-11): `make ci` green at `MILESTONE=20` - 292 host tests,
  50 QEMU acceptances (M03-M20, both architectures built) - and:
  `os/test/elixos/ask_test.exs` (7 tests) and
  `test/integration/m20_ask_test.exs` (1 test) pass: questions are data in
  `Elixos.Ask` (ordering, several askers, a timeout, a dismissal, answers
  validated against the question, an asker that goes away dismissing its
  questions), the console prints the notice line, and the Jido action carries
  the answer back into the agent's state (ADR-059; the notice line and the
  question shape are in PROTOCOL.md §6, the fixture's own state-reading bug is
  ADR-061).
- [x] Demo recorded: `demos/m20-ask.mp4` (`make demo M=20`).

---

## M21: The OMP toolset on Elixos

> **Resumed (ADR-071).** Inventory and port canonical upstream OMP 18.10.1
> onto Jido Actions/Tools. The reference is commit
> `90701813e5fba6919067848989378b4ee6239c13`; no `clanklet` prerequisite remains.

**Goal.** An agent on the box gets the whole coding-agent toolset: every tool
the pinned OMP SDK exposes, with the same names, parameters, outputs and error
behaviour, so a prompt written for OMP works unchanged. The first
implementation is OMP's own TypeScript, run by QuickBEAM inside a peer BEAM
node that the main VM supervises - a crash in the JavaScript engine takes down
only the peer.

**Acceptance.** `test/elixos/toolset_test.exs` (the inventory equals the pinned
SDK's tool factories; the dispatcher picks the implementation before each call
and records which one ran; QuickBEAM runs with `apis: false` and its limits
set), `test/elixos/toolset_differential_test.exs` (every tool in the inventory
passes its fixtures recorded from OMP - outputs *and* failure semantics - in
the peer node), and `test/integration/m21_toolset_test.exs`: on the box a tool
call runs in the peer node, never the main VM; it sees only the calling
session's workspace and directory; and killing the peer mid-call returns an
error to the caller while the prompt keeps answering and the shim never
notices (no missed heartbeat, no relaunch).

**Notes.**
- *The reference.* The resumed arc targets upstream 18.10.1 at commit
  `90701813e5fba6919067848989378b4ee6239c13` (ADR-071). The original 18.8.7
  inventory in `os/test/fixtures/omp/inventory.exs` is historical until the
  new inventory and actual upstream outcomes are recorded. A reference move
  is never an excuse to synthesize expected results from the port.
- *The original inventory* is what the 18.8.7 SDK's factories construct -
  `BUILTIN_TOOLS` and
  `HIDDEN_TOOLS` in `src/tools/index.ts`, plus the settings-gated custom tools
  `src/sdk.ts` installs: `read`, `security_scan`, `bash`, `edit`, `ast_grep`,
  `ast_edit`, `ask`, `debug`, `ida`, `eval`, `github`, `glob`, `grep`, `find`,
  `lsp`, `checkpoint`, `rewind`, `context_notes`, `new_context`, `task`,
  `wait`, `todo`, `web_search`, `write`, `memory_edit`, `retain`, `recall`,
  `reflect`, `learn`, `manage_skill`; hidden `think`, `yield`, `goal`;
  settings-gated `generate_image` and `tts`. 35 tools, recorded with the pin
  in `os/test/fixtures/omp/inventory.exs`. MCP and extension tools are a
  user's configuration, not the toolset. A factory that returns `null` without
  its dependency (`createIf`: `ida` without IDA, `lsp` without a language
  server, `github` without `gh`) keeps that behaviour - absent, as OMP would
  be on the same machine.
- *The tool host.* QuickBEAM (Hex `quickbeam` 0.11.3, pinned with its checksum
  like every dependency) runs in a peer node started with `:peer` and
  supervised by the main VM; QuickJS never loads into the main VM. It runs
  with `apis: false` - with `apis: [:node]`, a write to `process.env` reaches
  `System.put_env/2`, which is VM-global (ADR-016). Use
  `QuickBEAM.ContextPool` and `QuickBEAM.Context`: 0.11.3's high-level
  `QuickBEAM.start/1` silently drops `:max_reductions`. Context startup receives
  positive memory and reduction budgets; every eval/call receives its timeout.
  Acceptance executes quota-breaking code and verifies the context still works,
  rather than only comparing an options list.
- *Pure core, Elixir effects.* Each tool splits into a pure core (parsing,
  matching, patch application, formatting), which runs in QuickBEAM, and Elixir
  effect handlers for everything QuickBEAM's missing Bun and Node APIs would
  have done - spawning processes, file access, globbing, the network - each
  scoped to the calling session's workspace and its M9 session directory. A
  tool sees what its session may see, and nothing VM-global moves.
- *Native dependencies.* A tool that needs an external binary gets it as an
  Alpine package in the image (`bash` for the bash tool, `ripgrep`, `git`,
  `ast-grep`, language servers), pinned in the lockfile like the rest. A tool
  that needs an OMP native addon (`@oh-my-pi/pi-natives`) is tried in QuickBEAM
  first; where QuickBEAM cannot load it, that piece is reimplemented in Elixir
  or Zig and the differential suite decides whether it matches.
- *The suite.* Fixtures are recorded from the pinned OMP - Unicode, malformed
  input, numeric boundaries, large payloads - and compared on outputs and on
  failure semantics. Shadow comparisons, when a second implementation runs
  beside the first, compute only pure results: effects run once. The dispatcher
  (`Elixos.Toolset`) chooses the implementation before each call and records
  which one ran, so a later implementation (M24's native ones) is promoted or
  reverted tool by tool without touching callers.
- *Generation selection.* `config/config.exs` can select a tool's Elixir or
  native module with `config :elixos, Elixos.Toolset, implementations:
  %{"<tool>" => {:elixir | :native, module}}`; absent entries use QuickBEAM.
  The module implements `Elixos.Toolset.Implementation.call/2`, with OMP
  parameters and the isolated session. M24's runtime promotion or reversion
  overrides that generation selection. Configuration is in the always-loaded
  OS config, not the optional `MIX_TARGET=elixos` layer.
- *What waits.* A tool that depends on a later milestone waits for it, and the
  inventory says so (whatever needs a browser waits for M25); the rest go
  ahead.
- *Checked 2026-10-10.* QuickBEAM 0.11.3 publishes `x86_64-linux-musl` and
  `aarch64-linux-musl` NIFs, so it needs no source build. Its dependency `oxc`
  (a Rust NIF that strips TypeScript) publishes musl only for x86_64 in 0.19.0.
  For aarch64, melange builds `oxc` from source with Alpine's Rust, preserving
  QuickBEAM's TypeScript path on both architectures. QuickBEAM's own source
  build needs Zig 0.16, which melange provides if its precompiled NIFs go away.

**Done when.** `make ci` is green with `MILESTONE=21`, the three test files
pass, and ADR-047 holds.

- [ ] Demo recorded: `demos/m21-toolset.mp4` (`make demo M=21`): `read`, `grep`
  and `edit` from the prompt through the peer node, then the peer killed
  mid-call and the prompt still there.

---

## M22: The on-box coding agent

> **Resumed (ADR-071).** Port the upstream prompt and skill surface onto the
> Jido coding-agent runtime after M21's tools. The former human-agent-work
> dependency no longer blocks this milestone.

**Goal.** A coding agent lives on the machine. A Jido agent owns the loop and
uses M21's toolset; it starts from IEx or over SSH like any REPL session,
reads its project instructions from the repository it works in, asks the human
through M20's Ask, and works in its own workspace on `/priv`. Its system
prompt and its tools are code that lives in the generation.

**Acceptance.** `test/elixos/coder_test.exs` (the loop against a scripted model
on the host: tool calls round-trip through the toolset, a subagent - OMP's
`task` - is a Jido agent under the same supervisor, a question goes through
`Elixos.Ask`, the repository's `AGENTS.md` reaches the model, and a credential
never appears in anything logged) and `test/integration/m22_coder_test.exs`:
from IEx, the agent completes a small coding task in a workspace under
`/priv/work/` with the real toolset, against a model stub on the loopback so
the test needs no network; the result is on disk; and the stub's credential is
in neither the console transcript nor `/priv/journal.log`.

**Notes.**
- *The loop.* `Elixos.Coder` is a Jido agent: a model turn, tool calls through
  `Elixos.Toolset`, the results back, until the model yields - OMP's semantics,
  `yield` and `goal` included. Subagents (`task`) are Jido agents under the
  same supervisor with their own sessions, and `wait` waits on them. Questions
  to the human are `Elixos.Ask` questions (M20), so the console, an SSH session
  or the GUI can answer them.
- *Instructions.* Project instructions come from the `AGENTS.md` of the
  repository the agent is working in, as in OMP. The agent's own system prompt
  and its tool selection are code in the generation (ADR-048): saved, NEXT'd
  and committed like any module, restored by a fallback, and in rescue the
  factory's - never a working copy.
- *Isolation.* Each session has its own workspace (a directory under
  `/priv/work/`, a git worktree when the work is a repository) and its own M9
  session directory. Nothing VM-global moves (ADR-016): not the cwd, not the
  environment.
- *Credentials.* Model credentials live in `/priv/credentials/`, outside any
  generation - a generation is shared, restorable state; a key is neither - and
  never reach a log, the journal or a crash dump: the client holds them as
  values it redacts wherever state is formatted.
- *Models.* The client speaks the OpenAI-compatible API M15's agents already
  use (`Elixos.Agents.LLM`). The test's model is a scripted stub on the
  loopback that replays tool calls; the demo is a run against a live model.
- *Starting it.* `Elixos.Coder.start/1` from IEx or an SSH session (M12) ties
  the agent's output to that session's group leader, like any REPL session
  (M9).

**Done when.** `make ci` is green with `MILESTONE=22`, both test files pass,
and ADR-048 holds.

- [ ] Demo recorded: `demos/m22-coder.mp4` (`make demo M=22`), against a live
  model.

---

## M23: Self-modification

> **Resumed (ADR-071).** Implement generation-only self-modification; it does
> not depend on the human finishing a separate OMP integration. The original
> candidate, health, evidence and fallback acceptance remains the contract.

**Goal.** The agent can change Elixos itself - OS code, its own tools, its own
prompt - and those changes reach the running system only through generations:
a candidate built in a child ERTS and tested in a peer node, then NEXT, a
reboot, real health checks, and COMMIT or fallback, with the evidence kept.
Code the agent writes never loads directly into the main VM.

**Acceptance.** `test/elixos/candidate_test.exs` (a candidate's manifest
records what produced it - session, model, tool revisions, parent generation;
the health predicate runs the system's own checks, not liveness; hot-loading
from an agent session is refused) and
`test/integration/m23_self_modification_test.exs`:
- the agent, driven by a scripted model, improves one of its own tools; the
  candidate passes its suite in a peer node, is committed, and the improvement
  survives a reboot;
- a deliberately broken candidate falls back to `last_good`, and its evidence -
  crash dump and logs - is on `/priv/evidence/<generation>/`;
- factory rescue runs the factory's agent, its prompt and its tools, not the
  suspect one.

**Notes.**
- *The path.* `Elixos.Candidate` builds a candidate from a working tree in a
  child ERTS (M11's mechanism; never the main VM's code server), runs the
  full portable system unit suite and the toolset's recorded fixture/smoke suite
  against it in a peer node, then hands it to the shim: NEXT, reboot, health,
  COMMIT or fallback - M6 to M8, unchanged. M17 is what makes this safe:
  whatever a candidate does,
  it cannot alter `last_good` or the factory.
- *Real health.* `Elixos.Boot.AutoCommit`'s predicate becomes the system's own
  checks - its tests and the toolset smoke tests - not just "the VM stayed up".
  A candidate that boots but fails them is never committed, and the shim's
  attempt counter falls back.
  Host build orchestration (`:host_orchestration`) and QEMU provisioning are
  not on-box suites: rerunning candidate-build orchestration inside its own
  validation would recurse. The same full portable suite runs before NEXT and
  at boot, in an isolated peer; deliberate core and selected-tool defects must
  fail the real checks, not only injected callbacks.
- *Evidence.* A failed candidate's crash dump, its logs and the failing check
  are kept under `/priv/evidence/<generation>/` (ADR-025's dumps already live
  on `/priv`); a fallback never deletes evidence.
- *Provenance.* Each manifest records what produced it: the session, the
  model, the tool revisions (the dispatcher's record, M21) and the parent
  generation. `Elixos.Candidate.provenance/1` reads it back.
- *Never in the main VM.* Code the agent writes is compiled and tested outside
  the main VM and reaches it only by being booted as a generation; hot code
  loading from an agent session is refused (ADR-049).
- *Side effects.* A rollback restores code and the image's state, not the
  world: a sent message, a payment or a migration stays done. Migrations follow
  the expand-before-commit rule (M18): a generation ships only migrations its
  parent can ignore.

**Done when.** `make ci` is green with `MILESTONE=23`, both test files pass,
and ADR-049 holds.

- [ ] Demo recorded: `demos/m23-self-modification.mp4` (`make demo M=23`).

---

## M24: Native hot paths

> **Resumed (ADR-071).** Measure and port the toolset's native hot paths after
> the reference differential suite is available. The original parity,
> concurrent p99, peer-crash and artifact-pinning acceptance remains unchanged.

**Goal.** Measured hot paths of the toolset move to Zig through Zigler, as pure
functions, one at a time - promoted only when the differential suite says they
match and a benchmark says they are faster where it counts.

**Acceptance.** `test/elixos/native_test.exs`: one hot path (edit's patch
application) runs natively with results identical to the reference across the
whole differential suite; its p99 latency under concurrent sessions,
conversion overhead included, beats the QuickBEAM implementation's; and a
deliberately crashing native candidate, run in the peer node, takes down only
the peer - the caller gets an error, the main VM never notices.
`test/integration/m24_native_test.exs`: on the box the dispatcher records the
native implementation as the one that ran, and the generation's manifest pins
its library, the target and the toolchain.

**Notes.**
- *Promotion (ADR-050).* Measure first; port a pure function; promote it only
  after the differential suite passes and a p99 benchmark under concurrent
  sessions, conversion overhead included, shows the gain. Unproven native code
  runs in the peer node; a promoted implementation moves into the main VM only
  if latency demands it.
- *NIF discipline.* Synchronous NIFs only for bounded work well under 1 ms;
  longer work uses dirty or threaded execution with admission limits.
- *Pinning.* Generation manifests pin native libraries content-addressed - each
  version its own file name, so loading a new one never replaces an old one in
  place - plus the target and the toolchain. `Elixos.Native.pin_library/2`
  packages a built library under its actual SHA-256; `Image.save/2` records the
  exact pins in `manifest.native_libraries`. Zigler fetches its own Zig with
  `mix zig.get`: that version is pinned and baked into the toolchain package
  as `/priv/toolchain/zigler/zig`, separate from the shim's tracking-master
  compiler. Nothing is fetched on the box.
- *Reverting.* The dispatcher can revert one tool's implementation without a
  generation switch. That reverts the implementation, not the environment: the
  library stays pinned in the manifest that shipped it.

**Done when.** `make ci` is green with `MILESTONE=24`, both test files pass,
and ADR-050 holds.

- [ ] Demo recorded: `demos/m24-native.mp4` (`make demo M=24`): the benchmark,
  then the crashing candidate taking down only the peer.

---

## M25: A browser to call from the prompt

**Goal.** A headless browser, shipped with the system, callable from IEx and
from agents: navigate, extract, evaluate JavaScript, screenshot - with no
download at run time.

**Acceptance.** `test/elixos/browser_test.exs` (the pinned manifest decides
the argv: a musl-clean adapter is exec'd directly, a glibc one through its
private loader) and `test/integration/m25_browser_test.exs`: the adapter comes
up from the read-only `/system`, navigates to a stub HTTP server on the
loopback, returns the page's text, evaluates JavaScript, produces a PNG, and
`elixos.safe` starts none of it.

**Notes. The gate first.** Run `ldd` on the pinned Lightpanda binary at build
time. If it needs glibc, carry a private glibc in the system image and start
Lightpanda through glibc's own loader
(`ld-linux-x86-64.so.2 --library-path <dir> lightpanda serve`), exec'd
directly as a port: a few MB, no rebuild. Building V8 for musl is the last
resort, and **abandoning M25 is an allowed outcome**; the ADR records which
arm was taken and why. `agent-browser` is not a portable fallback - it drives
Chrome for Testing (glibc) or another browser over CDP, so the libc question
only moves. jido_browser 2.3's adapter is optional and limited (navigation,
clicks, typing, screenshots, extraction, JS evaluation; no element refs, saved
state, tabs or console capture): the milestone is the adapter, its pin and its
service, not the full surface. Binaries are pinned and verified when the image
is built (M14's verification, ADR-009's rule: nothing is fetched on the box),
never by jido_browser's own downloader. The implemented stack uses `cdp_ex`
and the adapter-compatible `Elixos.Browser.CDP` interface, not a
`jido_browser` dependency (ADR-065). `Elixos.Browser` starts the adapter only
in normal mode, stops it on poweroff and never lets it block the prompt.

**Done when.** `make ci` is green with `MILESTONE=25`, both test files pass,
and the ADR records the loader decision - or M25 is explicitly abandoned in the
roadmap with the reason.

**Done (2026-10-11).** `make ci` green at `MILESTONE=25`: 298 host tests, 51
QEMU tests, and both images building with two agreeing digests each. The loader
arm taken is ADR-064 - the pinned upstream Lightpanda, stripped, with the
private glibc it needs in the package's own directory under `/system/browser`,
started through glibc's own loader, which `command/1` turns into argv. The stack
is ADR-065 - `cdp_ex` behind the same session/page interface `jido_browser`'s
Lightpanda adapter expects, with the process a Port; `light_cdp` and
`jido_browser` itself were evaluated and rejected there with evidence. The
on-box toolchain gained Rust (ADR-066), and the acceptance now releases its
first VM before the rescue boot (ADR-067).

- [x] Demo recorded: `demos/m25-browser.mp4` (`make demo M=25`).

---

## M26: Installed packages are Mix dependencies

**Goal.** A project built on the box sees the system's installed packages as
its dependencies: after `Elixos.Package.install(:hello_app)` - whose closure
installs `hello_dep` first (M15) - the build resolves `hello_dep` from
`/priv/apps` instead of reaching for a repository, so M10's one version per
package holds for anything built on the box.

**Acceptance.** `test/integration/m26_system_deps_test.exs`: `hello_app`
installs by name on a box with no network, its dependency's code is the
*installed* copy (the loaded `HelloDep` lives under `/priv/apps/hello_dep/`),
and `HelloApp.greet()` answers with the value that dependency provides.

**Notes. The gap found in M15's review, fixed in M26.** Adding an installed
ebin to the code path made modules loadable but did not teach Mix where a
declared dependency lived. Building `hello_app` therefore asked for Hex's SCM;
the factory had no Hex SCM, so the network-less acceptance failed.
ADR-068 chose `Elixos.Package.SCM` over rewriting project sources: the build
child prepends it before Mix loads dependencies, and it points an installed
package's destination at `/priv/apps/<name>`. Explicit sources, absent
packages and incompatible versions fall through to the ordinary SCMs.

**Done when.** `make ci` is green with `MILESTONE=26`, the QEMU test passes,
and the ADR records the mechanism.

**Done (2026-10-11).** `make ci` green at `MILESTONE=26`: 298 host tests, 52
QEMU tests, and both images assembling twice to agreeing digests each (x86_64
rootfs `c6dc99d0…`, aarch64 `1b2df389…`). The child ERTS that runs a build
prepends `Elixos.Package.SCM` before Mix loads anything (ADR-068): a declared
dependency that this box installed is answered where it is - `checked_out?/1`
is true, so no SCM reaches for a repository - and one whose requirement the
installed version does not satisfy falls through to the ordinary SCMs, never to
a silent wrong copy. `install(:hello_app)` therefore installs its closure first
(`hello_dep`, M15) and then builds against `/priv/apps/hello_dep` on a box with
no network: the module the acceptance finds loaded is that copy, under
`/priv/apps/hello_dep/ebin/`. Mix's first red run said it in its own words -
`Could not install Hex because Mix could not download metadata at
https://builds.hex.pm/installs/hex.csv`.

- [x] Demo recorded: `demos/m26-system-deps.mp4` (`make demo M=26`).

---

## M27: GUI (Emerge on the framebuffer)

**Goal.** A dialog on the cyberdeck's own screen: Emerge renders the Ask
queue's questions to the panel, the person answers with the keyboard, and IEx
stays alive behind it - a GUI that is never in the boot-critical path, whose
first app is the queue M20 already has.

**In progress.** The four off-screen dialogs, framebuffer sink, evdev input,
lease-based console handover and QEMU GPU/QMP support are implemented.
`make test` and the x86_64 GUI acceptance have passed; the synchronized
development demo exercises real keyboard input for all four dialog kinds.
ARM64 renderer packaging and the full milestone gate are still in progress.

**Acceptance.** `test/elixos/emerge_render_test.exs` (each Ask dialog renders
with no display and its pixels are checked) and
`test/integration/m27_gui_test.exs`: a pending question appears on the
framebuffer, an injected key answers it, the asking agent gets the answer, and
the console works again after the GUI exits (rescue stays text-only).

**Notes. What Emerge actually offers (checked against its 0.4.2 docs).**
- *Frames.* `backend: :headless, rendering_api: :raster, headless: [mode:
  :binary, target: pid, ...]` sends `{:emerge_skia_frame,
  %VideoInterop.Frame{}}` to a local PID; the sink writes each frame to
  `/dev/fb0` itself (no Mesa, no GPU). At compile time,
  `config :emerge, compiled_backends: []` selects the *raster backend profile*,
  not the libc target. The host fetch selected `x86_64-unknown-linux-gnu--raster`;
  RustlerPrecompiled selects the target from ERTS and `TARGET_*` overrides.
  The image pins and verifies the x86_64 musl artifact at build time
  (ADR-009, ADR-069) and packages its private dependency closure.
  Emerge 0.4.2 lists no aarch64 musl precompiled target; ARM64 uses a locked
  source build. Both architectures now package their own factory loader.
- *Rendering off-screen.* `EmergeSkia.Native.render_tree_to_pixels_nif/2` and
  `render_tree_to_png_nif/2` accept a serialized EMRG tree and raster options
  and render synchronously with no window. The GUI wrapper uses
  `EmergeSkia.TreeRenderer.render_to_pixels/3` for the pixel-buffer tests.
- *Input is ours, not Emerge's.* 0.4.2 has **no API to inject input into the
  renderer**; events only flow out (`set_input_target/2`, `set_input_mask/2`,
  `Emerge.handle_input/2`), and a headless raster renderer has no input device
  at all. So a small static Zig helper grabs the evdev devices (`EVIOCGRAB`)
  while the GUI owns the screen and streams their events to the BEAM, and the
  dialog's logic - which option is selected, which key answers - is Elixir.
  The helper needs no root: it runs as the BEAM's own uid, and the `input`
  group gives it the event devices (M17: access that only needs a group uses
  the group, never the allow-list); `/dev/fb0` the same way, through `video`.
  The QEMU test injects at `Elixos.GUI.input/1`, the same entry the helper
  feeds - `{:key, key, :press | :release}`, `{:pointer, x, y}`,
  `{:button, button, :press | :release}` - and QEMU's own keyboard through a
  QMP socket (`send-key`, and `screendump` for the demo's frames) is the
  hardware-level variant exercised by the demo.
- *Kernel.* The common fragment enables `CONFIG_FB_DEVICE`,
  `CONFIG_DRM_VIRTIO_GPU`, `CONFIG_INPUT_EVDEV` and `CONFIG_VIRTIO_INPUT`.
  QEMU adds `virtio-gpu-pci` and `virtio-keyboard-pci`. These are configuration
  changes, never a kernel patch (ADR-001).
- *Console handover.* While the GUI owns the screen, unbind fbcon through its
  entry under `/sys/class/vtconsole`; rebind it when the GUI exits. Those
  writes need root, so the handover is a privileged helper on M17's allow-list
  (`console-handover`, ADR-046): the BEAM asks for it by name and cannot run
  anything else as root. The input helper's grab dies with the helper, so a
  crash returns the keyboard.
- *Failure modes.* The GUI is never boot-critical: renderer load/start or
  helper failures leave the console available, and rescue stays text-only.
  The NIF runs inside the VM, so a Skia crash can take the VM down with it
  (ADR-069). Lease closure restores fbcon after ordinary GUI/helper death;
  restarting a SIGKILLed broker restores abandoned bindings (ADR-070).

**Done when.** `make ci` is green with `MILESTONE=27`, both test files pass,
and the ADRs (the renderer as a service; the input path) are written.

- [ ] Milestone demo gate: `demos/m27-gui.mp4` combines synchronized framebuffer and console recordings (`make demo M=27`). Development recording published; tick at the completed milestone gate.

---

## Later (not yet scheduled)

Wi-Fi (Q3), a DHCP client in Elixir, power-button handling from input events,
kernel/factory upgrades on hardware (Q5), process-state persistence (Q2),
gsh packaging (Q6), CRIU as a stretch goal. A terminal view in Emerge that
hosts IEx as just another REPL session, so the GUI can become the shell.

### Hardware-accelerated graphics profiles (ADR-072)

Integrate the human's completed `live_gpui` stack — GPUI + LiveView via
Rustler — and ship AMD and NVIDIA hardware-accelerated images. Each profile
packages its vendor drivers, firmware and graphics userspace dependencies;
the OS, LiveView and agent code remain shared. The current native-editor
screenshot is a smoke test of that unfinished project, not a shipped backend.
Verify real acceleration and native editing under busy callbacks, keyed-row
reordering and view-process restart on each profile.

