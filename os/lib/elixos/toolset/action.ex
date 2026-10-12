defmodule Elixos.Toolset.Action do
  @moduledoc """
  The Jido adapter over the pinned OMP toolset (M21, ADR-047).

  One call runs exactly one OMP tool through `Elixos.Toolset.call/3` — the
  generation's dispatcher, which selects the backend, executes inside the
  supervised tool peer's budgeted QuickBEAM context and records the
  implementation, revision and node. This module adds no execution path of its
  own.

  ## Raw arguments, upstream validation

  `arguments` is forwarded verbatim. No key is converted or atomized, no value
  is coerced and Jido does not validate them: the pinned upstream validator
  (`validateAgentToolArguments/2` inside the peer) is the only authority that
  shapes an OMP call, and the raw map reaches it unchanged. The envelope schema
  below only proves that a tool name and an argument object were supplied.

  ## The OMP envelope is not Jido's envelope

  Jido's stock `Jido.Action.Tool` adapter is deliberately *not* used: it
  converts parameter keys and re-encodes results and errors into JSON
  `%{"error" => binary}` payloads, which is not the OMP envelope. Raw OMP values
  are preserved here instead:

  * `run/2` returns `Elixos.Toolset.call/3`'s value unchanged on success and
    `{:error, reason, {:omp_raw, reason}}` on failure — the Jido `directive`
    element carries the untouched term (see `t:Jido.Exec.exec_result/0`).
  * `execute/3` is the boundary callers should use. It runs the action through
    `Jido.Exec.run/4` with `max_retries: 0` and restores the exact
    `{:error, reason}` term, because Jido's exec layer would otherwise normalize
    every non-exception failure into `Jido.Action.Error.ExecutionFailureError`.
    Jido's own failures (parameter validation, dispatch timeouts, crashes) are
    real exceptions and pass through unchanged.

  ## No retry, no replay

  Effects are never replayed. `max_retries: 0` is forced, so a default retry
  cannot re-issue an OMP effect after a failure or a lost peer, and
  `timeout: 0` disables Jido's dispatch timeout: the deadline belongs to the
  dispatcher's `:timeout` option, which bounds the peer call itself.
  """

  use Jido.Action,
    name: "omp_tool",
    description: "Execute one revision-pinned OMP tool through Elixos.Toolset.call/3",
    schema: %{
      "type" => "object",
      "properties" => %{
        "tool" => %{
          "type" => "string",
          "description" =>
            "OMP tool ID (Elixos.Toolset.Catalog.names/0, canonical or legacy alias)"
        },
        "arguments" => %{
          "description" =>
            "Raw arguments, including malformed JSON values; only the upstream validator may normalize them"
        }
      },
      "required" => ["tool", "arguments"],
      "additionalProperties" => false
    }

  alias Elixos.Toolset.Catalog

  @typedoc "Context keys the action reads."
  @type context :: %{
          required(:session) => Elixos.Toolset.Session.t(),
          optional(:timeout) => timeout()
        }

  @doc """
  Executes `tool` with `arguments` once, without retry, and returns the OMP
  envelope exactly.

  `context` carries the calling `Elixos.Toolset.Session` (`:session`) and the
  caller's deadline in milliseconds (`:timeout`, optional; the dispatcher's own
  peer deadline is the default). The result is `{:ok, result}` with the upstream
  result map, or `{:error, reason}` with the upstream error map or dispatcher
  error (`:unknown_tool`, `:tool_deferred`, `:tool_host_down`).

  `:max_retries` and `:timeout` are forced to `0` after any caller options:
  an OMP effect must not be replayed, and Jido must not time out a call that
  the dispatcher's deadline already bounds.
  """
  @spec execute(String.t(), term(), context(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(tool, arguments, context, opts \\ []) when is_binary(tool) do
    {action, params} =
      case is_map(arguments) && Catalog.dispatch_module(tool) do
        nil -> {__MODULE__, %{"tool" => tool, "arguments" => arguments}}
        false -> {__MODULE__, %{"tool" => tool, "arguments" => arguments}}
        module -> {module, arguments}
      end

    run_opts = Keyword.merge(opts, max_retries: 0, timeout: 0)

    case Jido.Exec.run(action, params, context, run_opts) do
      {:error, _normalized, {:omp_raw, reason}} -> {:error, reason}
      other -> other
    end
  end

  @doc """
  The Jido.Action callback.

  A success returns the upstream result map; a failure returns the upstream or
  dispatcher error term in both the reason and the directive element, so the
  raw envelope survives `Jido.Exec` without being re-encoded. Use
  `execute/3` when the plain `{:ok, result} | {:error, reason}` shape is wanted.
  """
  @impl Jido.Action
  def run(%{"tool" => tool, "arguments" => arguments}, context)
      when is_binary(tool) do
    case context do
      %{session: %Elixos.Toolset.Session{} = session} ->
        case Elixos.Toolset.call(tool, arguments, session: session, timeout: timeout(context)) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason, {:omp_raw, reason}}
        end

      %{} ->
        {:error, {:missing_session, Map.keys(context)},
         {:omp_raw, {:missing_session, Map.keys(context)}}}
    end
  end

  def run(params, _context) do
    {:error, {:invalid_omp_call, params}, {:omp_raw, {:invalid_omp_call, params}}}
  end

  @doc "The catalog descriptor of a tool, available to callers that route on names."
  @spec descriptor(String.t()) :: map() | nil
  def descriptor(tool), do: Catalog.descriptor(tool)

  @doc "The pinned upstream wire schema a tool's default variant carries."
  @spec schema(String.t()) :: map()
  def schema(tool), do: Catalog.default_schema(tool)

  @doc "The catalog's canonical, alias-aware tool enumeration."
  @spec names() :: [String.t()]
  def names, do: Catalog.names()

  defp timeout(%{timeout: timeout}) when is_integer(timeout) and timeout > 0, do: timeout
  defp timeout(_context), do: Elixos.Toolset.Peer.quickbeam_options()[:timeout]
end
