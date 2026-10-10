# Jido on Elixos

Where the API and its conventions come from, and what the milestone has to
decide. The sketch is docs/ROADMAP.md's M15.

## The authority

`~/src/jido-skills` on the development host (github.com/agentjido/jido-skills)
is a set of Agent Skills for the Jido ecosystem. Read them before writing
milestone code, in this order:

- `source/skills/jido-core/SKILL.md` and its `reference/{agents,actions,directives}.md`
  — the ecosystem map and the conventions everything else assumes.
- `source/skills/jido-agent/SKILL.md` — `use Jido.Agent`, schemas, `cmd/2`,
  plugins, directives, and the AgentServer runtime.
- `source/skills/jido-action/SKILL.md` — `use Jido.Action`, `run/2`, and how
  actions become LLM tools.
- `source/skills/jido-ai/SKILL.md` — providers, `jido_ai` chat agents, and
  streaming through `req_llm`.
- `source/skills/jido-testing/SKILL.md` — testing agents and actions without
  OTP processes, which is how the unit tests here should work.

The packages: `jido`, `jido_action`, `jido_signal` (the framework) and
`jido_ai` + `req_llm` (providers). All are Hex packages, so they arrive through
the package manager this repo already ships (ADR-019, M14) rather than being
vendored.

## What Elixos adds, and what it does not

- An agent is a **user module**: the M6 image journals what a prompt defines
  and restores it at boot, so `jido` needs no new persistence. The interesting
  work is supervision: agents have to be started at boot (the answer to Q2:
  rebuild from supervisors and `/priv`), and an agent's state worth keeping
  belongs on the persistent disk, not in a heap snapshot.
- The LLM is a **provider, not the definition**. `req_llm` talks to a real
  provider when the machine has a network and a key; without either, an agent
  still runs — commands, actions and state do not need a model. Tests use a
  stubbed provider over the loopback, so the suite never needs an API key.
- The image is the point: "define an agent at the prompt, `Elixos.save()`,
  power off, and it is there next boot" is the same sentence as M6's live
  image, with `jido` in the middle. That is the flourish.

## What M15 turned out to require

**The closure, prebuilt.** Installing `jido` by name resolves 15 packages
(jido 2.4.0, jido_action, jido_signal, jason, crontab, fuse, multigraph,
nimble_options, nimble_parsec, poolboy, splode, telemetry, telemetry_metrics,
time_zone_info, zoi). Three are rebar projects and telemetry's rebar.config
needs the `pc` plugin, which rebar3 fetches from the network: the box cannot
build them yet. The fixture therefore ships the closure *built*
(`os/test/fixtures/hex_repo/build-jido.sh` compiles it on the host, packs
`ebin/` with Hex's own tarball writer, and adds it to the fixture repository);
`Elixos.Package.install/1` adopts a package that arrives built (ADR-033).
Telemetry's NIF is compiled for musl with the pinned zig - without it the
Erlang path still works, but a glibc `.so` would be a landmine.

**Modules a prompt defines.** The image journals module definitions through
the *session's* tracer (`Elixos.Boot.Recorder`). `Code.require_file/1` and
`Code.eval_string/3` (even with `__ENV__`) do *not* carry it, so modules that
arrive that way are never journaled and a "power cycle" loses them. What
works is what the M6 test does: one expression - several `defmodule`s wrapped
in `( ... )` - sent in a single `QEMU.iex/3` call, which is also one prompt
(several pasted expressions move the helper's prompt counter on without it,
the M14 lesson).

**A Jido agent's memory.** `Jido.AgentServer.state/1` carries the agent
struct, but its `__struct__` is `Jido.Agent` - passing a restored struct back
as `:agent` tells the server the module is `Jido.Agent`, and `strategy/0` is
then undefined. What is remembered is the *state map* (`state.agent.state`),
handed back as `initial_state`, with the module coming from the record.
Snapshots are written by `Elixos.Agents.snapshot_all/0`, which `Elixos.save/1`
and a graceful shutdown call (ADR-032).

**Loopback and the factory.** The kernel leaves `lo` down: the shim brings it
up with one ioctl (ADR-034), which is what lets an action reach a stub on
127.0.0.1. The factory also carries mnesia (jido's OTP dependency) and
ssl + inets with the machine's CA bundle (ADR-035), and the application puts
`/factory/lib/*/ebin` on the code path at boot.

**The sign-in.** `Elixos.Agents.LLM` is OTP only (`:gen_tcp`, `:ssl`, `:json`)
and speaks chat completions and the Responses API. Verified live with this
host's ChatGPT tokens: `complete/2` with `auth: :codex` and
`model: "gpt-5.6-luna"` returns real text. Two things cost a round trip: the
ChatGPT backend insists on `stream: true` (read the server-sent events), and
`%{auth: :codex}` as a function head does not match a keyword list. On this
development host the mix VM's code path does not include OTP's applications,
so `:ssl` has to be appended (`Code.append_path/1` at
`~/.local/share/mise/installs/erlang/29.1.1/lib/ssl-*/ebin`, and its
`public_key`/`asn1` siblings) before a hosted provider can be called from a
script; the guest gets the same applications from the factory.
