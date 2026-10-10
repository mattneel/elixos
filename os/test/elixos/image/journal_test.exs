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

  # A CRC-valid term of the wrong shape is damage, never a record: otherwise a
  # malformed payload would reach the working-set replay and raise there.
  test "a CRC-valid record that is not a {seq, entry} pair is damage", %{path: path} do
    append_all(path, [:fine])

    for payload <- [:erlang.term_to_binary(:not_a_pair), :erlang.term_to_binary({2, :tail})] do
      File.write!(
        path,
        <<byte_size(payload)::32-big, :erlang.crc32(payload)::32-big, payload::binary>>,
        [:append]
      )
    end

    assert Journal.read(path) == {:error, {:corrupt, 2}}
  end

  test "the on-disk format is the documented one", %{path: path} do
    append_all(path, [:hello])
    payload = :erlang.term_to_binary({1, :hello})

    assert File.read!(path) ==
             <<byte_size(payload)::32-big, :erlang.crc32(payload)::32-big, payload::binary>>
  end

  # Atoms are per-VM, so this runs the reader in a child VM: that is exactly
  # the real reader, the next boot. Every module record names its module, and
  # the reader has not loaded it yet. Decoding with `:safe` refuses to create
  # the atom and reports damage, which made a saved generation unreadable by
  # the boot that needs it (found by the M6 integration test). The CRC gate,
  # not the atom table, is what guards the decoder.
  test "a record naming a module this VM has never loaded is not damage", %{path: path} do
    module = :"Elixir.Elixos.JournalTest.Unloaded#{System.unique_integer([:positive])}"
    append_all(path, [{:module, module, "abc"}, {:generation, 1}])

    script = """
    case Elixos.Image.Journal.read(#{inspect(path)}) do
      {:ok, records, :clean} -> IO.puts("records=\#{length(records)}")
      other -> IO.puts("bad \#{inspect(other)}")
    end
    """

    {out, 0} = System.cmd(elixir(), ["-pa", ebin_dir(), "-e", script])
    assert String.trim(out) == "records=2"
  end

  defp elixir, do: System.find_executable("elixir")

  defp ebin_dir do
    Elixos.Image.Journal |> :code.which() |> to_string() |> Path.dirname()
  end
end
