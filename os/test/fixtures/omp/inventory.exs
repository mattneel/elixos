# The OMP toolset inventory (M21, ADR-047): every tool the pinned OMP SDK's
# factories construct, recorded 2026-10-10 from the 18.8.7 reference -
#
#   src/tools/index.ts   BUILTIN_TOOLS (30) and HIDDEN_TOOLS (3)
#   src/sdk.ts           the settings-gated custom tools (generate_image, tts)
#
# MCP and extension tools are a user's configuration, not the toolset. Moving
# the pin is a note in docs/DECISIONS.md and re-recorded fixtures.
#
# Each tool is {name, origin, construction}:
#   origin        :builtin | :hidden | :settings
#   construction  :always     the factory always returns the tool
#                 :create_if  it returns null without its dependency or setting
#                 :settings   installed only while its setting is on
#
# No per-tool JSON fixtures exist yet. M21 must record them from this exact
# pin, including dependency/settings-gated availability rather than treating
# inventory membership as proof that a factory is available.
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
    version: "18.8.7",
    source: "https://github.com/can1357/oh-my-pi (packages/coding-agent)",
    integrity:
      "sha512-CRjlRS/CmWKXD67iXScvPssI0PzFIuWOdkSh8/lYk3OEb1gcRy09iBuP6xaoD1/BZnFkug9sXC7CiG8xxfgjqQ=="
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
    {"tts", :settings, :settings}
  ],
  # Tools that need a later milestone, and which one. Subagents are Jido agents
  # (M22), so `task` waits for the on-box agent; the rest go ahead in M21.
  waits: %{"task" => 22}
}
