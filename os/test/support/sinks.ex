defmodule Elixos.Test.ProcessSink do
  @moduledoc "A control sink that sends every write to a process as `{:shim_write, binary}`."
  @behaviour Elixos.Shim.Sink

  @impl true
  def open(pid) when is_pid(pid), do: {:ok, pid}

  @impl true
  def write(pid, data) do
    send(pid, {:shim_write, IO.iodata_to_binary(data)})
    :ok
  end
end

defmodule Elixos.Test.BrokenSink do
  @moduledoc "A control sink whose writes always fail with `{:error, :epipe}`."
  @behaviour Elixos.Shim.Sink

  @impl true
  def open(arg), do: {:ok, arg}

  @impl true
  def write(_state, _data), do: {:error, :epipe}
end
