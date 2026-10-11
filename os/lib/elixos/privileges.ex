defmodule Elixos.Privileges do
  @moduledoc """
  Named privileged helpers and the BEAM's real uid (M17, docs/ROADMAP.md).

  The shim reads the image's allow-list once and executes helpers directly.
  The unprivileged BEAM can request a name, never a command or another uid.

  The guest starts this client after Control. A linked reader owns the inherited
  reply pipe, so waiting for a helper never blocks Control's heartbeats. Requests
  are serialized because the wire has names, not request identifiers. A timed-out
  request keeps its place until its late reply is consumed; no request is replayed.
  Queued requests can time out without ever being written. A broken reply channel
  fails closed and is never reopened within this VM.

  Options are `:control` (default Control), `:timeout_ms` (default 5,000), and
  `:name` (default this module; nil is unregistered). `:source` may supply a
  `{module, argument}` implementing open/read/close for deterministic host tests;
  otherwise the required `ELIXOS_REPLY_FD` is validated and opened on the guest.
  """
  # Restarting would lose the tombstone for a late reply and could attribute it
  # to a new same-name request. Only a new VM has a fresh reply channel.
  use GenServer, restart: :temporary

  alias Elixos.Decimal
  alias Elixos.Shim.Control

  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "Requests an allow-listed helper, validating its name before using either pipe."
  @spec request(String.t()) :: {:ok, pos_integer()} | {:error, term()}
  def request(name), do: request(__MODULE__, name)

  @doc false
  def request(server, name) do
    if valid_name?(name) do
      GenServer.call(server, {:request, name}, :infinity)
    else
      {:error, :invalid_name}
    end
  end

  @doc "Whether the name is one to 32 ASCII lowercase letters, digits or hyphens."
  @spec valid_name?(term()) :: boolean()
  def valid_name?(name) when is_binary(name) and byte_size(name) in 1..32,
    do: name_bytes?(name)

  def valid_name?(_name), do: false

  defp name_bytes?(<<>>), do: true

  defp name_bytes?(<<byte, rest::binary>>) when byte in ?a..?z or byte in ?0..?9 or byte == ?-,
    do: name_bytes?(rest)

  defp name_bytes?(_name), do: false

  @doc "Encodes a valid name as a HELPER request including its trailing newline."
  @spec encode_request(String.t()) :: {:ok, binary()} | {:error, :invalid_name}
  def encode_request(name) do
    if valid_name?(name), do: {:ok, "HELPER " <> name <> "\n"}, else: {:error, :invalid_name}
  end

  @doc "Parses a newline-free HELPER reply; successful pids are positive canonical u32 values."
  @spec parse_reply(binary()) ::
          {:ok, String.t(), pos_integer()} | {:refused, String.t()} | {:error, :invalid}
  def parse_reply("HELPER " <> rest) when byte_size(rest) <= 57 do
    case :binary.split(rest, " ", [:global]) do
      [name, "OK", pid] ->
        with true <- valid_name?(name),
             {:ok, pid} when pid > 0 <- Decimal.parse_u32(pid) do
          {:ok, name, pid}
        else
          _ -> {:error, :invalid}
        end

      [name, "REFUSED"] ->
        if valid_name?(name), do: {:refused, name}, else: {:error, :invalid}

      _ ->
        {:error, :invalid}
    end
  end

  def parse_reply(_line), do: {:error, :invalid}

  @doc "Returns the running BEAM's real operating-system uid."
  @spec uid() :: non_neg_integer()
  def uid do
    status = File.read!("/proc/self/status")
    [_, real] = Regex.run(~r/^Uid:\s+([0-9]+)\s/m, status)
    String.to_integer(real)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, {module, arg}} <- source(opts) do
      owner = self()
      ref = make_ref()
      reader = spawn_link(fn -> read_replies(owner, ref, module, arg) end)

      receive do
        {^ref, :opened} ->
          {:ok,
           %{
             reader: reader,
             control: Keyword.get(opts, :control, Control),
             timeout_ms: Keyword.get(opts, :timeout_ms, 5_000),
             pending: %{},
             queue: :queue.new(),
             active: nil,
             error: nil
           }}

        {^ref, {:error, reason}} ->
          {:stop, {:reply_pipe, reason}}

        {:EXIT, ^reader, reason} ->
          {:stop, {:reply_pipe, reason}}
      end
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp source(opts) do
    case Keyword.fetch(opts, :source) do
      {:ok, source} -> {:ok, source}
      :error -> reply_fd(System.get_env("ELIXOS_REPLY_FD"))
    end
  end

  defp reply_fd(nil), do: {:error, {:launch_contract, :missing, "ELIXOS_REPLY_FD"}}

  defp reply_fd(text) do
    case Decimal.parse_u32(text) do
      {:ok, fd} when fd >= 3 -> {:ok, {Elixos.Privileges.ReplyFd, fd}}
      _ -> {:error, {:launch_contract, :invalid, "ELIXOS_REPLY_FD"}}
    end
  end

  @impl true
  def handle_call({:request, _name}, _from, %{error: reason} = state) when not is_nil(reason),
    do: {:reply, {:error, {:reply_pipe, reason}}, state}

  def handle_call({:request, name}, from, state) do
    ref = make_ref()
    timer = Process.send_after(self(), {:expire, ref}, state.timeout_ms)
    entry = %{name: name, from: from, timer: timer}

    state = %{
      state
      | pending: Map.put(state.pending, ref, entry),
        queue: :queue.in(ref, state.queue)
    }

    {:noreply, dispatch(state)}
  end

  @impl true
  def handle_info({:expire, ref}, state) do
    case Map.fetch(state.pending, ref) do
      {:ok, %{from: from} = entry} when not is_nil(from) ->
        GenServer.reply(from, {:error, :timeout})
        Process.cancel_timer(entry.timer)

        pending =
          if state.active == ref do
            # Retain this tombstone until the reply arrives. In particular, a
            # later request with the same name must not consume the old reply.
            Map.put(state.pending, ref, %{entry | from: nil})
          else
            Map.delete(state.pending, ref)
          end

        queue =
          if state.active == ref,
            do: state.queue,
            else: :queue.filter(&(&1 != ref), state.queue)

        {:noreply, %{state | pending: pending, queue: queue}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:helper_reply, reader, reply}, %{reader: reader} = state) do
    case {state.active, reply} do
      {ref, {:ok, name, pid}} when not is_nil(ref) ->
        finish(state, ref, name, {:ok, pid})

      {ref, {:refused, name}} when not is_nil(ref) ->
        finish(state, ref, name, {:error, :refused})

      _ ->
        {:noreply, fail_channel(state, :invalid_reply)}
    end
  end

  def handle_info({:reply_error, reader, reason}, %{reader: reader} = state),
    do: {:noreply, fail_channel(state, reason)}

  def handle_info({:EXIT, reader, reason}, %{reader: reader, error: nil} = state),
    do: {:noreply, fail_channel(state, reason)}

  def handle_info(_message, state), do: {:noreply, state}

  defp dispatch(%{active: nil, error: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, ref}, queue} ->
        state = %{state | queue: queue}

        case Map.fetch(state.pending, ref) do
          :error ->
            dispatch(state)

          {:ok, entry} ->
            case Control.helper(state.control, entry.name) do
              :ok -> %{state | active: ref}
              {:error, reason} -> fail_channel(state, {:control_write, reason})
            end
        end

      {:empty, _queue} ->
        state
    end
  end

  defp dispatch(state), do: state

  defp finish(state, ref, name, result) do
    entry = Map.fetch!(state.pending, ref)

    if entry.name == name do
      Process.cancel_timer(entry.timer)
      if entry.from, do: GenServer.reply(entry.from, result)
      state = %{state | active: nil, pending: Map.delete(state.pending, ref)}
      {:noreply, dispatch(state)}
    else
      {:noreply, fail_channel(state, :unexpected_helper)}
    end
  end

  defp fail_channel(state, reason) do
    for {_ref, entry} <- state.pending do
      Process.cancel_timer(entry.timer)
      if entry.from, do: GenServer.reply(entry.from, {:error, {:reply_pipe, reason}})
    end

    Process.exit(state.reader, :kill)
    %{state | pending: %{}, queue: :queue.new(), active: nil, error: reason}
  end

  defp read_replies(owner, ref, module, arg) do
    case module.open(arg) do
      {:ok, source} ->
        send(owner, {ref, :opened})

        try do
          read_loop(owner, module, source)
        after
          module.close(source)
        end

      {:error, reason} ->
        send(owner, {ref, {:error, reason}})
    end
  end

  defp read_loop(owner, module, source, buffer \\ <<>>) do
    case module.read(source) do
      {:ok, chunk} when is_binary(chunk) and byte_size(chunk) in 1..65 ->
        case consume_replies(owner, buffer <> chunk) do
          {:ok, rest} -> read_loop(owner, module, source, rest)
          {:error, reason} -> send(owner, {:reply_error, self(), reason})
        end

      :eof ->
        reason = if buffer == <<>>, do: :eof, else: :unterminated_reply
        send(owner, {:reply_error, self(), reason})

      {:error, reason} ->
        send(owner, {:reply_error, self(), reason})

      _ ->
        send(owner, {:reply_error, self(), :invalid_reply})
    end
  end

  defp consume_replies(owner, bytes) do
    case :binary.match(bytes, "\n") do
      {length, 1} when length <= 64 ->
        <<line::binary-size(^length), ?\n, rest::binary>> = bytes

        case parse_reply(line) do
          {:error, :invalid} ->
            {:error, :invalid_reply}

          reply ->
            send(owner, {:helper_reply, self(), reply})
            consume_replies(owner, rest)
        end

      :nomatch when byte_size(bytes) <= 64 ->
        {:ok, bytes}

      _ ->
        {:error, :invalid_reply}
    end
  end

  @impl true
  def terminate(_reason, state) do
    fail_channel(state, :closed)
    :ok
  end
end

defmodule Elixos.Privileges.ReplyFd do
  @moduledoc false

  def open(fd), do: File.open("/proc/self/fd/#{fd}", [:read, :raw, :binary])
  # OTP fills fixed-size reads on pipes before returning. One byte avoids
  # waiting for a future reply; the client bounds the line and preserves CRLF.
  def read(source), do: :file.read(source, 1)
  def close(source), do: File.close(source)
end
