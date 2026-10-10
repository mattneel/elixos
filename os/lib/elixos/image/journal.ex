defmodule Elixos.Image.Journal do
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
  def open(path), do: Elixos.NotImplemented.raise!(6, "Elixos.Image.Journal.open/1 #{path}")

  @spec append(t(), term()) :: {:ok, seq()} | {:error, term()}
  def append(journal, entry) do
    _ = {journal, entry}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Journal.append/2")
  end

  @doc "Reads every complete record. Does not need the journal to be open."
  @spec read(Path.t()) ::
          {:ok, [{seq(), term()}], :clean | :torn} | {:error, {:corrupt, seq()} | :enoent}
  def read(path), do: Elixos.NotImplemented.raise!(6, "Elixos.Image.Journal.read/1 #{path}")

  @spec close(t()) :: :ok
  def close(journal) do
    _ = journal
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Journal.close/1")
  end
end
