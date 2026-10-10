defmodule Elixos.Image.Journal do
  use GenServer

  @moduledoc """
  Append-only change journal: Smalltalk's changes file (docs/ARCHITECTURE.md §4.3).

  Every module defined at a REPL, every `forget` and every saved generation is
  appended here before anything else happens, so nothing typed is ever lost.

  ## Record format (a contract: recovery tooling reads it)

      <<size::32-big, crc::32-big, payload::binary-size(size)>>

  where `payload = :erlang.term_to_binary({seq, entry})` and
  `crc = :erlang.crc32(payload)`. Sequence numbers start at 1 and increase by 1.

  ## Damage

    * A record cut short at the end of the file, or a bad CRC in the *last*
      record, is a torn tail (a crash mid-append): `read/1` returns the complete
      records and `:torn`, and `open/1` truncates the tail before appending.
    * A bad CRC followed by further records is corruption:
      `{:error, {:corrupt, seq}}`, where `seq` is the damaged record's
      position (1-based). `open/1` refuses such a journal with the same error
      and leaves the file untouched; repairing it is a human decision.

  `append/2` returns only after the record is fsync'd.
  """

  @type t :: pid()
  @type seq :: pos_integer()

  @doc "Opens (creating if needed) the journal at `path`, linked to the caller."
  @spec open(Path.t()) :: {:ok, t()} | {:error, term()}
  def open(path) do
    case scan(path) do
      {:ok, records, _offset, :clean} ->
        start(path, length(records) + 1)

      {:ok, records, offset, :torn} ->
        # A torn tail is a crash mid-append: cut it off, so the next append
        # continues from the last whole record.
        with :ok <- truncate(path, offset) do
          start(path, length(records) + 1)
        end

      {:error, {:corrupt, seq}} ->
        # Damage in the middle is not ours to repair: leave the evidence.
        {:error, {:corrupt, seq}}

      # No journal yet: the first append creates it.
      {:error, :enoent} ->
        start(path, 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec append(t(), term()) :: {:ok, seq()} | {:error, term()}
  def append(journal, entry) do
    GenServer.call(journal, {:append, entry})
  end

  @doc "Reads every complete record. Does not need the journal to be open."
  @spec read(Path.t()) ::
          {:ok, [{seq(), term()}], :clean | :torn} | {:error, {:corrupt, seq()} | :enoent}
  def read(path) do
    case scan(path) do
      {:ok, records, _offset, status} -> {:ok, records, status}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec close(t()) :: :ok
  def close(journal) do
    GenServer.stop(journal)
  end

  ## GenServer

  @impl true
  def init({path, seq}) do
    # Append mode: the journal is only ever added to, and only by us.
    case :file.open(path, [:append, :raw, :binary]) do
      {:ok, file} -> {:ok, %{file: file, seq: seq}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:append, entry}, _from, state) do
    payload = :erlang.term_to_binary({state.seq, entry})
    record = <<byte_size(payload)::32-big, :erlang.crc32(payload)::32-big, payload::binary>>

    with :ok <- :file.write(state.file, record),
         :ok <- :file.sync(state.file) do
      # Only after the fsync: a record that was not durable never happened.
      {:reply, {:ok, state.seq}, %{state | seq: state.seq + 1}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp start(path, seq), do: GenServer.start_link(__MODULE__, {path, seq})

  defp truncate(path, offset) do
    with {:ok, file} <- :file.open(path, [:read, :write, :raw, :binary]) do
      # :file.position/2 answers {:ok, new_position}, not :ok.
      with {:ok, _position} <- :file.position(file, offset),
           :ok <- :file.truncate(file),
           :ok <- :file.sync(file) do
        :file.close(file)
      end
    end
  end

  # Walks the records. Returns the records, the offset just past the last whole
  # one, and whether the remainder is a torn tail or damage in the middle.
  defp scan(path) do
    case File.read(path) do
      {:ok, bytes} -> scan_bytes(bytes, 0, 0, [])
      {:error, reason} -> {:error, reason}
    end
  end

  defp scan_bytes(bytes, offset, index, acc) do
    size = byte_size(bytes)

    cond do
      offset == size ->
        {:ok, Enum.reverse(acc), offset, :clean}

      # A header that does not fit is a torn tail, always: nothing follows it
      # but the end of the file.
      offset + 8 > size ->
        {:ok, Enum.reverse(acc), offset, :torn}

      true ->
        <<_::binary-size(^offset), declared::32-big, crc::32-big, _::binary>> = bytes

        if offset + 8 + declared > size do
          {:ok, Enum.reverse(acc), offset, :torn}
        else
          payload = binary_part(bytes, offset + 8, declared)
          whole_record = offset + 8 + declared

          case decode(payload, crc) do
            {:ok, record} ->
              scan_bytes(bytes, whole_record, index + 1, [record | acc])

            :damage ->
              # Damage with nothing after it is a torn tail; damage followed by
              # further records is corruption, and the caller is told where.
              if whole_record == size do
                {:ok, Enum.reverse(acc), offset, :torn}
              else
                {:error, {:corrupt, index + 1}}
              end
          end
        end
    end
  end

  defp decode(payload, crc) do
    if :erlang.crc32(payload) == crc do
      case decode_term(payload) do
        # The format is `{seq, entry}` (moduledoc): a CRC-valid term of any
        # other shape is damage, not a record to replay.
        {:ok, {seq, _entry} = record} when is_integer(seq) and seq > 0 -> {:ok, record}
        _other -> :damage
      end
    else
      :damage
    end
  end

  # Not `binary_to_term/2` with `:safe`: these records name modules, and the
  # reader is a fresh boot, where those atoms do not exist yet — `:safe`
  # refuses to create atoms, so every module record would read as damage and a
  # saved generation could never be loaded by the boot that needs it (M6).
  # What guards the decoder is the CRC (journal) or the shape check
  # (generation), not the atom table; those bytes are ours.
  defp decode_term(payload) do
    {:ok, :erlang.binary_to_term(payload)}
  rescue
    ArgumentError -> :error
  end
end
