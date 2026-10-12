# The complete first-party OMP tool surface (M21, ADR-047/ADR-071), pinned to
# 18.10.1 / 90701813e5fba6919067848989378b4ee6239c13. Source evidence and the
# context-specific registry map are in docs/omp-inventory.json:
#
#   tools/index.ts       BUILTIN_TOOLS (30) and HIDDEN_TOOLS (3)
#   sdk.ts               image/TTS settings, autoresearch and vibe tools (11)
#   special sessions     advisor, commit, compression and security tools (12)
#
# Dynamic MCP/extension inventories remain user configuration, not new built-ins.
#
# Each tool is {name, origin, construction}:
#   origin        :builtin | :hidden | :settings | :runtime
#   construction  :always     the factory always returns the tool
#                 :create_if  it returns null without its dependency or setting
#                 :settings   installed only while its setting is on
#                 :session    supplied only in its declared runtime/session mode
#
# JSON fixtures are recorded from this exact pin, never from Elixos. A missing
# non-waiting tool still fails coverage; membership does not imply a factory's
# dependency/settings/context gates are satisfied.
# A fixture records `reference` (package/version/integrity), `coverage`, distinct
# absolute recorded `roots`, `workspace` and `session_dir` initial file maps,
# `params`, exactly one of `output` or `error` (kind/message), and `effects`
# containing complete final workspace/session_dir maps. Text values are literal
# bytes; {"base64": "..."} represents binary media. Only the two recorded roots
# are rebound for replay; output fields are never dropped. Edit fixtures record
# ordered successful `reads` (params plus exact output/error) that prime the same
# session's seen lines. Coverage includes nominal, Unicode, malformed input,
# numeric boundaries and payloads of at least 65,536 bytes. A numeric boundary
# records its params `path`, numeric `limit`, and `relation` (below/at/above).
# Expected outcomes/effects are recorded from the reference, never synthesized.
# Stateful tools may record `setup_calls` (tool/params plus exact outcome);
# prerequisites execute once in the same session before reads and the target.
%{
  reference: %{
    package: "@oh-my-pi/pi-coding-agent",
    version: "18.10.1",
    source: "https://github.com/can1357/oh-my-pi/tree/90701813e5fba6919067848989378b4ee6239c13",
    integrity:
      "sha512-xvHDKLcAsGvDwLQG6PHZEYiELQPKJ4NiSc/yeurja8IZkC7yALjR+2pbEiCT4cSdyIfEmHFDhDUze8hSxYpiZA=="
  },
  tools: [
    {"read", :builtin, :always},
    {"security_scan", :builtin, :always},
    {"bash", :builtin, :always},
    {"edit", :builtin, :always},
    {"ast_grep", :builtin, :always},
    {"ast_edit", :builtin, :always},
    {"ask", :builtin, :create_if},
    {"debug", :builtin, :create_if},
    {"ida", :builtin, :create_if},
    {"eval", :builtin, :always},
    {"github", :builtin, :create_if},
    {"glob", :builtin, :always},
    {"grep", :builtin, :always},
    {"find", :builtin, :always},
    {"lsp", :builtin, :create_if},
    {"checkpoint", :builtin, :create_if},
    {"rewind", :builtin, :create_if},
    {"context_notes", :builtin, :create_if},
    {"new_context", :builtin, :create_if},
    {"task", :builtin, :always},
    {"wait", :builtin, :always},
    {"todo", :builtin, :always},
    {"web_search", :builtin, :always},
    {"write", :builtin, :always},
    {"memory_edit", :builtin, :create_if},
    {"retain", :builtin, :create_if},
    {"recall", :builtin, :create_if},
    {"reflect", :builtin, :create_if},
    {"learn", :builtin, :create_if},
    {"manage_skill", :builtin, :create_if},
    {"think", :hidden, :always},
    {"yield", :hidden, :always},
    {"goal", :hidden, :always},
    {"generate_image", :settings, :settings},
    {"tts", :settings, :settings},
    {"init_experiment", :runtime, :session},
    {"run_experiment", :runtime, :session},
    {"log_experiment", :runtime, :session},
    {"update_notes", :runtime, :session},
    {"vibe_spawn", :runtime, :session},
    {"vibe_send", :runtime, :session},
    {"vibe_wait", :runtime, :session},
    {"vibe_kill", :runtime, :session},
    {"vibe_list", :runtime, :session},
    {"advise", :runtime, :session},
    {"git_overview", :runtime, :session},
    {"git_file_diff", :runtime, :session},
    {"git_hunk", :runtime, :session},
    {"recent_commits", :runtime, :session},
    {"analyze_files", :runtime, :session},
    {"propose_changelog", :runtime, :session},
    {"propose_commit", :runtime, :session},
    {"split_commit", :runtime, :session},
    {"rewrite", :runtime, :session},
    {"approve", :runtime, :session},
    {"security_publish", :runtime, :session}
  ],
  # Tools that need a later milestone, and which one. Subagents are Jido agents
  # (M22), so `task` waits for the on-box agent; the rest go ahead in M21.
  waits: %{"task" => 22}
}
