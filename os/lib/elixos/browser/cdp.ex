defmodule Elixos.Browser.CDP do
  @moduledoc """
  Just enough Chrome DevTools Protocol for the browser service (M25).

  Lightpanda's `serve` speaks CDP over one WebSocket (protocol 1.3). The flow
  is the standard one, verified against Lightpanda 1.0.0: `Target.createTarget`
  makes a page, `Target.attachToTarget` with `flatten: true` returns a session
  id, and every later command carries it. Frames are text.

  The WebSocket client is ours: the handshake is RFC 6455 with `:crypto` and
  `Base`, and OTP's `:json` parses replies, so the OS needs no WebSocket
  dependency for one adapter (ADR-065). It is deliberately small - one
  connection, synchronous calls by id, events drained, pings answered.
  """

  import Bitwise

  @guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  @default_timeout 30_000

  defstruct socket: nil, buffer: <<>>, next_id: 1

  @type t :: %__MODULE__{socket: :gen_tcp.socket(), buffer: binary(), next_id: pos_integer()}

  @doc "Opens a WebSocket to `ws://host:port/path`."
  @spec connect(String.t(), timeout()) :: {:ok, t()} | {:error, term()}
  def connect(url, timeout \\ @default_timeout) do
    with {:ok, host, port, path} <- parse(url),
         {:ok, socket} <-
           :gen_tcp.connect(
             String.to_charlist(host),
             port,
             [:binary, active: false, nodelay: true],
             timeout
           ),
         {:ok, rest} <- handshake(socket, host, port, path, timeout) do
      # Bytes that arrived with the handshake reply are frames already.
      {:ok, %__MODULE__{socket: socket, buffer: rest}}
    end
  end

  @doc """
  Sends one CDP command and returns its `result`.

  Events and other replies are drained while waiting; the command's own error
  becomes `{:error, {code, message}}`. `session/1` is the id `attach/2`
  returned; commands without one go to the browser itself.
  """
  @spec call(t(), String.t(), map(), timeout(), String.t() | nil) ::
          {:ok, term(), t()} | {:error, term(), t()}
  def call(cdp, method, params \\ %{}, timeout \\ @default_timeout, session \\ nil) do
    id = cdp.next_id
    message = %{id: id, method: method, params: params}
    message = if session, do: Map.put(message, :sessionId, session), else: message
    cdp = %{cdp | next_id: id + 1}

    with :ok <- send_text(cdp.socket, JSON.encode!(message)),
         {:ok, reply, cdp} <- await(cdp, id, timeout) do
      case reply do
        %{"result" => result} -> {:ok, result, cdp}
        %{"error" => %{"code" => code, "message" => text}} -> {:error, {code, text}, cdp}
        other -> {:error, {:unexpected, other}, cdp}
      end
    end
  end

  @doc "Closes the connection."
  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: socket}), do: :gen_tcp.close(socket)

  ## handshake

  defp parse(url) do
    case URI.parse(url) do
      %URI{scheme: "ws", host: host, port: port, path: path} when is_binary(host) and host != "" ->
        {:ok, host, port || 80, path || "/"}

      _other ->
        {:error, :bad_url}
    end
  end

  defp handshake(socket, host, port, path, timeout) do
    key = Base.encode64(:crypto.strong_rand_bytes(16))

    request = [
      "GET ",
      path,
      " HTTP/1.1\r\nHost: ",
      host,
      ":",
      Integer.to_string(port),
      "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ",
      key,
      "\r\nSec-WebSocket-Version: 13\r\n\r\n"
    ]

    with :ok <- :gen_tcp.send(socket, request),
         {:ok, head, rest} <- read_head(socket, <<>>, timeout) do
      expected = Base.encode64(:crypto.hash(:sha, key <> @guid))

      cond do
        not String.contains?(head, " 101 ") -> {:error, {:handshake, head}}
        not String.contains?(head, expected) -> {:error, :bad_accept}
        true -> {:ok, rest}
      end
    end
  end

  defp read_head(socket, acc, timeout) do
    case :binary.split(acc, "\r\n\r\n") do
      [head, rest] ->
        {:ok, head, rest}

      [_incomplete] ->
        case :gen_tcp.recv(socket, 0, timeout) do
          {:ok, data} -> read_head(socket, acc <> data, timeout)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  ## frames

  defp send_text(socket, text) do
    payload = :binary.bin_to_list(text)
    size = length(payload)
    mask = :crypto.strong_rand_bytes(4)

    header =
      cond do
        size < 126 -> [0x81, 0x80 ||| size]
        size < 65_536 -> [0x81, 0x80 ||| 126, <<size::16>>]
        true -> [0x81, 0x80 ||| 127, <<size::64>>]
      end

    :gen_tcp.send(socket, :erlang.iolist_to_binary([header, mask, mask_payload(payload, mask)]))
  end

  defp mask_payload(payload, mask) do
    mask_bytes = :binary.bin_to_list(mask)

    payload
    |> Enum.with_index()
    |> Enum.map(fn {byte, index} -> bxor(byte, Enum.at(mask_bytes, rem(index, 4))) end)
    |> :binary.list_to_bin()
  end

  defp await(cdp, id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_reply(cdp, id, deadline)
  end

  defp await_reply(cdp, id, deadline) do
    case read_message(cdp, deadline) do
      {:ok, :text, payload, cdp} ->
        case JSON.decode(payload) do
          {:ok, %{"id" => reply_id} = reply} ->
            if reply_id == id do
              {:ok, reply, cdp}
            else
              await_reply(cdp, id, deadline)
            end

          # Events (Target.targetCreated, Page.loadEventFired, ...) carry no
          # id: they are drained while waiting for the reply we asked for.
          {:ok, _event} ->
            await_reply(cdp, id, deadline)

          {:error, _reason} ->
            await_reply(cdp, id, deadline)
        end

      {:ok, :ping, payload, cdp} ->
        with :ok <- :gen_tcp.send(cdp.socket, [0x8A, byte_size(payload), payload]) do
          await_reply(cdp, id, deadline)
        end

      {:ok, _other, _payload, cdp} ->
        await_reply(cdp, id, deadline)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # One message, reassembling continuation frames.
  defp read_message(cdp, deadline, opcode \\ nil, acc \\ <<>>) do
    with {:ok, <<fin::1, _rsv::3, op::4, masked::1, len::7>>, cdp} <- fill(cdp, 2, deadline),
         {:ok, len, cdp} <- length(len, cdp, deadline),
         {:ok, mask, cdp} <- mask_key(masked, cdp, deadline),
         {:ok, body, cdp} <- fill(cdp, len, deadline) do
      payload = if mask, do: mask_payload(:binary.bin_to_list(body), mask), else: body
      kind = if opcode == nil or op == 0, do: kind_of(op), else: kind_of(opcode)

      cond do
        op == 8 -> {:error, :closed_by_peer}
        fin == 1 -> {:ok, kind, acc <> payload, cdp}
        true -> read_message(cdp, deadline, kind, acc <> payload)
      end
    end
  end

  defp kind_of(1), do: :text
  defp kind_of(9), do: :ping
  defp kind_of(_other), do: :other

  defp length(len, cdp, _deadline) when len < 126, do: {:ok, len, cdp}

  defp length(126, cdp, deadline) do
    with {:ok, <<len::16>>, cdp} <- fill(cdp, 2, deadline), do: {:ok, len, cdp}
  end

  defp length(127, cdp, deadline) do
    with {:ok, <<len::64>>, cdp} <- fill(cdp, 8, deadline), do: {:ok, len, cdp}
  end

  defp mask_key(0, cdp, _deadline), do: {:ok, nil, cdp}

  defp mask_key(1, cdp, deadline) do
    with {:ok, mask, cdp} <- fill(cdp, 4, deadline), do: {:ok, mask, cdp}
  end

  defp fill(%__MODULE__{buffer: buffer} = cdp, n, _deadline) when byte_size(buffer) >= n do
    <<head::binary-size(^n), rest::binary>> = buffer
    {:ok, head, %{cdp | buffer: rest}}
  end

  defp fill(cdp, n, deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 1)

    case :gen_tcp.recv(cdp.socket, 0, timeout) do
      {:ok, data} -> fill(%{cdp | buffer: cdp.buffer <> data}, n, deadline)
      {:error, reason} -> {:error, reason}
    end
  end
end
