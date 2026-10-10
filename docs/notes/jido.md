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
