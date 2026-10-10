defmodule Elixos.Shim.Sink do
  @moduledoc """
  Where control lines go.

  Production uses `Elixos.Shim.Sink.Fd` (the pipe the shim hands us as
  ELIXOS_CTL_FD). Tests use a process sink (`Elixos.Test.ProcessSink`), which
  is what makes `Elixos.Shim.Control` testable on the dev host.
  """

  @callback open(arg :: term()) :: {:ok, state :: term()} | {:error, term()}
  @callback write(state :: term(), iodata()) :: :ok | {:error, term()}
end

defmodule Elixos.Shim.Sink.Fd do
  @moduledoc """
  Writes to the control pipe inherited from the shim, by fd number (M4).

  On Linux, opening `/proc/self/fd/<n>` for writing reopens the pipe's write
  end, so no port or NIF is needed. Writes are small (< PIPE_BUF), hence atomic.
  """
  @behaviour Elixos.Shim.Sink

  @impl true
  def open(fd) when is_integer(fd) and fd >= 0 do
    # Reopening /proc/self/fd/<n> for writing gives us the pipe's write end:
    # the shim's fd was inherited, so there is no path to it otherwise.
    File.open("/proc/self/fd/#{fd}", [:write, :raw, :binary])
  end

  @impl true
  def write(device, data) do
    IO.binwrite(device, data)
  rescue
    # A control pipe whose reader is gone (EPIPE) must be reported, not crash
    # the control server: Elixos.Shim.Control keeps running and tells callers.
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end
end
