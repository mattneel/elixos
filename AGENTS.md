# AGENTS.md

You are building **Elixos**, the Elixir operating system: an unmodified
mainline Linux kernel boots a tiny Zig PID 1 shim, which runs the BEAM, which
drops the single user at `iex(1)>`. The BEAM owns the userland. The vision
is in docs/VISION.md; read it once. This file is your operating manual.

## The loop

The roadmap already exists as tests, gated by the `MILESTONE` file
(docs/TESTING.md). Work in order except for explicit ADR-backed exceptions
(M20 is retired by ADR-093; M21–M24 are withdrawn by ADR-083). After M27 the
K230 cyberdeck track (M28–M33) comes first. `MILESTONE` is the active gate, not a claim
that every milestone up to it is complete.

0. If this is not a git repository yet, `git init` and commit everything as
   the baseline.
1. `cat MILESTONE` gives N. Read docs/ROADMAP.md, section MN. If N is
   unfinished, resume it; otherwise read the next non-deferred milestone.
2. `make test` (plus `make test-qemu` from M3 on) must be green. If it is not,
   fix that first.
3. Write the selected milestone into `MILESTONE`. Its acceptance tests now
   run and fail. Commit: `M<N>: start`.
4. Turn them green test-first: for each piece you need, write a small unit
   test (red), make it pass (green), refactor. Run `make test` constantly;
   use `make check M=N` for the focused host + QEMU gate during iteration.
5. Run the full `make ci` once at the milestone boundary. When it is green,
   tick the checklist in ROADMAP.md and commit: `M<N>: done`. Go back to 1.

## Hard rules

- **Never weaken an acceptance test** (anything shipped in `os/test/`,
  `shim/src/*.zig` test blocks, or `spec/`) to get green: no deleting,
  skipping, loosening regexes or raising timeouts to hide a hang. If you are
  convinced a test is wrong, add an ADR to docs/DECISIONS.md saying why, change
  the test in its own commit, and call it out in your summary. The original
  scaffold's pure tests were reference-checked; later additions record their
  reference limitations in moduledocs (docs/TESTING.md). Suspect your code first.
- **Never patch the kernel** (ADR-001). Change only its config fragments:
  `kernel/elixos.config` plus `kernel/config.<arch>`.
  `scripts/check-kernel-config.sh` must pass for the merged fragments.
- **PID 1 never exits** and never panics the kernel (ADR-002). `main` is
  `noreturn`.
- **IEx is the login shell; sh is tooling-only** (ADR-012, amended by ADR-041).
  BusyBox sh is permitted for builds. The shim execs binaries directly
  (`erlexec`, never a release's `bin/` scripts).
- **Never change the VM's cwd or environment** (ADR-016). Every program on
  Elixos shares one VM. Builds run in a child ERTS.
- **The shim's console lines and the control protocol are API**
  (docs/PROTOCOL.md). Tests match them byte for byte.
- **`spec/` vectors are shared** by the Zig and Elixir suites; change both
  sides together.
- **Programs are packages, commands are functions** (ADR-019). Hex repositories
  are the package sources and `/priv/hex/repos.exs` is the whole trust
  decision; nothing is installed from a repo whose key was not added first.
- **Each REPL session has its own working directory** (ADR-020), keyed by its
  group leader. Nothing changes the VM's cwd (ADR-016); native tools are exec'd
  with `cd:` set to the session's directory.
- x86_64 and aarch64 (ADR-041). Single user (ADR-013). No runtime deps in `os/`
  without an ADR.
- Unresolved questions and proposed ADRs in docs/DECISIONS.md belong to the
  human. Follow the proposed default and keep going; mention it in your summary.

## Zig (tracking master)

- The pinned nightly is in `.zig-version`; `scripts/install-zig.sh` installs
  it. If it has rotated off ziglang.org, bump `.zig-version` and
  `build.zig.zon`'s `minimum_zig_version` together, then fix what the compiler
  reports.
- **Compiler errors are the signal.** Read the error, fix exactly what it
  says, rebuild. Do not switch approaches because the compiler complained;
  there is usually one right fix.
- **The pinned std source is the authority, not your memory.** Before using
  any std API, grep `$(dirname $(which zig))/lib/std`. Master churns weekly;
  APIs already hit while writing this scaffold: `EnumSet.initEmpty()` is now
  `.empty`, `main` takes `std.process.Init.Minimal`, formatting goes through
  `std.Io.Writer` (`{q}` quotes strings, `{t}` prints tag names).
- **Lazy analysis hides breakage.** Zig only checks code that is referenced.
  Keep the `refAllDecls` test in `shim/src/main.zig` and add every new file to it.
- In the shim: raw `std.os.linux` syscalls, no libc, no allocation after
  startup, single-threaded.
- `zig build test -Dmilestone=N` runs unit tests on the host;
  `zig build -Drelease -Dtest-hooks=true` builds `zig-out/bin/init`.
  `@panic("TODO(Mx)")` stubs are fine: the build runner reports each crashed
  test and keeps going.

## Elixir

- OTP 29.1.1 and Elixir 1.20.4 (`.tool-versions`).
- Stubs raise `Elixos.NotImplemented` ("TODO(Mx)"). Replace them.
- Read the moduledocs before implementing: several record behavior verified
  on these exact versions (`Elixos.Image.Capture`, `Elixos.REPL`,
  `Elixos.Package.Spec`). They will save you hours.
- Every test module needs `@moduletag milestone: N`; QEMU tests also need
  `@moduletag :qemu` and live in `os/test/integration/` (`meta_test.exs`
  enforces both).

## Commands

| command | does |
|---|---|
| `make check-tools` | what is missing on this machine |
| `make test` | shim + Elixir unit tests for the current milestone |
| `make check M=27` | host tests through M27 + its QEMU file(s), after building the host image |
| `make test-qemu` | builds the host image and runs the non-aarch64 integration suite |
| `make test-qemu-aarch64` | builds both images and runs the separate ARM64 smoke test |
| `make ci` | host tests, the QEMU suite and both image builds; ARM64 smoke is separate |
| `make image` | the host architecture's packaged kernel, shim, initramfs, service image and disk |
| `make images` | x86_64 and aarch64 images |
| `make demo M=26` | record, render and check one milestone's demo |
| `make qemu ARGS="..."` | boot interactively; Ctrl-A X quits |
| `cd os && mix test path/to/test.exs:LINE` | one test (set `ELIXOS_MILESTONE` to override) |

QEMU picks its accelerator from the host: the helpers pass `-accel kvm -accel
tcg`, so with `/dev/kvm` (check `make check-tools`) boots take seconds, and
without it QEMU falls back to TCG - slower but fine. Raise
`ELIXOS_QEMU_SLOWDOWN` if boots time out.

## Map

```
MILESTONE            current milestone (an integer)
AGENTS.md            this file
docs/                VISION, ARCHITECTURE, PROTOCOL (API), DECISIONS (ADRs), ROADMAP, TESTING
kernel/              VERSION (kernel.org pin + sha256), elixos.config + config.<arch>
melange/             recipes for our APKs, including native aarch64 kernel/OTP cross-builds
apko/                rootfs + service-image configs, per-architecture lockfiles and public keys
build.zig            the shim's build; shim/src/*.zig is PID 1
spec/                golden vectors shared by both test suites
os/                  the Mix project: the Elixos userland (lib/) and every ExUnit test (test/)
hex/                 the official Hex repository (packages, signing key) and its README
demos/               scripted asciinema recordings, one per visible milestone
.github/workflows/   CI: the Hex repository's build and Pages deployment
os/test/integration/ QEMU acceptance tests, one file per milestone
scripts/             image (melange + apko), initramfs, disk, QEMU, UEFI image,
                     tool installs, kernel config guard and the acceptance audit
build/               outputs (gitignored)
```

When something takes long to figure out (cross-building OTP, a QEMU quirk),
write what you learned in `docs/notes/<topic>.md` so the next session starts
from there.
