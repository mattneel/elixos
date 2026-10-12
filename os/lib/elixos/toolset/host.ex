defmodule Elixos.Toolset.Host do
  @moduledoc """
  Peer-local tool execution and session-owned QuickBEAM contexts (M21).

  The peer bootstrap starts this process beneath QuickBEAM.Supervisor. Calls
  execute outside the keeper's mailbox so blocked effects do not serialize
  unrelated sessions. Each session retains one API-disabled context until its
  owner exits; no call is retried here.
  """
  use GenServer

  alias Elixos.Toolset.{Core, Peer, Session}

  def start_link([]), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Executes the selected backend once and returns its actual code revision."
  def execute(:quickbeam, tool, params, %Session{} = session, timeout) do
    result =
      with {:ok, context} <- GenServer.call(__MODULE__, {:context, session}, :infinity) do
        Core.call(context, tool, params, timeout)
      end

    {result, Core.revision()}
  end

  def execute({kind, module}, _tool, params, %Session{} = session, _timeout)
      when kind in [:elixir, :native] do
    result = module.call(params, session)
    revision = module.module_info(:md5) |> Base.encode16(case: :lower)
    {result, revision}
  end

  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)
    options = Peer.quickbeam_options()

    with {:ok, pool} <-
           QuickBEAM.ContextPool.start_link(
             size: 1,
             memory_limit: Keyword.fetch!(options, :memory_limit)
           ) do
      {:ok, %{pool: pool, options: options, contexts: %{}, monitors: %{}}}
    end
  end

  @impl true
  def handle_call({:context, %Session{id: id} = session}, _from, state) do
    case Map.fetch(state.contexts, id) do
      {:ok, %{context: context}} ->
        {:reply, {:ok, context}, state}

      :error ->
        case create_context(state.pool, state.options, session) do
          {:ok, context} ->
            monitor = Process.monitor(session.owner)
            entry = %{context: context, monitor: monitor}

            state = %{
              state
              | contexts: Map.put(state.contexts, id, entry),
                monitors: Map.put(state.monitors, monitor, id)
            }

            {:reply, {:ok, context}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _owner, _reason}, state) do
    case Map.pop(state.monitors, monitor) do
      {nil, _monitors} ->
        {:noreply, state}

      {id, monitors} ->
        {entry, contexts} = Map.pop(state.contexts, id)
        QuickBEAM.Context.stop(entry.context)
        {:noreply, %{state | contexts: contexts, monitors: monitors}}
    end
  end

  def handle_info({:EXIT, pool, reason}, %{pool: pool} = state), do: {:stop, reason, state}

  def handle_info({:EXIT, context, _reason}, state) do
    case Enum.find(state.contexts, fn {_id, entry} -> entry.context == context end) do
      nil ->
        {:noreply, state}

      {id, entry} ->
        Process.demonitor(entry.monitor, [:flush])

        {:noreply,
         %{
           state
           | contexts: Map.delete(state.contexts, id),
             monitors: Map.delete(state.monitors, entry.monitor)
         }}
    end
  end

  defp create_context(pool, options, session) do
    # apis:false omits Node/browser helpers but still installs Beam callbacks.
    # Deny the unscoped defaults, notably RPC/spawn; tool effects register only
    # their session-bound capability handlers here.
    denied =
      Map.new(QuickBEAM.Runtime.beam_handlers(), fn {name, _handler} ->
        {name, fn _args -> raise "Unscoped Beam APIs are disabled in the tool sandbox" end}
      end)

    options = Keyword.put(options, :handlers, denied)

    with {:ok, context} <- QuickBEAM.Context.start_link(Keyword.put(options, :pool, pool)) do
      call_options = Keyword.take(options, [:timeout])

      initialized =
        with {:ok, _value} <- QuickBEAM.Context.eval(context, Core.source(), call_options) do
          QuickBEAM.Context.call(context, "__ompCoreInit", [session.session_file], call_options)
        end

      case initialized do
        {:ok, _value} ->
          {:ok, context}

        {:error, reason} ->
          QuickBEAM.Context.stop(context)
          {:error, reason}
      end
    end
  end
end
