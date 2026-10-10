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

  def start_link(opts) do
    _ = opts
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Control.start_link/1")
  end

  @spec commit(server(), non_neg_integer()) :: :ok | {:error, term()}
  def commit(server \\ __MODULE__, generation) do
    _ = {server, generation}
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Control.commit/2")
  end

  @spec next(server(), non_neg_integer()) :: :ok | {:error, term()}
  def next(server \\ __MODULE__, generation) do
    _ = {server, generation}
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Control.next/2")
  end

  @spec reboot(server()) :: :ok | {:error, term()}
  def reboot(server \\ __MODULE__) do
    _ = server
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Control.reboot/1")
  end

  @spec poweroff(server()) :: :ok | {:error, term()}
  def poweroff(server \\ __MODULE__) do
    _ = server
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Control.poweroff/1")
  end

  @spec halt(server()) :: :ok | {:error, term()}
  def halt(server \\ __MODULE__) do
    _ = server
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Control.halt/1")
  end

  @spec pause_heartbeat(server()) :: :ok
  def pause_heartbeat(server \\ __MODULE__) do
    _ = server
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Control.pause_heartbeat/1")
  end

  @spec resume_heartbeat(server()) :: :ok
  def resume_heartbeat(server \\ __MODULE__) do
    _ = server
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Control.resume_heartbeat/1")
  end

  @impl true
  def init(opts) do
    _ = opts
    Elixos.NotImplemented.raise!(2, "Elixos.Shim.Control.init/1")
  end
end
