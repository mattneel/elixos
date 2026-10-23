defmodule Elixos.Candidate.ChildIO do
  @moduledoc false

  use GenServer

  def start, do: GenServer.start(__MODULE__, [], name: :user)

  @impl true
  def init([]) do
    Process.flag(:trap_exit, true)
    port = Port.open({:fd, 0, 1}, [:binary, :eof])
    Process.group_leader(self(), self())
    if :init.notify_when_started(self()) == :started, do: send(self(), {:init, :started})
    {:ok, %{port: port, worker: nil}}
  end

  @impl true
  def handle_info({:init, :started}, %{worker: nil} = state) do
    worker = spawn_link(fn -> Elixos.Candidate.Runner.main() end)
    {:noreply, %{state | worker: worker}}
  end

  def handle_info({:io_request, from, reply_as, request}, state) do
    send(from, {:io_reply, reply_as, io_reply(request, state.port)})
    {:noreply, state}
  end

  def handle_info({port, :eof}, %{port: port}), do: :erlang.halt(1)
  def handle_info({:EXIT, port, _reason}, %{port: port}), do: :erlang.halt(1)
  def handle_info({:EXIT, worker, _reason}, %{worker: worker}), do: :erlang.halt(1)

  # Stdin is only an ownership channel. It never dispatches a PID, MFA, fun,
  # ETF term, model-supplied command, or arbitrary message to the host.
  def handle_info({_port, {:data, _bytes}}, state), do: {:noreply, state}
  def handle_info(_message, state), do: {:noreply, state}

  defp io_reply({:put_chars, encoding, chars}, port), do: put_chars(port, chars, encoding)
  defp io_reply({:put_chars, chars}, port), do: put_chars(port, chars, :latin1)
  defp io_reply({:put_chars, encoding, module, function, args}, port),
    do: put_chars(port, apply(module, function, args), encoding)
  defp io_reply({:put_chars, module, function, args}, port),
    do: put_chars(port, apply(module, function, args), :latin1)
  defp io_reply({:requests, requests}, port) do
    Enum.reduce_while(requests, :ok, fn request, :ok ->
      case io_reply(request, port) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  defp io_reply(:getopts, _port), do: [binary: true, encoding: :unicode]
  defp io_reply({:setopts, _options}, _port), do: :ok
  defp io_reply(_request, _port), do: {:error, :enotsup}

  defp put_chars(port, chars, encoding) do
    bytes = if encoding == :latin1, do: IO.iodata_to_binary(chars),
               else: :unicode.characters_to_binary(chars, encoding, :utf8)
    true = Port.command(port, bytes)
    :ok
  rescue
    _ -> {:error, :badarg}
  end
end
