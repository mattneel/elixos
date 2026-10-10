# Elixos

**The Elixir operating system.** An unmodified mainline Linux kernel boots a
tiny Zig PID 1 shim, which runs the BEAM, which drops you at `iex(1)>`. No
shell, no userland but Erlang/OTP: REPLs are the shells, the supervision tree
is the service manager, and the system is a live image you shape from the
prompt and save across power cycles, like a Lisp machine. Single user,
x86_64, built for a cyberdeck.

```
iex(1)> defmodule Hello, do: def(hi, do: :persisted)
iex(2)> Elixos.save()
{:ok, 1}
iex(3)> Elixos.reboot()
...
iex(1)> Hello.hi()
:persisted
```

## Status

This repository is a test-first scaffold. The whole vision exists as tests,
gated by milestone; the implementation is built by working through
[docs/ROADMAP.md](docs/ROADMAP.md) with a coding agent. Instructions for the
agent are in [AGENTS.md](AGENTS.md).

Current milestone: see `MILESTONE` (0 = harness only).

## Quick start (WSL2 Ubuntu 24.04 or any x86_64 Linux)

```sh
sudo apt install build-essential flex bison bc libelf-dev libssl-dev cpio \
  qemu-system-x86 e2fsprogs mtools ovmf openssh-client
scripts/install-zig.sh            # Zig master, pinned in .zig-version
asdf install                      # or mise: OTP 29.1.1, Elixir 1.20.4
make check-tools
make test                         # green at milestone 0
make kernel                       # builds the pinned mainline kernel once
git init && git add -A && git commit -m "Elixos scaffold"   # the agent commits per milestone
```

## Docs

- [VISION](docs/VISION.md): what Elixos is and is not
- [ARCHITECTURE](docs/ARCHITECTURE.md): boot chain, shim, live image, REPLs, apps, toolchain
- [PROTOCOL](docs/PROTOCOL.md): every interface that is API (tests match it byte for byte)
- [DECISIONS](docs/DECISIONS.md): ADRs and open questions
- [ROADMAP](docs/ROADMAP.md): milestones M1-M13 and their acceptance tests
- [TESTING](docs/TESTING.md): how the test layers, gating and QEMU harness work
