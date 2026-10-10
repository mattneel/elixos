defmodule Elixos.Image.JournalTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 6
  @moduletag :tmp_dir

  alias Elixos.Image.Journal

  setup %{tmp_dir: tmp_dir} do
    %{path: Path.join(tmp_dir, "journal.log")}
  end

  # The record format is a documented contract (Journal moduledoc), so the
  # tests may compute offsets from it.
  defp record_size(seq, entry), do: 8 + byte_size(:erlang.term_to_binary({seq, entry}))

  defp append_all(path, entries) do
    {:ok, journal} = Journal.open(path)
    seqs = for entry <- entries, do: elem(Journal.append(journal, entry), 1)
    :ok = Journal.close(journal)
    seqs
  end

  test "appends get sequence numbers from 1 and read back in order", %{path: path} do
    entries = [
      {:module, Foo, "abc"},
      {:forget, Foo},
      {:generation, 1},
      <<0, 1, 2>>,
      %{any: "term"}
    ]

    assert append_all(path, entries) == [1, 2, 3, 4, 5]
    assert Journal.read(path) == {:ok, Enum.zip(1..5, entries), :clean}
  end

  test "reopening continues the sequence", %{path: path} do
    append_all(path, [:a, :b])
    assert append_all(path, [:c]) == [3]
    assert {:ok, [{1, :a}, {2, :b}, {3, :c}], :clean} = Journal.read(path)
  end

  test "a missing journal", %{path: path} do
    assert Journal.read(path) == {:error, :enoent}
  end

  test "a record cut short at the end is a torn tail", %{path: path} do
    append_all(path, [:a, :b, :c])
    {:ok, bytes} = File.read(path)
    File.write!(path, binary_part(bytes, 0, byte_size(bytes) - 3))

    assert Journal.read(path) == {:ok, [{1, :a}, {2, :b}], :torn}
  end

  test "a torn header is a torn tail too", %{path: path} do
    append_all(path, [:a])
    File.write!(path, <<0, 0, 0>>, [:append])
    assert Journal.read(path) == {:ok, [{1, :a}], :torn}
  end

  test "a bad CRC in the last record is a torn tail", %{path: path} do
    append_all(path, [:a, :b])
    {:ok, bytes} = File.read(path)
    last = byte_size(bytes) - 1
    <<head::binary-size(^last), byte>> = bytes
    File.write!(path, <<head::binary, Bitwise.bxor(byte, 0xFF)>>)

    assert Journal.read(path) == {:ok, [{1, :a}], :torn}
  end

  test "open truncates a torn tail, so the next append is clean", %{path: path} do
    append_all(path, [:a, :b, :c])
    {:ok, bytes} = File.read(path)
    File.write!(path, binary_part(bytes, 0, byte_size(bytes) - 3))

    assert append_all(path, [:d]) == [3]
    assert Journal.read(path) == {:ok, [{1, :a}, {2, :b}, {3, :d}], :clean}
  end

  test "damage followed by valid records is corruption, never silently truncated", %{path: path} do
    append_all(path, [:a, :b, :c])
    {:ok, bytes} = File.read(path)
    offset = record_size(1, :a) + 8 + 2
    <<head::binary-size(^offset), byte, rest::binary>> = bytes
    File.write!(path, <<head::binary, Bitwise.bxor(byte, 0xFF), rest::binary>>)

    assert Journal.read(path) == {:error, {:corrupt, 2}}
    assert {:error, _} = Journal.open(path)
    assert File.read!(path) == <<head::binary, Bitwise.bxor(byte, 0xFF), rest::binary>>
  end

  test "the on-disk format is the documented one", %{path: path} do
    append_all(path, [:hello])
    payload = :erlang.term_to_binary({1, :hello})

    assert File.read!(path) ==
             <<byte_size(payload)::32-big, :erlang.crc32(payload)::32-big, payload::binary>>
  end
end
