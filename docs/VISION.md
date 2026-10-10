# Elixos: the vision

**Elixos is the Elixir operating system.** An unmodified mainline Linux kernel
boots straight into IEx, and the BEAM is the entire userland. It works the way
you would expect an Elixir OS to work: you live inside one running system and
shape it from the prompt.

Think of it as the ultimate cyberdeck OS: a single-user machine you carry,
boot in seconds, and program while it runs.

## What "works the way you'd think" means

- **Power on, get a prompt.** Firmware runs the kernel, the kernel runs a
  tiny PID 1 shim, the shim runs the BEAM, and you land at `iex(1)>`.
  There is no login screen, no shell script, no `/bin/sh`.
- **REPLs are the shells.** Where other systems offer bash and sh, Elixos
  offers IEx, erl and gsh (Gleam). They are not separate worlds: a GenServer
  started from IEx is callable from erl a second later, because every REPL
  attaches to the same running VM. Ctrl-G job control switches between them.
- **A live image, like a Lisp machine or a Smalltalk image.** Define a module
  at the prompt, run `Elixos.save()`, power off; it is there after the next
  boot. Every definition is journaled the moment you make it, so nothing typed
  is ever lost, even unsaved work (`Elixos.unsaved/1`, `Elixos.recover/1`).
- **OS concepts are OTP concepts.** The supervision tree is the service
  manager. `Process.list/0` is `ps`. Logger is syslog. A crashed service
  restarts under its supervisor; a crashed or hung VM is restarted by the shim.
- **Recovery is IEx too.** A bad generation falls back to the last good one;
  if that fails too, you boot the pristine factory image in rescue mode, still
  at an IEx prompt, with tools to diff generations, replay the journal and
  bisect the change that broke things.
- **Self-hosting.** `mix`, Hex and a C toolchain (`zig cc`) run on the box.
  You can build and install a regular Elixir project, NIFs included, from the
  prompt.
- **Programs are packages, commands are functions.** Software comes from Hex
  repositories, the way other systems take packages from apt: add a repository
  with its public key, then `Elixos.Package.install(:name)`. A package does not
  ship a CLI — it exposes an Elixir API, and anything native it runs is exec'd
  directly with the session's working directory. Nothing is trusted because a
  URL was typed: adding a repository's key is the consent step.
- **Every session has its own working directory.** Two consoles, or a console
  and an SSH channel, can sit in different directories at the same time, while
  the VM's own working directory never moves (ADR-016).
- **Regular Elixir apps opt in.** A normal `mix.exs` can carry an `elixos:`
  key saying how it wants to be installed, and `config/elixos.exs` says how it
  behaves there (`MIX_TARGET=elixos`). The same project still builds anywhere.

## Principles

1. **Kernel and BEAM, nothing else.** The only foreign code at runtime is the
   unmodified mainline kernel and a few hundred lines of Zig in PID 1. Anything
   that can be Elixir is Elixir.
2. **Never patch the kernel.** We configure it; that is all (ADR-001).
3. **PID 1 is boring and tiny.** It mounts, supervises, records and recovers.
   It never parses anything richer than `key=value` and never dies (ADR-002).
4. **The image is code plus data, not a heap dump.** The BEAM cannot
   `save-lisp-and-die`, so the image is rebuilt from content-addressed module
   blobs, a journal and generation manifests at every boot (ADR-005).
5. **One VM is shared by everything.** Its working directory, environment and
   code path are global state; nothing may change them for everyone (ADR-016).
6. **Test-driven, milestone by milestone.** The whole vision already exists
   as tests in this repo; building Elixos means turning them green in order.

## Non-goals (for now)

- Multi-user. Elixos is single-user (ADR-013); a REPL is not a security boundary.
- Architectures other than x86_64 (ADR-014). aarch64 is a later decision.
- POSIX compatibility or running arbitrary Linux binaries.
- Being Nerves. Nerves is excellent appliance firmware: Buildroot, read-only
  root, A/B updates, you work on the host. Elixos is the opposite: a machine
  you live inside. We borrow ideas freely (erlinit's PID 1 chores, Toolshed's
  REPL helpers) but not the model.
- A heap-level snapshot. CRIU could checkpoint `beam.smp` on mainline, but it
  is a heavy C dependency and fragile around devices; it stays a stretch goal.

## Where this runs

Development happens on WSL2 with QEMU, driven by a coding agent working
through docs/ROADMAP.md. The target is a cyberdeck-style x86_64 machine booting
through UEFI straight into the kernel's EFI stub, with the console on its own
screen in a big Terminus font.
