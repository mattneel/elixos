# Upstream OMP inventory and Jido port map

Source: [canonical Oh-My-Pi 18.10.1](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/package.json),
commit [`90701813e5fba6919067848989378b4ee6239c13`](https://github.com/can1357/oh-my-pi/commit/90701813e5fba6919067848989378b4ee6239c13).
The isolated reference checkout is `build/upstream/oh-my-pi`; the human's
`oh-my-pi`, `clanklet` and unfinished `live_gpui` checkouts were not changed.

This is a complete source inventory and decided port map, **not a claim that
the Elixos port or differential parity is finished**. [ADR-071](DECISIONS.md)
removes the former clanklet dependency and resumes M21–M24.

The [machine-readable manifest](omp-inventory.json) is authoritative for every
entry: exact source paths and line ranges, factory/consumer, arguments and
schema variants, activation gates, results/errors, effects, dependencies,
source-inspected tests, asset bytes/SHA-256 and the Jido target. No upstream
user configuration, credentials, installed MCP tools or external skill-library
contents are invented.

## Coverage

| Surface | Entries |
|---|---:|
| Builtin factories | 30 |
| Hidden factories | 3 |
| Primary SDK/settings/mode additions | 11 |
| Advisor/commit/compression/security-session tools | 12 |
| Tool schema variants | 86 |
| Production prompt/template assets | 351 |
| Research/benchmark/test/preview assets | 37 |
| Inline/generated prompt surfaces | 47 |
| Repository-local authoring skills | 3 |
| Skill fixtures | 20 |
| Runtime contracts | 35 |
| URI/protocol contract rows | 19 |
| Eval helper groups | 14 |

Production assets include one terminal-only commit confirmation template;
it is explicitly not a model instruction. The per-file manifest separates
all non-production assets instead of silently counting them as shipped prompts.
Runtime helper groups and URI contract rows are not counts of individual
functions or registered schemes.

## Tools, one by one

The factory maps, enabled/active set and exposed provider presentation are
separate layers. A `createIf` factory may return null; inventory membership
never bypasses its dependency/settings gate. Preserve those gates.
The primary SDK also adds autoresearch tools; vibe mode owns an ephemeral
registry. Advisor, commit, compression and security sessions have their own
rosters, not additions to every ordinary coding session.

`xd://` mounts, Code Mode, MCP/RPC/kernel bridges and response-only schemas
are recorded separately in `tools.supplemental_surfaces`. They are not extra
copies of the underlying builtin tool. The canonical legacy alias
`search` → `grep` is recorded; unknown custom-name case is preserved.

Targets below are the selected module boundaries for the port, not modules
that already exist. Each tool's full schema variants and effect/error
requirements remain in the manifest; a short descriptor is not its contract.

| Tool | Context | Jido Action target | Source |
|---|---|---|---|
| `read` | builtin | `Elixos.Toolset.Actions.Read` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L552-L555) |
| `security_scan` | builtin | `Elixos.Toolset.Actions.SecurityScan` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L554-L556) |
| `bash` | builtin | `Elixos.Toolset.Actions.Bash` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L555-L557) |
| `edit` | builtin | `Elixos.Toolset.Actions.Edit` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L556-L558) |
| `ast_grep` | builtin | `Elixos.Toolset.Actions.AstGrep` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L557-L559) |
| `ast_edit` | builtin | `Elixos.Toolset.Actions.AstEdit` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L558-L560) |
| `ask` | builtin | `Elixos.Toolset.Actions.Ask` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L559-L561) |
| `debug` | builtin | `Elixos.Toolset.Actions.Debug` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L560-L562) |
| `ida` | builtin | `Elixos.Toolset.Actions.Ida` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L561-L563) |
| `eval` | builtin | `Elixos.Toolset.Actions.Eval` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L562-L564) |
| `github` | builtin | `Elixos.Toolset.Actions.Github` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L563-L565) |
| `glob` | builtin | `Elixos.Toolset.Actions.Glob` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L564-L566) |
| `grep` | builtin | `Elixos.Toolset.Actions.Grep` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L565-L567) |
| `find` | builtin | `Elixos.Toolset.Actions.Find` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L566-L568) |
| `lsp` | builtin | `Elixos.Toolset.Actions.Lsp` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L567-L569) |
| `checkpoint` | builtin | `Elixos.Toolset.Actions.Checkpoint` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L568-L570) |
| `rewind` | builtin | `Elixos.Toolset.Actions.Rewind` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L569-L571) |
| `context_notes` | builtin | `Elixos.Toolset.Actions.ContextNotes` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L570-L572) |
| `new_context` | builtin | `Elixos.Toolset.Actions.NewContext` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L571-L573) |
| `task` | builtin | `Elixos.Toolset.Actions.Task` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L572-L574) |
| `wait` | builtin | `Elixos.Toolset.Actions.Wait` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L573-L575) |
| `todo` | builtin | `Elixos.Toolset.Actions.Todo` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L574-L576) |
| `web_search` | builtin | `Elixos.Toolset.Actions.WebSearch` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L575-L577) |
| `write` | builtin | `Elixos.Toolset.Actions.Write` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L576-L578) |
| `memory_edit` | builtin | `Elixos.Toolset.Actions.MemoryEdit` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L577-L579) |
| `retain` | builtin | `Elixos.Toolset.Actions.Retain` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L578-L580) |
| `recall` | builtin | `Elixos.Toolset.Actions.Recall` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L579-L581) |
| `reflect` | builtin | `Elixos.Toolset.Actions.Reflect` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L580-L582) |
| `learn` | builtin | `Elixos.Toolset.Actions.Learn` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L581-L583) |
| `manage_skill` | builtin | `Elixos.Toolset.Actions.ManageSkill` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L582-L584) |
| `think` | hidden | `Elixos.Coder.Actions.Think` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L585-L589) |
| `yield` | hidden | `Elixos.Coder.Actions.Yield` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L585-L589) |
| `goal` | hidden | `Elixos.Coder.Actions.Goal` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/index.ts#L585-L589) |
| `generate_image` | SDK settingsGatedCustomEntries | `Elixos.Toolset.Actions.GenerateImage` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/sdk.ts#L3432-L3475) |
| `tts` | SDK settingsGatedCustomEntries | `Elixos.Toolset.Actions.Tts` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/sdk.ts#L3432-L3475) |
| `init_experiment` | SDK inline createAutoresearchExtension | `Elixos.Coder.Research.Actions.InitExperiment` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/sdk.ts#L2593-L2624) |
| `run_experiment` | SDK inline createAutoresearchExtension | `Elixos.Coder.Research.Actions.RunExperiment` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/autoresearch/index.ts#L31-L123) |
| `log_experiment` | SDK inline createAutoresearchExtension | `Elixos.Coder.Research.Actions.LogExperiment` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/autoresearch/index.ts#L31-L123) |
| `update_notes` | SDK inline createAutoresearchExtension | `Elixos.Coder.Research.Actions.UpdateNotes` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/autoresearch/index.ts#L31-L123) |
| `vibe_spawn` | SessionTools ephemeral vibe registry | `Elixos.Coder.Vibe.Actions.Spawn` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/sdk.ts#L4608-L4611) |
| `vibe_send` | SessionTools ephemeral vibe registry | `Elixos.Coder.Vibe.Actions.Send` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/vibe.ts#L40-L43) |
| `vibe_wait` | SessionTools ephemeral vibe registry | `Elixos.Coder.Vibe.Actions.Wait` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/vibe.ts#L45-L48) |
| `vibe_kill` | SessionTools ephemeral vibe registry | `Elixos.Coder.Vibe.Actions.Kill` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/vibe.ts#L50-L52) |
| `vibe_list` | SessionTools ephemeral vibe registry | `Elixos.Coder.Vibe.Actions.List` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/tools/vibe.ts#L54) |
| `advise` | Separate advisor agent loop, not primary toolRegistry | `Elixos.Coder.Advisor.Actions.Advise` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/advisor/advise-tool.ts#L16-L21) |
| `git_overview` | Dedicated commit-agent customTools | `Elixos.Coder.Commit.Actions.GitOverview` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/commit/agentic/tools/index.ts#L26-L53) |
| `git_file_diff` | Dedicated commit-agent customTools | `Elixos.Coder.Commit.Actions.GitFileDiff` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/commit/agentic/tools/index.ts#L26-L53) |
| `git_hunk` | Dedicated commit-agent customTools | `Elixos.Coder.Commit.Actions.GitHunk` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/commit/agentic/tools/index.ts#L26-L53) |
| `recent_commits` | Dedicated commit-agent customTools | `Elixos.Coder.Commit.Actions.RecentCommits` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/commit/agentic/tools/index.ts#L26-L53) |
| `analyze_files` | Dedicated commit-agent customTools | `Elixos.Coder.Commit.Actions.AnalyzeFiles` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/commit/agentic/tools/index.ts#L34-L45) |
| `propose_changelog` | Dedicated commit-agent customTools | `Elixos.Coder.Commit.Actions.ProposeChangelog` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/commit/agentic/tools/index.ts#L47-L51) |
| `propose_commit` | Dedicated commit-agent customTools | `Elixos.Coder.Commit.Actions.ProposeCommit` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/commit/agentic/tools/index.ts#L47-L51) |
| `split_commit` | Dedicated commit-agent customTools | `Elixos.Coder.Commit.Actions.SplitCommit` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/commit/agentic/tools/index.ts#L47-L51) |
| `rewrite` | Dedicated restricted compression session customTools | `Elixos.Coder.Compression.Actions.Rewrite` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/compress/protocol.ts#L23-L36) |
| `approve` | Dedicated restricted compression session customTools | `Elixos.Coder.Compression.Actions.Approve` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/compress/protocol.ts#L38-L42) |
| `security_publish` | Dedicated security review session publicationTool | `Elixos.Toolset.Security.Actions.Publish` | [factory](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/coding-agent/src/security/publication.ts#L26-L116) |

## Prompts, file by file

`prompts.assets` contains every production and separately classified ancillary
file, with its exact hash, byte length, consumer, variables, activation and
Jido layer. `prompts.inline_prompts` records the generated/inline surfaces;
copying only `src/prompts/system/system-prompt.md` would lose them.

Preserve these distinct mechanisms:

- The generated system blocks and trailing project/instruction context have an
  ordered assembly. SDK literal, template and fixed prompt replacements are
  different modes; a literal replacement does not inherit all default blocks.
- The shared renderer is the upstream Handlebars-compatible implementation in
  [`packages/utils/src/template.ts`](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/utils/src/template.ts#L1-L62),
  wrapped by [`prompt.compile/render`](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/packages/utils/src/prompt.ts#L533-L548).
  It uses `noEscape: true`, registered helpers/partials and post-render
  formatting. Do not substitute generic EEx interpolation and assume parity.
- Personality, model/tool inventory, memory, rules, subagent profiles,
  compaction/handoffs and isolated helper models are separate prompt inputs.
- Before-agent-start extension overrides chain in handler order. Slash prompt
  argument substitution, file commands, skill invocation and MCP prompt
  expansion have their own precedence and rendering boundaries.
- Native edit descriptions, embedded rule prompts, provider dialect prompts
  and helper-model templates outside `packages/coding-agent/src/prompts` are
  part of the source surface too.
- The terminal-only split confirmation remains a UI interaction, not a model
  system message.

`prompts.assembly`, `override_rules` and `template_loader` retain the exact
source-backed composition/override chain. Generation-owned prompt assets and
agent profiles map to `Elixos.Coder`; ephemeral request/session messages
remain session-scoped. The inventory is not a rewritten generic coding prompt.

## Skills, skill by skill

The repository ships authoring skills under `.omp/skills`; the published
coding-agent package does **not** bundle a default external skill library.
The remaining SKILL.md files are fixtures. Each fixture is retained and
classified in `skills.skills`, not installed as a production capability.

| Skill | Distribution | Jido target | Source |
|---|---|---|---|
| `semantic-compression` | Repository-local authoring skill; not npm-bundled | Generation-owned skill asset, loaded by the session skill registry | [SKILL.md](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/.omp/skills/semantic-compression/SKILL.md) |
| `system-prompts` | Repository-local authoring skill; not npm-bundled | Generation-owned skill asset, loaded by the session skill registry | [SKILL.md](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/.omp/skills/system-prompts/SKILL.md) |
| `tool-prompt-optimization` | Repository-local authoring skill; not npm-bundled | Generation-owned skill asset, loaded by the session skill registry | [SKILL.md](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/.omp/skills/tool-prompt-optimization/SKILL.md) |

Port the runtime, not just the three Markdown bodies:

- Discovery covers native, Skillshare, OMP plugins, Claude, Agent Plugins,
  Claude plugins, generic agents, Codex, OpenCode, GitHub, managed and custom
  providers. Preserve their path ordering, filtering and collision rules.
- Authored-provider, custom-override and isolated managed-fallback passes are
  distinct. Conventional skill parsing and strict Agent Plugin frontmatter
  validation intentionally do not accept identical metadata.
- Routing names/descriptions are frozen into a reader-gated session catalog;
  full instructions and referenced assets load on demand through `skill://`
  or explicit user invocation. Root relative assets at the skill directory.
- Preserve image ordering, invocation queues, context insertion and keyword
  activation; skill invocation is a user-attributed message, not a hidden
  model-authored instruction.
- Managed learning/skill mutation and Skillshare install/update/uninstall,
  integrity, store extraction and approval are separate stateful operations.
  Do not equate a downloaded skill with a trusted executable tool.
- Consolidated-memory playbooks are separately generated files, not ordinary
  discovered skill registrations.

`skills.discovery`, `validation`, `invocation`, `management`, `provider_sources`
and `tests` carry the full rules and source evidence, including deliberate
adapter/trust distinctions. Arbitrary installed user libraries are outside
this upstream snapshot, but their loader behavior is in scope.

## Runtime boundaries that the port must preserve

The complete runtime report is in `runtime` in the manifest. It records the
AgentTool result/stream/cancellation envelopes, ToolSession services,
scheduling/admission, retained-kernel ownership, journals/provenance,
subagent/workpool/goal lifecycles, native host ABI and provider credentials.
Consumer-visible contracts housed in TUI modules are not discarded as UI-only.

URI/protocol contract rows: `router_contract`, `url_filesystem`, `skill`, `rule`, `memory`, `agent`, `history`, `artifact`, `local`, `proc`, `cfg`, `ssh`, `security`, `vault`, `issue_pr`, `mcp`, `omp`, `xd`, `attachment_conflict`.

AST rewrite variants, LSP and DAP suboperations, edit seen-line/snapshot state,
binary/image content, process uncertainty and completed effects are recorded
explicitly. A tool-name shim is not a complete port. Differential/shadow work
must not execute filesystem/process/network effects twice, and cancellation
must not silently replay an uncertain call.

### Jido boundary decisions

- Use `Jido.Action` for the recorded callable targets and `Jido.Agent` for
  coding sessions and subagents; retain the supervised tool-host peer and
  resource limits in ADR-047.
- Preserve upstream JSON schemas **and upstream runtime validation**. The
  installed Jido 2.4.0 JSON-schema adapter passes schema maps through without
  validating parameter values. The standard tool adapter also normalizes
  known keys and serializes result/error payloads; those transformations are
  not automatically byte-compatible with OMP.
- Make effect execution/retry/cancellation explicit. Do not use default
  automatic Action retries to replay an OMP effect after failure or lost-peer
  completion. Preserve the original result/error envelope at the model boundary.
- Model credentials remain outside generations and logs. Session paths and
  subprocess environments are local; the main VM's cwd/environment never move.
- M23 uses child-ERTS build, isolated full portable/fixture validation,
  generation NEXT, reboot, real health and COMMIT or fallback (ADR-049).
  It never hot-loads agent-written working-tree code into the main VM.
- M24 promotes only after exact differential results and a concurrent
  dispatcher p99 win including conversion overhead; real native artifacts
  are content-addressed and crash-isolated (ADR-050).

## Verification actually exercised

- Fresh clone of canonical upstream and observed package/revision identity.
- Imported the **actual full builtin/hidden factory module** using the matching
  18.10.1 native addon. Its construction order agrees with the manifest.
- Executed canonical-name normalization, including the legacy alias and
  custom-name case behavior.
- Verified every prompt/template and skill path, distinct prompt paths, and
  recorded SHA-256 over literal source bytes.
- Executed the production skill-invocation template with Unicode, literal XML
  characters, asset-root binding and conditional user arguments.
- Executed a Jido schema-boundary probe: the schema remained identical and an
  integer still reached the Action despite its string-only JSON schema.
- Parsed the four complete structured reports and checked all runtime arrays.

Host checks used Bun 1.4.2 and Jido/Jido Action 2.4.0. The reference runtime
needed `bun install --frozen-lockfile --ignore-scripts`, upstream
`gen:tool-views`, and the version-matched `pi-natives-linux-x64` addon;
none of these steps rebuilt an Elixos kernel. Source-inspected test paths are
not passing test claims. Tool availability under external credentials,
servers, browser/desktop devices and target-native runtimes, and full
behavioral equivalence, remain for the port's conformance gate.

## Graphics scope

The human's `live_gpui` is **GPUI + LiveView via Rustler**, currently
smoke-tested and unfinished. [ADR-072](DECISIONS.md) records separate AMD
and NVIDIA hardware-accelerated image profiles with shared OS/LiveView/agent
code. This inventory neither changes that checkout nor replaces the current
Emerge framebuffer backend on the strength of a screenshot.

## Attribution

Upstream is MIT-licensed. The machine manifest retains its complete copyright
and permission notice and license digest; copied implementation, prompt and
skill material must retain that notice. [Original license](https://github.com/can1357/oh-my-pi/blob/90701813e5fba6919067848989378b4ee6239c13/LICENSE).
