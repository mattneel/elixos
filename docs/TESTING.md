# Testing

Elixos is built test-first (ADR-017). The whole roadmap already exists as
tests; building Elixos means turning them green, one milestone at a time.

## The layers

| layer            | where                                   | runs on      | command          |
|------------------|-----------------------------------------|--------------|------------------|
| shim unit        | `shim/src/*.zig` (`test` blocks)        | dev host     | `make test-shim` |
| userland unit    | `os/test/elixos/**/*_test.exs`          | dev host     | `make test-os`   |
| shared contracts | `spec/*.vectors`, read by both suites   | dev host     | both of the above |
| system           | `os/test/integration/m*_test.exs`       | QEMU         | `make test-qemu` |
| ARM64 smoke      | `os/test/integration/m16_aarch64_test.exs` | QEMU (TCG) | `make test-qemu-aarch64` |
| hardware         | manual checklist in docs/ROADMAP.md M13 | the cyberdeck | a human         |
| native OCI       | SDK task and scoped runtime/export smoke below | Linux Docker daemon | separate from `make ci` |

`make test` runs the two unit layers. `make ci` runs those tests, the
non-aarch64 QEMU suite and both architecture image builds; it does **not**
run the ARM64 smoke test or the manual hardware checklist.

Native OCI application-image and Fly checks are separate deployment gates.
A passing machine/QEMU gate does not establish them; their recorded results
are [below](#native-oci-images-and-docker-proof).

For iteration on the current work, `make check M=27` builds the host image,
runs the Zig and ExUnit host suites through M27, then only
`test/integration/m27_*.exs`. Use the full `make ci` at the milestone boundary,
not after every edit.

## Milestones

`MILESTONE` selects the active gate, including a milestone whose implementation
is still in progress. It is not a count of completed milestones. M1–M19 and
M25–M29 are delivered; M20 is retired under ADR-093; M21–M24 are withdrawn
under ADR-083. The K230 track continues with M30–M33.

- **Zig:** every test begins `try milestone.require(N);`, which returns
  `error.SkipZigTest` until `MILESTONE >= N`. The Makefile passes
  `-Dmilestone=$(cat MILESTONE)`.
- **ExUnit:** every test module has `@moduletag milestone: N`;
  `os/test/test_helper.exs` excludes later milestones. `os/test/meta_test.exs`
  fails if a test module forgets the tag.
- **Overrides:** `ELIXOS_MILESTONE=N` selects the ExUnit gate for a direct
  `mix test` command; `make check M=N` passes the selection to both host
  test layers and its integration run.
- **Retired and withdrawn milestones:** M20's Ask queue and its suites are
  removed by ADR-093. M21–M24's rejected bundled coding-agent contract,
  fixtures and suites are retired by ADR-083. Neither is silently skipped or
  counted as passing. Retained OS acceptance assertions and timeouts are
  unchanged.
- **Architecture:** `:aarch64` integration tests are excluded unless
  `ELIXOS_QEMU_AARCH64=1`.

Stubs fail loudly and say which milestone implements them: Zig stubs
`@panic("TODO(M1): ...")` (the build runner reports each crashed test and
carries on with the rest), Elixir stubs raise `Elixos.NotImplemented`.

## Shared vectors

`spec/protocol.vectors` is the control protocol's contract, read verbatim by
`shim/src/protocol.zig` (embedded via `addAnonymousImport` in build.zig) and by
`os/test/elixos/shim/protocol_test.exs` (one ExUnit test per line). Add a case
there and both sides must handle it. The format is documented in the file.

`spec/ring.vectors` is the inter-core ring's contract (docs/PROTOCOL.md §11):
capacities, headers, frames, decoding and a counter wrap, read by
`shim/src/ring.zig` the same way and by `os/test/elixos/ring_vectors_test.exs`
against the Elixir implementation (`os/test/support/ring.ex`) that plays the
coprocessor's side in `coproc_ring_test.exs`.

## QEMU tests

**Helpers** (`os/test/support/`):

- `Elixos.Test.QEMU`: `boot/2`, `boot_to_iex/2`, `expect/3`,
  `expect_with_before/3`, `await_log/3`, `expect_exit/2`, `send_line/2`,
  `send_raw/2`, `iex/3`, `transcript/1`, `refute_kernel_panic/1`, `stop/1`.
  One `boot/2` is one QEMU process is one power-on: QEMU runs with
  `-no-reboot`, so a guest reboot ends the process and the test boots again
  with the same disk. Matching happens on ANSI-stripped console text.
  - IEx redraws the current prompt with your input after Enter, so `iex/3`
    waits for a prompt numbered *higher* than the last one seen
    (`vm.iex_prompt`) and returns everything printed before it.
    Every call returns an updated `vm`; thread it into the next call, including
    through loops. Multi-line input is evaluated as one parenthesized block
    (ADR-042, ADR-054).
  - Shim log lines can arrive while you wait for something else; assert them
    with `await_log/3`, which searches everything this boot printed.
- `Elixos.Test.Disk`: `fresh!/1` (sparse copy of the pristine
  `build/disk.img`, or `build/aarch64/disk.img` when
  `ELIXOS_QEMU_AARCH64=1`), `read/2`, `exists?/2`, `write!/3`, `put_tree!/3`.
  Each disk carries its own architecture's toolchain. It uses e2fsprogs'
  `debugfs`, so no root and no mounting. Only use it while QEMU is not running.
  Guest `/priv/x` is `/x` here.
- `Elixos.Test.QMP`: the GPU-enabled harness opens a private Unix QMP socket
  and adds virtio GPU/keyboard devices. The M27 demo sends actual QEMU keys
  and captures framebuffer PPMs through this helper; the shipped acceptance
  also exercises the `Elixos.GUI.input/1` front-end seam.

**Conventions.**
- QEMU tests live in `os/test/integration/`, are tagged `:qemu`, and set a
  generous `@moduletag timeout:`.
- Every test boots its own fresh disk copy, so tests never share state.
- End tests with `QEMU.refute_kernel_panic/1`: PID 1 must never take the
  kernel down.
- `make test-qemu` builds the image before running the suite.
  `make check M=27` does the same for a focused run. For a direct test command,
  first build the image, then use `cd os && ELIXOS_QEMU=1 mix test
  test/integration/m26_system_deps_test.exs` (optionally set `ELIXOS_MILESTONE`).
  `mix test` itself does not refresh the guest image.
  Never use `--include qemu`: an include filter also re-includes future milestones.

**Speed.** Without `/dev/kvm` QEMU falls back to TCG automatically (`-accel
kvm -accel tcg`). The kernel still reaches PID 1 in about two seconds; the
BEAM is slower. Raise `ELIXOS_QEMU_SLOWDOWN` (a timeout multiplier, default 1)
if boots time out. On WSL2, KVM needs nested virtualization enabled.

**Test hooks.** `elixos.test.*` kernel parameters (PROTOCOL.md §5) are enabled
by `-Dtest-hooks=true`; the default for a direct `zig build` is false
(ADR-018). The current `melange/shim.yaml` machine-image recipe explicitly
enables them, including the initramfs embedded by the UEFI script. Those
machine images do not yet have a separate hook-free deployment target.
In contrast, `scripts/build-docker-image.sh` always compiles the current
native container shim with `-Dcontainer=true -Dtest-hooks=false`.
The hooks let tests reach otherwise awkward states: a plan without a launch,
or a shim panic. `make shim` and `make release-shim` are not current targets.

**Debugging a boot.** `make qemu ARGS="elixos.safe"` boots interactively on
your terminal (Ctrl-A X quits). A failing expectation prints the last 4 KB of
the console.

## RAM-backed Live acceptance

On x86_64, build the normal image with its approved factory source pin, then
run `scripts/build-uefi-image.sh --live`. It emits `build/esp-live.img`; its
`EFI/BOOT/BOOTX64.EFI` is the standalone, unsigned Live EFI file.
The full toolchain profile is exercised with 4 GiB guest RAM.

`test/integration/m27_ram_live_test.exs` builds a Live initramfs from the
pristine packaged base. It boots with a valid writable ext4 disk explicitly
selected as `elixos.data`, checks normal PostgreSQL service, a read-only
`/system` and retained console despite an available framebuffer, then saves
code and writes a file and database row. A second cold boot must lose all
three kinds of state while the attached disk's SHA256 remains identical.
Run it with `cd os && ELIXOS_QEMU=1 ELIXOS_MILESTONE=27 mix test
test/integration/m27_ram_live_test.exs`.

The laptop surface additionally needs an OVMF boot of the actual EFI/ESP,
USB keyboard input, framebuffer screenshots and unchanged file-backed
NVMe/SATA/data-disk sentinels. Pass only regular files, never host block
devices. Force `-accel kvm` without a TCG alternative when proving nested
virtualization. WSL2 runs under Hyper-V; WSLg supplies display integration,
not the KVM path. This does not require physical PCIe passthrough.

## Native OCI images and Docker proof

The OCI boundary runs the existing shim, factory and services directly on the
**Docker daemon's Linux kernel**. It does not boot the packaged machine kernel
or an inner VM. On Docker Desktop, that kernel belongs to Docker's Linux
environment, not necessarily the shell host. `Elixos.runtime/0` returns
`:container`; the actual daemon architecture, SDK image and runtime image
must match. Native `amd64`/`x86_64` and `arm64`/`aarch64` names are normalized.
`mix elixos.image` rejects mismatches instead of enabling transparent emulation.

### Preparing native base images

The packaging helper needs Docker CLI with a running Linux daemon and
buildx/BuildKit, Python 3.10+, the repository's pinned Zig, and existing pinned
target outputs. `make check-tools` covers the broader machine-image build
prerequisites. If the outputs do not exist, first prepare the reviewed native
factory source input: set `ELIXOS_OH_MY_JIDO_SOURCE` to its canonical checkout,
inspect `elixir scripts/stage-coding.exs pin "$ELIXOS_OH_MY_JIDO_SOURCE"`,
and explicitly set `ELIXOS_CODING_SHA256` to the approved hash. Do not
automatically bless a changed checkout or modify it as part of packaging.

From the repository root, for a native x86_64 daemon:

```sh
scripts/build-image.sh x86_64
scripts/build-docker-image.sh --arch x86_64 elixos:sdk
scripts/build-docker-image.sh --runtime --arch x86_64 elixos:runtime
```

Skip the first command when the correct pinned artifacts already exist.
`ELIXOS_BUILD` can select an existing artifact directory. The OCI helper uses
the target's `oci/`, `rootfs.digest`, `system/oci/` and, for the SDK, the pinned
toolchain APK. It rebuilds only the current container shim, with test hooks
disabled. Neither a kernel/initramfs nor a saved disk/session is an OCI input.
Only sanitized package layers enter the narrow Docker build context.

The SDK has immutable `/toolchain`; the runtime does not. `/priv` is explicit
writable state, not the SDK location. The optional final argument names a
local tag; no image registry publication is implied. `--arch aarch64` selects
ARM64 artifacts, but cross-packaging alone neither boots nor verifies ARM64.
Use a matching native daemon for execution.

The [interactive Docker recipe](../README.md#native-oci-images-docker) lists
the runtime flags. Container hardware controls and the framebuffer GUI are
not supported. This profile never mounts host disks or reboots the hosting
kernel.

### Verified Docker results (x86_64)

Native x86_64 base-image smokes booted the real PostgreSQL/Oban userland in
Docker on the daemon kernel, with a read-only root, no passed host devices and
no privileged mode.

An application image built by the public `mix elixos.image` task then passed
the complete gate and these runtime checks:

- The real install/save, reboot 75, same-volume restore, unmodified default
  `Elixos.Health.run/0`, commit and export all passed. Then the final runtime
  image was built.
- The runtime image booted on a fresh volume and on a genuinely empty volume
  (`volume-nocopy`). A fresh volume starts with empty application state.
- Counter and SQL rows persisted across container removal on a retained
  volume.
- SIGTERM exited 0. A requested reboot exited 75, and
  `--restart=on-failure` started the container again.
- A populated volume without `boot.state`, and an interrupted seed
  initialization, were refused with their data unchanged.

These results do not cover ARM64 execution, other daemons, backups,
replication or high availability. An app's HTTP listener and health
endpoint are the app's own; neither the SDK nor the OS health gate creates
them.

**Commit timing.** Each start counts as a boot attempt until
`Elixos.Boot.AutoCommit` commits. Containers ignore host boot parameters, so
the commit waits for the default 30 s of healthy uptime. Repeated restarts
inside that window raise the attempt count and can make the shim fall back to
`last_good`.

The [SDK guide](../hex/README.md#build-a-native-application-image) specifies
repository trust, offline public mirrors, image contents and volume precedence.

## Firecracker boot proof

`scripts/install-firecracker.sh` verifies the pinned upstream 1.17.0 archive
and installs only into `build/`. `scripts/run-firecracker.py` boots the
existing x86_64 `bzImage` and Live initramfs using KVM, not another kernel
variant or guest rootfs. No block device, TAP, management socket or GPU is
attached. It is a development launcher, not the production jailer.

The exercised scenario boots normal IEx twice, checks Linux 7.2.9 and init
as PID 1, runs PostgreSQL and verifies that a file/database row vanish on the
next launch. `Elixos.reboot()` performs clean service shutdown and ends this
owned VMM; running the launcher again is the next cold boot.
External networking and production isolation are not claimed by this smoke.
The current SDK-capable Live initramfs was also booted directly: its real
data-directory API returned `/priv/data/microvm_sdk`, and PostgreSQL returned
9191. `Elixos.poweroff()` shut down the BEAM but reported that power-off was
unavailable and halted the guest; the owned VMM then needed launcher
termination. Use the verified reboot path to end this development profile.

## Native application SDK proof

The following records source-package SDK and machine-kernel guest proof.
Native OCI health/export results are in
[Verified Docker results](#verified-docker-results-x86_64); the cloud result
is in [Fly application proof](#fly-application-proof).

Host tool gates:

```sh
cd hex/packages/elixos_sdk && mix test
cd ../elixos_demo_stats && mix test
cd ../elixos_demo
mix deps.get --only test --target host
mix test
```

The SDK suite builds real Hex metadata in fresh prod/Elixos processes,
including target/environment filtering, native OS requirements and portable
libraries. The generated project's actual host tests run without an OS
facade. The demo's durable-state suite starts a fresh child VM to catch safe
ETF schema-loading failures that a same-VM service restart misses.

The focused guest gates are:

```sh
cd os
ELIXOS_QEMU=1 mix test \
  test/integration/m27_native_package_contract_test.exs \
  test/integration/m11_self_hosting_test.exs \
  test/integration/m26_system_deps_test.exs
```

They exercise target-effective project identity/config, the real bundled OS
dependency, ordinary shared dependencies, native NIF compilation, version
changes without stale application resources, retained app data, and cold
boot with automatic services/queues but no manual declarations.

The external SDK smoke separately built/installed the public archive into
an isolated archive directory, generated a project outside this checkout,
ran its host tests, and packaged its native client source. A new temporary
RSA key signed a static mirror; only public registry bytes entered the
guest. Installing the client by name built `elixos_demo_stats`, the native
measurement journal and the client inside Elixos. Its OS-only module called
the real OS/data-directory API; the shared statistics module loaded from
`/priv/apps/elixos_demo_stats/ebin`.

After recording two measurements and a counter value, `Elixos.save/0`,
clean shutdown and a second cold boot restored counter 7, measurement count
2, mean 21.75 and prod/Elixos config. Linux 7.2.9 and Zig init were checked,
and installation left the shared VM's cwd/environment/Mix state unchanged.
Both guest shutdowns returned zero. This was actual guest runtime proof,
not host cross-compilation or a claim of successful health promotion.

The focused host package/image/restore/meta gate passed 115 tests; SDK,
portable statistics and demo gates passed 13, 3 and 6 respectively. The five
permanent native guest cases and the external SDK smoke passed together.
These were scoped results; the full M27 gate passed later (see below).

## Fly application proof

**A native Fly trial passed on 2026-10-22.** It deployed a runtime image built
by `mix elixos.image` through Fly's normal OCI image path. The receipt is the
local, uncommitted `fly-native-receipt.json` of that run.

| Item | Observed |
|---|---|
| Image | `linux/amd64`, entrypoint `/init`, pushed to a trial registry |
| Machine | one Machine in `iad`, 2 shared vCPUs, 2 GB RAM, `--ha=false` |
| Volume | one 1 GB encrypted Fly Volume `elixos_data` at `/priv` |
| Kernel | Fly's own `6.12.105-fly`; no custom kernel, QEMU, TCG or nested VMM |
| Init | Fly's init ran `/init` as a child; the shim supervised as subreaper |
| First boot | the seed initialized the fresh volume; generation 1, normal mode |
| HTTP | the app's own listener on `internal_port` 8080 served a public HTTPS health endpoint |
| State | two increments over HTTPS gave counter 2 and 2 SQL rows |
| Secret | a Fly secret was visible to the app; its SHA256 matched, and it was not in the image config |
| Restart | Machine restart with SIGTERM logged `beam exited status=0`, `shutdown poweroff` and `Main child exited normally with code: 0` |
| After restart | counter 2, 2 rows, generation 1, normal mode |

The trial used its own `fly.toml`: the checked-in
[`docker/fly.toml`](../docker/fly.toml) plus an app name, an
`[http_service]` on `internal_port = 8080` and a `GET /health` check. The
checked-in profile has no HTTP service by design. The HTTP service and its
health endpoint belong to the application, not to Elixos. The app, Machine,
volume and registry image were destroyed after the trial.

**Limits.** This is one Machine with one volume. It is not proof of high
availability, backups, volume snapshots, scaling, multi-region operation or
ARM64. A volume belongs to one Machine; it is not shared or replicated
storage. Fly does not apply Docker's read-only and tmpfs flags.

**Commit timing.** After the restart, the shim logged `attempt=2`, because
auto-commit had not yet committed the first boot. Repeated restarts inside the
30 s commit window can make the shim fall back to `last_good`. Let a
deployment run healthy for longer than that window before you restart it.

The [deployment guide](../hex/README.md#fly-native-oci-profile) gives the
commands and the profile settings.

## Writing tests

- Acceptance tests (the ones that came with the scaffold) are the contract.
  Do not weaken, skip or delete them; see AGENTS.md for the procedure when one
  is genuinely wrong.
- Add your own unit tests freely, red first, for the internals you build,
  and give them the milestone you are working on.
- Prefer behavior over implementation. Formats that are API (PROTOCOL.md, the
  journal record format, the store layout) may be asserted byte for byte.
- No sleeps where you can await a message. Where time is the subject
  (heartbeats, auto-commit), keep intervals short and margins wide.
- Async tests must not touch VM-global state: cwd, OS environment, registered
  names they do not own (ADR-016).

## Approvals and GUI gates (M27)

ADR-093 replaced the Ask queue with Oh-My-Jido approvals. The host tests are:

- `test/elixos/approvals_test.exs`: detached requests, explicit approval and
  denial, closed expiry and restart behavior (4 tests).
- `test/elixos/gui_dialog_test.exs`, `gui_keyboard_test.exs`,
  `gui_pointer_test.exs` and `emerge_render_test.exs`: dialog state, input and
  off-screen rendering of each request kind.

The QEMU acceptance is `test/integration/m27_gui_test.exs`. The machine boots
to IEx without the GUI, a real Oh-My-Jido question is pending, the GUI opened
from IEx shows it, and an injected key answers it. Then the waiting tool gets
the answer and the console comes back. `m27_native_tooling_test.exs` runs on
the same image.

```sh
cd os
ELIXOS_QEMU=1 ELIXOS_MILESTONE=27 mix test \
  test/integration/m27_gui_test.exs test/integration/m27_native_tooling_test.exs
```

These host tests and the two QEMU files (3 tests) passed on a rebuilt x86_64
image. The `demos/m27-gui` recording was redone on 2026-10-22, and
`make demo M=27` passes its key and graphics checks. On 2026-10-23 the full
`make ci` passed at `MILESTONE=27` (379 host tests, 57 QEMU tests, both
images, with the ARM64 renderer and factory cross-built per ADR-094) and
`make test-qemu-aarch64` passed.

## Candidate and Health host gates

The new host integration is scoped independently of the withdrawn M21–M24
OMP contract. `test/elixos/candidate_test.exs` builds real fixture and OS
source in separate ERTS processes, executes real ExUnit suites in child workers,
checks sentinel isolation, hostile OTP-origin message/fun/frame rejection
and counterfeit JSON receipt refusal, rejects invalid/stale candidates, round-trips
provenance, and exercises normal Image/NEXT protocol writes only against an
isolated process sink. Its stored-byte corruption and return-to-parent cases
are temporary-file tests, not authorization for guest fault injection.

`test/elixos/health_test.exs` checks named error/exception aggregation, empty
suite rejection, durable results and default Health-based AutoCommit refusal.
Generation tests cover optional provenance and existing version-one manifests.
Normal host checks include all these tests at the active M27 gate.

Child validation excludes QEMU provisioning and `:host_orchestration` only.
The Candidate orchestration suite and the existing second-Mix-build target
suite carry that tag to avoid recursive build/dependency provisioning inside
health. Their assertions still run in the normal host gate. Runtime SSH
acceptance remains included; its synthetic client keys are generated by OTP
instead of requiring an unshipped `ssh-keygen` executable. No retained
runtime assertion is relaxed.

Factory packaging includes source, tests, fixtures, MILESTONE, shared vectors
and ExUnit, not host dependency caches or the fixture's private signing input.
Missing assets fail health closed. Rebuild images before any separately
approved disposable-guest promotion/fallback demonstration; host protocol
sink success proves only a write, not a shim acknowledgment or sealing.

## Approved native coding factory and disposable T10

ADR-084 adds source-pinned native Oh-My-Jido packaging, not the withdrawn OMP
milestones. `test/elixos/coding_factory_test.exs` runs the actual source
stager against the canonical checkout, checks exact licensed/privacy-patched
source bytes and checksums, excludes host artifacts, refuses a changed tree
under its old pin, and compares the selected pure-BEAM closure against both
authoritative locks. It is host orchestration, not a recursive guest health
build. Candidate tests additionally reject post-test manifest/provenance/boot
policy replacement and distinguish verified stored bytes from actually loaded
generation code. These assertions were added without running them here.

Parent-owned focused commands, from `os/`, after resolving the new checked-in
lock with the approved canonical source:

```
ELIXOS_OH_MY_JIDO_SOURCE=/home/autark/src/oh_my_jido mix deps.get --check-locked
ELIXOS_OH_MY_JIDO_SOURCE=/home/autark/src/oh_my_jido mix test test/elixos/candidate_test.exs test/elixos/health_test.exs test/elixos/coding_factory_test.exs
```

The native factory uses its own OTP 29.1.1 / Elixir 1.20.4, verifies that
dependency resolution did not alter the OS lock, and records exact selected
source and target BEAM/application identities under `/factory/coding`.
It installs the real host adapter as an ordinary OTP package against the
complete OS, not the reduced host-test application. Mix, ExUnit, portable
tests and fixture/vector assets remain included.

The canonical `oh_my_jido/examples/elixos/README.md` documents exact pinned
image commands, a separate sparse disposable disk (never the default disk),
four packaged guest entrypoints and evidence paths. Candidate build, test and
propose each wait for a separate Oh-My-Jido approval, which the human answers
through `Elixos.Approvals`. Only the human reboots;
only default live-image Health and AutoCommit may COMMIT. Normal last-good
fallback is exercised by a benign non-protected userland boot-MFA exception,
not byte corruption or protected-module mutation.

Native scripted ReAct is explicitly the no-network model boundary of this
guest scenario; all file edits, suites, provenance, NEXT, boot and session
continuity are real. A `:guest_postconditions_verified` return still requires
the parent to match the actual serial attempt/exception/fallback/commit lines,
shim-owned boot.state/sealing and no kernel panic. No guest execution or
quality gate is claimed by these source changes. Actual provider coding proof
and F05/T9 target-native QuickBEAM/Python packaging remain separate requirements.



## Optional target-native Eval gates (ADR-092)

Source implementation is in the separate `ELIXOS_EVAL_PROFILE=1` native
melange/apko profile; the default factory/locks remain pure BEAM. The profile
requires its own output directory and explicitly reviewed `pin-eval` source
hash. It packages target QuickBEAM/OXC native libraries and the canonical
private-diagnostics Snakepit/Python SDK plus pinned CPython 3.14 wheels.
Source changes alone do not verify either Linux architecture.

The parent owns all builds, quality checks, image/disk effects and actual
guest execution. [The optional Eval operations guide](notes/coding-eval.md)
provides precise prerequisites, both architecture commands, no-default-disk
guards, actual native receipt paths and the real IEx smoke entrypoint.
The smoke must run on each normal no-NIC target, not the host's OTP 28.
Each language must retain two cells, execute and deny a real workspace Read
tool, enforce output/deadline quotas, cancel a live callback, survive actual
native worker termination, require explicit reset and confirm cleanup.
Only complete success writes an architecture-bound `verified.json` plus
actual SHA256 sidecar; no missing backend or mock/provider result can pass.
Retain both serial/no-panic transcripts, native/input/BEAM/image receipts and
exact optional apko locks/SBOMs before claiming F05/E01–E07 verified.
No build, test, linter, formatter, guest or disk operation was run while
implementing this packaging assignment.

## How the scaffold's tests were checked

Before the original scaffold shipped, its pure tests ran against a throwaway
reference implementation that was then deleted: 37/37 Zig tests on Zig
0.18.0-dev.131+41f885830, 159/159 ExUnit tests on OTP 29.1.1 / Elixir 1.20.4,
repeated with random seeds. Mutation spot checks confirmed the vectors catch
a lenient parser. The QEMU and disk helpers drove a real 7.2.9 boot of a probe
`/init`, and the console functions (`iex/3`, `await_log/3`, the Ctrl-G flow)
drove a real IEx 1.20.4 on a pty.

Those historical counts are not a claim that every later acceptance test had
an independent reference implementation. Later milestones record reference
limitations in their moduledocs; some notes describe the state when the tests
were authored, before their implementation landed. Delivered milestones have
their exercised acceptance recorded in ROADMAP.md. Suspect implementation
first, but use AGENTS.md's ADR procedure for a demonstrated test defect.
