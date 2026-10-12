# Elixos

[![A module defined in IEx survives a power cycle](demos/readme-live-image.gif)](demos/m06-live-image.mp4)

[Watch the recording](demos/m06-live-image.mp4) · [All demos](demos/README.md)

**The Elixir operating system.** An unmodified mainline Linux kernel boots a
tiny Zig PID 1 shim, which runs the BEAM and drops you at `iex(1)>`. IEx is the
default shell; a POSIX shell exists for tooling. Programs are packages,
commands are functions, and the running system is a live image you can save.

For shipping living Elixir apps as well as personal machines: USB sticks,
cyberdecks and SBCs. Images are built from pinned Alpine packages for
**x86_64 and aarch64**.

## Status

**M1–M20, M25 and M26 are landed:** live generations and recovery, on-box Mix
builds, SSH, UEFI boot, trusted Hex packages, Jido agents, package-built images,
an unprivileged BEAM with sealed commits, PostgreSQL, persistent Oban jobs,
the Ask question queue, a headless browser, Rust tooling, and installed packages
resolved as Mix dependencies.

**In progress:** the framebuffer GUI (M27). Emerge is a dependency; the dialogs,
framebuffer integration and input handling are not implemented yet.

**Deferred:** the coding-agent toolset, on-box coding agent, safe self-modification
and native hot paths (M21–M24), by [ADR-063](docs/DECISIONS.md).
See the [roadmap and acceptance criteria](docs/ROADMAP.md).

## Prior art and friends

- [Autolith](https://github.com/lambda-symbolics/autolith): image generations,
  rollback and recovery images, and the introspective self-modifying agent
  direction. That agent work is still ahead of us.
- [Nerves](https://nerves-project.org/) and its
  [erlinit](https://github.com/nerves-project/erlinit): a minimal PID 1 handling
  boot, mounts and shutdown while the BEAM owns application supervision.
- [AtomVM](https://github.com/atomvm/AtomVM): a lightweight VM bringing Erlang
  and Elixir to microcontrollers and other constrained devices.
- **Smalltalk and Lisp machine images:** a live world and a changes log.
  Elixos rebuilds from code and data rather than saving the BEAM heap
  ([ADR-005](docs/DECISIONS.md)).

## Build and test

`make check-tools` reports prerequisites; `make test` runs unit tests.
For focused iteration, `make check M=26` builds the host image and runs the
unit tests through M26 plus that milestone's QEMU acceptance.
`make ci` is the full gate: unit tests, the QEMU suite and both image builds;
`make test-qemu-aarch64` runs the separate ARM64 smoke test.
See [TESTING](docs/TESTING.md) for the test layers and [AGENTS.md](AGENTS.md)
for the development loop.

## Docs

- [VISION](docs/VISION.md): what Elixos is and is not
- [ARCHITECTURE](docs/ARCHITECTURE.md): boot chain, shim, live image, REPLs, apps, toolchain
- [PROTOCOL](docs/PROTOCOL.md): every interface that is API (tests match it byte for byte)
- [DECISIONS](docs/DECISIONS.md): ADRs and open questions
- [ROADMAP](docs/ROADMAP.md): milestones and their acceptance tests
- [TESTING](docs/TESTING.md): how the test layers, gating and QEMU harness work
