defmodule Elixos.Coder do
  @moduledoc """
  The on-box coding agent (M22, docs/ROADMAP.md; ADR-048).

  A Jido agent owns model turns, M21 tool calls and M20 questions. Subagents
  run under `Elixos.Coder.Supervisor`, a DynamicSupervisor. Each session has
  its own workspace and M9 session directory; neither the VM cwd nor its
  environment moves. The prompt and selected tools belong to the generation,
  while project instructions come from the workspace's `AGENTS.md`.
  """

  @doc """
  Runs a task until the model yields, returning its result and ordered transcript.

  Options are `:workspace`, `:model` (a keyword list of `:base_url`, `:model`
  and `:credential`, the provider name). All calls use `Elixos.Toolset`.
  Host acceptance tests use temporary workspaces; on-box workspaces live under
  `/priv/work/`. Transcript entries
  include `:role` and `:tool` (a name or nil), never credential values.
  """
  @spec run(String.t(), keyword()) ::
          {:ok, %{result: String.t(), transcript: [map()]}} | {:error, term()}
  def run(_task, _opts), do: Elixos.NotImplemented.raise!(22, "Elixos.Coder.run/2")

  @doc "Starts an interactive session tied to the caller's group leader."
  @spec start(keyword()) :: {:ok, pid()}
  def start(_opts), do: Elixos.NotImplemented.raise!(22, "Elixos.Coder.start/1")

  @doc "The system prompt stored in the running generation, not a working copy."
  @spec system_prompt() :: String.t()
  def system_prompt, do: Elixos.NotImplemented.raise!(22, "Elixos.Coder.system_prompt/0")

  @doc "The SHA-256 hex digest over the generation's prompt and tool selection."
  @spec prompt_hash() :: String.t()
  def prompt_hash, do: Elixos.NotImplemented.raise!(22, "Elixos.Coder.prompt_hash/0")
end
