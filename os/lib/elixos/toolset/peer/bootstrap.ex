defmodule Elixos.Toolset.Peer.Bootstrap do
  @moduledoc """
  The peer-side half of the tool-host lifecycle (M21, ADR-047).

  Runs inside the peer node started by `Elixos.Toolset.Peer`, never in the main
  VM. The main VM calls `start/0` over `:erpc` once the peer is up; the peer is
  handed out only after that call succeeded, so its QuickBEAM application is
  already running and `QuickBEAM.ContextPool`/`QuickBEAM.Context` can be
  started there immediately.

  The release ships the engine without loading its application specification.
  This bootstrap loads and starts it only in the peer (ADR-047); otherwise
  Jido discovery would load its NIF in the main VM even if the app stayed
  stopped. `ensure_all_started/1` is idempotent.

  Nothing here touches the main VM: no application state, no environment, no
  code path.
  """

  @engine :quickbeam

  @doc """
  Starts the JavaScript engine's OTP applications in this (peer) node.

  Returns `:ok` when `:quickbeam` and the applications it needs are running and
  the engine's NIF module is loaded in this node, `{:error, reason}` otherwise.

  The NIF module is loaded on purpose: the whole point of the bootstrap is that
  a broken or missing engine addon fails the peer before a caller can hand it a
  context to run.
  """
  @spec start() :: :ok | {:error, term()}
  def start do
    with {:ok, _apps} <- Application.ensure_all_started(:elixir),
         {:ok, _apps} <- Application.ensure_all_started(@engine),
         {:module, _module} <- Code.ensure_loaded(QuickBEAM.Native),
         :ok <- start_host() do
      :ok
    end
  end

  defp start_host do
    case Supervisor.start_child(QuickBEAM.Supervisor, {Elixos.Toolset.Host, []}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
