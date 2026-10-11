defmodule Elixos.Shim.Control do
  @moduledoc """
  Owns the control channel to the PID 1 shim (docs/PROTOCOL.md §2-3).

  It writes `HB` immediately on start and then every `:heartbeat_ms`, and it
  turns requests into protocol lines. Requests are synchronous: when `commit/2`
  returns `:ok`, the line has been written, so "commit, then reboot" is ordered.

  Options:

    * `:sink` (required) - `{module, arg}`; the module implements `Elixos.Shim.Sink`
    * `:heartbeat_ms` - heartbeat interval, default `1_000`
    * `:name` - registered name, default `Elixos.Shim.Control`; `nil` registers nothing

  `pause_heartbeat/1` exists for fault injection: to the shim, a paused
  heartbeat is indistinguishable from a hung VM (M5 tests rely on that).

  Generation arguments are validated in the caller: anything but an integer in
  `0..4_294_967_295` raises `ArgumentError` and never reaches the server.
  If the sink fails, the request returns `{:error, reason}` and the server keeps running.
  """
  use GenServer

  @type server :: GenServer.server()

  @default_heartbeat_ms 1_000

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)

    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec commit(server(), non_neg_integer()) :: :ok | {:error, term()}
  def commit(server \\ __MODULE__, generation) do
    request(server, {:commit, generation})
  end

  @spec next(server(), non_neg_integer()) :: :ok | {:error, term()}
  def next(server \\ __MODULE__, generation) do
    request(server, {:next, generation})
  end

  @doc "Writes a validated helper request; replies are handled by Elixos.Privileges."
  @spec helper(server(), String.t()) :: :ok | {:error, term()}
  def helper(server \\ __MODULE__, name), do: request(server, {:helper, name})

  @spec reboot(server()) :: :ok | {:error, term()}
  def reboot(server \\ __MODULE__), do: request(server, :reboot)

  @spec poweroff(server()) :: :ok | {:error, term()}
  def poweroff(server \\ __MODULE__), do: request(server, :poweroff)

  @spec halt(server()) :: :ok | {:error, term()}
  def halt(server \\ __MODULE__), do: request(server, :halt)

  @spec pause_heartbeat(server()) :: :ok
  def pause_heartbeat(server \\ __MODULE__), do: GenServer.call(server, :pause_heartbeat)

  @spec resume_heartbeat(server()) :: :ok
  def resume_heartbeat(server \\ __MODULE__), do: GenServer.call(server, :resume_heartbeat)

  # The line is encoded (and the generation validated: invalid ones raise here,
  # in the caller) before the call, so a bad argument never reaches the server.
  defp request(server, message) do
    GenServer.call(server, {:write, Elixos.Shim.Protocol.encode(message)})
  end

  @impl true
  def init(opts) do
    {module, arg} = Keyword.fetch!(opts, :sink)
    heartbeat_ms = Keyword.get(opts, :heartbeat_ms, @default_heartbeat_ms)
    state = %{module: module, sink: nil, heartbeat_ms: heartbeat_ms, paused: false, timer: nil}

    case module.open(arg) do
      {:ok, sink} ->
        state = %{state | sink: sink}
        # The shim's boot grace runs until the first heartbeat arrives.
        _ = write(state)
        {:ok, schedule(state)}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:write, line}, _from, state) do
    case state.module.write(state.sink, line) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:pause_heartbeat, _from, state) do
    cancel(state.timer)
    {:reply, :ok, %{state | paused: true, timer: nil}}
  end

  def handle_call(:resume_heartbeat, _from, state) do
    if state.paused,
      do: {:reply, :ok, schedule(%{state | paused: false})},
      else: {:reply, :ok, state}
  end

  @impl true
  def handle_info({:heartbeat, ref}, state) do
    # A message from a superseded schedule (see schedule/1) is a no-op: acting
    # on it would forget the live timer and leave two heartbeat loops running.
    if match?({^ref, _}, state.timer) do
      state = %{state | timer: nil}

      if state.paused do
        # To the shim, a paused heartbeat is indistinguishable from a hung VM.
        {:noreply, state}
      else
        # A failed write must not bring the server down: the shim times us out.
        _ = write(state)
        {:noreply, schedule(state)}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp write(state), do: state.module.write(state.sink, Elixos.Shim.Protocol.encode(:heartbeat))

  # Every schedule carries a fresh reference, so an expired timer that was
  # already in flight when pause/resume ran cannot revive a stale loop.
  defp schedule(state) do
    ref = make_ref()
    %{state | timer: {ref, Process.send_after(self(), {:heartbeat, ref}, state.heartbeat_ms)}}
  end

  defp cancel(nil), do: :ok
  defp cancel({_ref, timer}), do: Process.cancel_timer(timer)

  @impl true
  def terminate(_reason, state) do
    cancel(state.timer)
    :ok
  end
end
