defmodule Elixos.RingVectorsTest do
  @moduledoc """
  M31: the Elixir ring (`Elixos.Test.Ring`, the tests' side of the region)
  against spec/ring.vectors, the golden vectors shim/src/ring.zig checks too.
  The file documents its own format.
  """
  use ExUnit.Case, async: true

  alias Elixos.Test.Ring

  @moduletag milestone: 31
  @moduletag :tmp_dir

  defp vectors do
    Elixos.Test.Paths.spec("ring.vectors")
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {line, _} -> line == "" or String.starts_with?(line, "#") end)
    |> Enum.map(fn {line, number} -> {number, String.split(line, "\t")} end)
  end

  defp hex(text), do: Base.decode16!(text, case: :lower)

  test "every vector kind is present" do
    kinds = vectors() |> Enum.map(fn {_, [kind | _]} -> kind end) |> MapSet.new()
    assert kinds == MapSet.new(~w(crc capacity header frame decode wrap))
  end

  test "crc vectors" do
    for {line, ["crc", bytes, crc]} <- vectors() do
      assert :erlang.crc32(hex(bytes)) == String.to_integer(crc, 16), "line #{line}"
    end
  end

  test "capacity vectors" do
    for {line, ["capacity", size, expected]} <- vectors() do
      size = String.to_integer(size)

      case expected do
        "invalid" -> assert Ring.capacity(size) == :error, "line #{line}"
        n -> assert Ring.capacity(size) == {:ok, String.to_integer(n)}, "line #{line}"
      end
    end
  end

  test "header vectors: what the big core's initialisation leaves", %{tmp_dir: dir} do
    for {line, ["header", size, expected]} <- vectors() do
      size = String.to_integer(size)
      path = Path.join(dir, "header-#{line}")
      Ring.create(path, size)
      File.write!(path, :binary.copy(<<0xA5>>, size))
      region = Ring.open(path, size)
      assert Ring.prepare(region) == [:a, :b]
      assert Ring.prepare(region) == []
      contents = File.read!(path)
      half = div(size, 2)

      for base <- [0, half] do
        assert binary_part(contents, base, 64) == hex(expected), "line #{line}"
        assert binary_part(contents, base + 64, half - 64) == <<0::size((half - 64) * 8)>>
      end

      assert Ring.initial_header(elem(Ring.capacity(size), 1)) == hex(expected)
    end
  end

  test "frame vectors: encoding, and a writer and reader on a region", %{tmp_dir: dir} do
    path = Ring.create(Path.join(dir, "frames"), 4096)
    region = Ring.open(path, 4096)

    for {line, ["frame", seq, payload, expected]} <- vectors() do
      seq = String.to_integer(seq)
      payload = hex(payload)
      assert Ring.encode(seq, payload) == hex(expected), "line #{line}"

      Ring.put_field(region, :a, :magic, 0)
      assert :a in Ring.prepare(region)
      writer = %{Ring.writer(region, :a) | seq: seq}
      {1, _} = Ring.write(writer, [payload])

      assert Ring.get_bytes(region, :a, 0, byte_size(hex(expected))) == hex(expected),
             "line #{line}"

      reader = %Ring.Reader{region: region, base: 0, capacity: region.capacity}
      assert {[{:frame, ^seq, ^payload}], _} = Ring.read(reader, 1)
    end
  end

  test "decode vectors, on their own and through a reader", %{tmp_dir: dir} do
    path = Ring.create(Path.join(dir, "decode"), 4096)
    region = Ring.open(path, 4096)

    for {line, ["decode", stream, expected]} <- vectors() do
      stream = hex(stream)
      Ring.put_field(region, :b, :magic, 0)
      assert :b in Ring.prepare(region)
      Ring.put_bytes(region, :b, 0, stream)
      Ring.put_field(region, :b, :head, byte_size(stream))
      reader = %Ring.Reader{region: region, base: 2048, capacity: region.capacity}
      {results, _} = Ring.read(reader, 1)

      case String.split(expected, " ") do
        ["frame", seq, payload, consumed] ->
          seq = String.to_integer(seq)
          payload = hex(payload)
          consumed = String.to_integer(consumed)
          assert Ring.decode(stream) == {:frame, seq, payload, consumed}, "line #{line}"
          assert results == [{:frame, seq, payload}]
          assert Ring.field(region, :b, :tail) == consumed
          assert Ring.field(region, :b, :dropped) == 0

        ["crc", consumed] ->
          consumed = String.to_integer(consumed)
          assert Ring.decode(stream) == {:crc, consumed}, "line #{line}"
          assert results == [:dropped]
          assert Ring.field(region, :b, :tail) == consumed
          assert Ring.field(region, :b, :dropped) == 1

        ["resync"] ->
          assert Ring.decode(stream) == :resync, "line #{line}"
          assert results == [:dropped]
          assert Ring.field(region, :b, :tail) == byte_size(stream)
          assert Ring.field(region, :b, :dropped) == 1
      end
    end
  end

  test "wrap vectors: the data area and the 2^32 counters wrap", %{tmp_dir: dir} do
    for {line, ["wrap", size, start, seq, payload, head_after, places]} <- vectors() do
      size = String.to_integer(size)
      start = String.to_integer(start)
      seq = String.to_integer(seq)
      payload = hex(payload)
      head_after = String.to_integer(head_after)
      path = Ring.create(Path.join(dir, "wrap-#{line}"), size)
      region = Ring.open(path, size)
      [:a, :b] = Ring.prepare(region)
      Ring.put_field(region, :a, :head, start)
      Ring.put_field(region, :a, :tail, start)
      writer = %{Ring.writer(region, :a) | seq: seq}
      {1, _} = Ring.write(writer, [payload])
      assert Ring.field(region, :a, :head) == head_after, "line #{line}"
      contents = File.read!(path)

      for place <- String.split(places, " ") do
        [offset, bytes] = String.split(place, "=")
        bytes = hex(bytes)

        assert binary_part(contents, String.to_integer(offset), byte_size(bytes)) == bytes,
               "line #{line}"
      end

      reader = %Ring.Reader{region: region, base: 0, capacity: region.capacity}
      assert {[{:frame, ^seq, ^payload}], _} = Ring.read(reader)
      assert Ring.field(region, :a, :tail) == head_after
    end
  end
end
