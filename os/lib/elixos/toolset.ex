defmodule Elixos.Toolset do
  @moduledoc """
  The pinned OMP coding-agent toolset (M21, docs/ROADMAP.md, ADR-047).

  The dispatcher chooses an implementation before each call and records the
  implementation, revision and peer node that ran it. Initially the pure core
  runs in QuickBEAM in a supervised peer, with Elixir effects scoped to the
  calling session's workspace and M9 session directory.

  The per-tool choice is code in the generation, configured in
  `os/config/config.exs`, so every OS build loads the selection:

      config :elixos, Elixos.Toolset,
        implementations: %{"<tool>" => {:elixir, ImplementationModule}}

  The tuple's implementation is `:elixir` or `:native`; a tool absent from
  this map runs on `:quickbeam`. M24's `Elixos.Native.promote/1` and
  `Elixos.Native.revert/1` provide runtime overrides on top of this selection.

  The 18.10.1 catalog covers all 56 first-party tool IDs, including
  context-specific helper sessions (ADR-071). Membership never bypasses a
  dependency or settings gate; `task` waits for M22. Dynamic MCP and extension
  inventories remain session configuration.

  Differential replay compares recorded reference output/errors and effects
  exactly. Effectful calls execute once; shadow comparisons are pure only.
  """

  alias Elixos.Toolset.{Catalog, Host, Peer, Session}

  @tools ~w(read security_scan bash edit ast_grep ast_edit ask debug ida eval github
            glob grep find lsp checkpoint rewind context_notes new_context task wait
            todo web_search write memory_edit retain recall reflect learn manage_skill
            think yield goal generate_image tts init_experiment run_experiment
            log_experiment update_notes vibe_spawn vibe_send vibe_wait vibe_kill vibe_list
            advise git_overview git_file_diff git_hunk recent_commits analyze_files
            propose_changelog propose_commit split_commit rewrite approve security_publish)
  @waiting %{"task" => 22}

  @type implementation :: :quickbeam | :elixir | :native
  @type run_record :: %{
          tool: String.t(),
          implementation: implementation(),
          revision: String.t(),
          node: node()
        }

  @doc "Returns the pinned SDK's tool names in recorded inventory order."
  @spec inventory() :: [String.t()]
  def inventory, do: @tools

  @doc "Returns the tools waiting for a later milestone and their milestone numbers."
  @spec waiting() :: %{String.t() => pos_integer()}
  def waiting, do: @waiting

  @doc """
  Calls a tool with OMP parameters in the calling session's isolated tool host.

  `:session` (`Elixos.Toolset.Session`) is required; `:timeout` is the caller's
  deadline in milliseconds, separate from the SDK bash timeout in seconds.
  Losing the peer mid-call returns `{:error, :tool_host_down}` without replaying
  the interrupted call's effects. Unknown, unavailable and deferred tools
  return distinct errors. Calls never change the main VM's cwd or environment.
  """
  @spec call(String.t(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def call(tool, params, opts) do
    tool = canonical_name(tool)

    cond do
      tool not in @tools ->
        {:error, {:unknown_tool, tool}}

      Map.has_key?(@waiting, tool) ->
        {:error, {:tool_deferred, tool, @waiting[tool]}}

      true ->
        %Session{} = session = Keyword.fetch!(opts, :session)
        timeout = Keyword.get(opts, :timeout, Peer.quickbeam_options()[:timeout])
        selection = selected_backend(tool)

        case Peer.run(Host, :execute, [selection, tool, params, session, timeout], timeout) do
          {:ok, node, {result, revision}} ->
            Peer.record(%{
              tool: tool,
              implementation: backend_kind(selection),
              revision: revision,
              node: node
            })

            result

          {:error, _reason} ->
            {:error, :tool_host_down}
        end
    end
  end

  @doc """
  Returns the implementation the dispatcher will select for the next call.

  The generation's `os/config/config.exs` selects modules through
  `config :elixos, Elixos.Toolset, implementations: %{"<tool>" => {kind, module}}`,
  where `kind` is `:elixir` or `:native`; absent tools use `:quickbeam`.
  M24's `Elixos.Native.promote/1` and `Elixos.Native.revert/1` are runtime
  overrides on top of that generation configuration.
  """
  @spec implementation(String.t()) :: implementation()
  def implementation(tool), do: tool |> canonical_name() |> selected_backend() |> backend_kind()

  @doc "Returns the last run's provenance, or nil when the tool has not run."
  @spec last_run(String.t()) :: run_record() | nil
  def last_run(tool), do: tool |> canonical_name() |> Peer.last_run()

  defp selected_backend(tool) do
    :elixos
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:implementations, %{})
    |> Map.get(tool, :quickbeam)
  end

  defp backend_kind(:quickbeam), do: :quickbeam
  defp backend_kind({kind, _module}) when kind in [:elixir, :native], do: kind

  defp canonical_name(tool), do: Catalog.canonical_name(tool)
end
