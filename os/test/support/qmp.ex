defmodule Elixos.Test.QMP do
  @moduledoc "QMP over an OTP UNIX socket, shared by the harness and framebuffer demos."

  def connect(path, timeout \\ 10_000) do
    deadline = now() + timeout
    socket = connect_until(path, deadline)

    try do
      case receive_json(socket, deadline) do
        %{"QMP" => _} -> :ok
        other -> raise "invalid QMP greeting: #{inspect(other)}"
      end

      command(socket, "qmp_capabilities", %{}, remaining(deadline))
      socket
    rescue
      error ->
        :gen_tcp.close(socket)
        reraise error, __STACKTRACE__
    end
  end

  def close(socket), do: :gen_tcp.close(socket)

  def command(socket, execute, arguments \\ %{}, timeout \\ 10_000) do
    deadline = now() + timeout
    :ok = :inet.setopts(socket, send_timeout: remaining(deadline))
    id = System.unique_integer([:positive, :monotonic])
    request = %{"execute" => execute, "arguments" => arguments, "id" => id}
    :ok = :gen_tcp.send(socket, [:json.encode(request), "\r\n"])
    response(socket, id, deadline)
  end

  def key(socket, qcode, timeout \\ 10_000) do
    command(
      socket,
      "send-key",
      %{
        "keys" => [%{"type" => "qcode", "data" => qcode}],
        "hold-time" => 80
      },
      timeout
    )
  end

  def screendump(socket, path, timeout \\ 10_000) do
    command(socket, "screendump", %{"filename" => Path.expand(path)}, timeout)
  end

  defp connect_until(path, deadline) do
    case :gen_tcp.connect(
           {:local, String.to_charlist(path)},
           0,
           [
             {:inet_backend, :socket},
             :binary,
             active: false,
             packet: :line,
             send_timeout: remaining(deadline),
             send_timeout_close: true
           ],
           remaining(deadline)
         ) do
      {:ok, socket} ->
        socket

      {:error, reason} when reason in [:enoent, :econnrefused] ->
        Process.sleep(min(50, remaining(deadline)))
        connect_until(path, deadline)

      {:error, reason} ->
        raise "QMP connect failed: #{inspect(reason)}"
    end
  end

  defp response(socket, id, deadline) do
    case receive_json(socket, deadline) do
      %{"id" => ^id, "return" => result} -> result
      %{"id" => ^id, "error" => error} -> raise "QMP command failed: #{inspect(error)}"
      %{"event" => _} -> response(socket, id, deadline)
      %{"id" => _} -> response(socket, id, deadline)
      other -> raise "unexpected QMP response: #{inspect(other)}"
    end
  end

  defp receive_json(socket, deadline) do
    case :gen_tcp.recv(socket, 0, remaining(deadline)) do
      {:ok, line} -> :json.decode(line)
      {:error, reason} -> raise "QMP receive failed: #{inspect(reason)}"
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp remaining(deadline) do
    case deadline - now() do
      left when left > 0 -> left
      _ -> raise "QMP timeout"
    end
  end
end
