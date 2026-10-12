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

`make test` runs the two unit layers. `make ci` runs those tests, the
non-aarch64 QEMU suite and both architecture image builds; it does **not**
run the ARM64 smoke test or the manual hardware checklist.

For iteration on the current work, `make check M=27` builds the host image,
runs the Zig and ExUnit host suites through M27, then only
`test/integration/m27_*.exs`. Use the full `make ci` at the milestone boundary,
not after every edit. `make check M=26` can verify the completed baseline while
M27's ARM64 packaging and full gate are still in progress.

## Milestones

`MILESTONE` selects the active gate, including a milestone whose implementation
is still in progress. It is not a count of completed milestones. M27 is active;
M1–M20, M25 and M26 are delivered; M21–M24 remain deferred under ADR-063.

- **Zig:** every test begins `try milestone.require(N);`, which returns
  `error.SkipZigTest` until `MILESTONE >= N`. The Makefile passes
  `-Dmilestone=$(cat MILESTONE)`.
- **ExUnit:** every test module has `@moduletag milestone: N`;
  `os/test/test_helper.exs` excludes later milestones. `os/test/meta_test.exs`
  fails if a test module forgets the tag.
- **Overrides:** `ELIXOS_MILESTONE=N` selects the ExUnit gate for a direct
  `mix test` command; `make check M=N` passes the selection to both host
  test layers and its integration run.
- **Deferrals:** `:deferred` tests are excluded in both modes (ADR-063).
  Increasing `MILESTONE` does not enable M21–M24.
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
(ADR-018). The current `melange/shim.yaml` image recipe explicitly enables
them, including the initramfs embedded by the UEFI script. A separate
hook-free deployment-image target is not implemented yet.
The hooks let tests reach otherwise awkward states: a plan without a launch,
or a shim panic. `make shim` and `make release-shim` are not current targets.

**Debugging a boot.** `make qemu ARGS="elixos.safe"` boots interactively on
your terminal (Ctrl-A X quits). A failing expectation prints the last 4 KB of
the console.

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
