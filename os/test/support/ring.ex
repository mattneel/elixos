defmodule Elixos.Test.Ring do
  @moduledoc """
  The inter-core ring (docs/PROTOCOL.md §11) in Elixir: the tests' side of a
  shared region file, playing the coprocessor against `elixos-link`, or
  inspecting what the helper left in the region. It mirrors
  shim/src/ring.zig; both are checked against spec/ring.vectors
  (test/elixos/ring_vectors_test.exs).

  The BEAM cannot map the file, so this side uses `pread`/`pwrite` on it; the
  page cache keeps those coherent with the helper's `MAP_SHARED` mapping. A
  4-byte `pread`/`pwrite` is not an atomic access, though (the kernel may copy
  byte by byte), so two rules keep the tests sound:

    * the other side's counter is read until two reads agree (`stable/3`),
      which rules out a torn read of a store in progress;
    * a test that *writes* frames for a running helper to read pauses it
      (SIGSTOP) around the write, so the helper never sees a half-written
      `head`. Torn reads of `tail` by a helper's writer are harmless: they can
      only under-report the free space.
  """

  import Bitwise

  @magic 0x52584C45
  @version 1
  @header 64
  @frame_header 16
  @max_len 65535
  @max_capacity 1 <<< 31

  @fields %{
    magic: 0,
    version: 4,
    capacity: 8,
    writer_epoch: 12,
    head: 16,
    reader_epoch: 20,
    tail: 24,
    dropped: 28
  }

  ## The pure protocol

  @doc "The capacity of each ring in a region of `size` bytes, or `:error`."
  @spec capacity(non_neg_integer()) :: {:ok, pos_integer()} | :error
  def capacity(size) when size > 0 and rem(size, 4096) == 0 do
    usable = div(size, 2) - @header
    {:ok, min(floor_power_of_two(usable), @max_capacity)}
  end

  def capacity(_size), do: :error

  defp floor_power_of_two(n), do: 1 <<< (Integer.digits(n, 2) |> length() |> Kernel.-(1))

  @doc "The largest payload a ring of `capacity` carries."
  def max_len(capacity), do: min(@max_len, div(capacity, 4))

  @doc "Stream bytes a frame with a `len`-byte payload occupies."
  def occupancy(len), do: @frame_header + align8(len)

  defp align8(n), do: n + 7 &&& -8

  @doc "CRC-32 (IEEE) over len, seq and the payload."
  def checksum(len, seq, payload),
    do: :erlang.crc32(<<len::32-little, seq::32-little, payload::binary>>)

  @doc "One encoded frame: header, payload, zero padding."
  @spec encode(non_neg_integer(), binary()) :: binary()
  def encode(seq, payload) do
    len = byte_size(payload)
    pad = align8(len) - len

    <<len::32-little, seq::32-little, checksum(len, seq, payload)::32-little, 0::32,
      payload::binary, 0::size(pad)-unit(8)>>
  end

  @doc "A ring header as the big core initialises it."
  def initial_header(capacity),
    do: <<@magic::32-little, @version::32-little, capacity::32-little, 0::416>>

  @doc """
  The reader's next step when `in_flight` holds exactly the bytes from `tail`
  to `head`: `{:frame, seq, payload, consumed}`, `{:crc, consumed}` (dropped,
  skipped by its len) or `:resync` (dropped, `tail = head`).
  """
  @spec decode(binary()) ::
          {:frame, non_neg_integer(), binary(), pos_integer()} | {:crc, pos_integer()} | :resync
  def decode(
        <<len::32-little, seq::32-little, crc::32-little, _zero::32, rest::binary>> = in_flight
      )
      when len in 1..@max_len do
    consumed = occupancy(len)

    cond do
      consumed > byte_size(in_flight) ->
        :resync

      checksum(len, seq, binary_part(rest, 0, len)) == crc ->
        {:frame, seq, binary_part(rest, 0, len), consumed}

      true ->
        {:crc, consumed}
    end
  end

  def decode(_in_flight), do: :resync

  ## A region file

  defmodule Region do
    @moduledoc false
    defstruct [:fd, :size, :capacity]
  end

  defmodule Writer do
    @moduledoc false
    defstruct [:region, :base, :capacity, seq: 0]
  end

  defmodule Reader do
    @moduledoc false
    defstruct [:region, :base, :capacity, dropped: 0]
  end

  @doc "Creates a zero-filled region file of `size` bytes."
  def create(path, size) do
    {:ok, _} = capacity(size)
    File.write!(path, "")
    {:ok, fd} = :file.open(path, [:read, :write, :raw, :binary])
    :ok = :file.pwrite(fd, size - 1, <<0>>)
    :ok = :file.close(fd)
    path
  end

  @doc "Opens a region file of `size` bytes (closed with the calling process)."
  def open(path, size) do
    {:ok, capacity} = capacity(size)
    {:ok, fd} = :file.open(path, [:read, :write, :raw, :binary])
    %Region{fd: fd, size: size, capacity: capacity}
  end

  @doc "Byte offset of ring `:a` (big writes) or `:b` (little writes)."
  def base(%Region{}, :a), do: 0
  def base(%Region{size: size}, :b), do: div(size, 2)

  @doc "One header field of ring `direction`, read once."
  def field(%Region{fd: fd} = region, direction, name) do
    {:ok, <<value::32-little>>} =
      :file.pread(fd, base(region, direction) + Map.fetch!(@fields, name), 4)

    value
  end

  @doc "Sets one header field (tests use it to damage a ring)."
  def put_field(%Region{fd: fd} = region, direction, name, value) do
    :ok =
      :file.pwrite(fd, base(region, direction) + Map.fetch!(@fields, name), <<value::32-little>>)
  end

  @doc "A field the other side writes: read until two reads agree."
  def stable(region, direction, name) do
    first = field(region, direction, name)

    case field(region, direction, name) do
      ^first -> first
      _moved -> stable(region, direction, name)
    end
  end

  @doc "Magic, version and the capacity the region size implies."
  def valid?(%Region{capacity: capacity} = region, direction) do
    field(region, direction, :magic) == @magic and field(region, direction, :version) == @version and
      field(region, direction, :capacity) == capacity
  end

  @doc "The big core's start: initialises each invalid ring. Returns the ones it initialised."
  def prepare(%Region{fd: fd, size: size, capacity: capacity} = region) do
    for direction <- [:a, :b], not valid?(region, direction) do
      base = base(region, direction)
      :ok = put_field(region, direction, :magic, 0)
      :ok = :file.pwrite(fd, base + 4, <<0::size((div(size, 2) - 4) * 8)>>)
      :ok = put_field(region, direction, :capacity, capacity)
      :ok = put_field(region, direction, :version, @version)
      :ok = put_field(region, direction, :magic, @magic)
      direction
    end
  end

  @doc "A (re)starting writer: bumps the writer epoch, continues at head."
  def writer(%Region{} = region, direction) do
    true = valid?(region, direction)

    put_field(
      region,
      direction,
      :writer_epoch,
      field(region, direction, :writer_epoch) + 1 &&& 0xFFFFFFFF
    )

    %Writer{region: region, base: base(region, direction), capacity: region.capacity}
  end

  @doc """
  A (re)starting reader: bumps the reader epoch, sets tail = head. With
  `restart: false`, the reader that was there all along: it continues at
  `tail`, so whatever is in flight is still read.
  """
  def reader(%Region{} = region, direction, opts \\ []) do
    true = valid?(region, direction)

    if Keyword.get(opts, :restart, true) do
      put_field(
        region,
        direction,
        :reader_epoch,
        field(region, direction, :reader_epoch) + 1 &&& 0xFFFFFFFF
      )

      put_field(region, direction, :tail, stable(region, direction, :head))
    end

    %Reader{region: region, base: base(region, direction), capacity: region.capacity}
  end

  @doc """
  Writes as many of `payloads` as fit, in order, then publishes them with
  one `head` store. Returns `{written, writer}`; `written < length(payloads)`
  means the ring was full (backpressure): nothing unread was touched.
  """
  def write(%Writer{} = writer, payloads) when is_list(payloads) do
    %Writer{region: region, base: base, capacity: capacity} = writer
    direction = direction(writer)
    head = field(region, direction, :head)
    tail = stable(region, direction, :tail)
    used = head - tail &&& 0xFFFFFFFF
    free = if used > capacity, do: 0, else: capacity - used

    {frames, written, _free} =
      Enum.reduce_while(payloads, {[], 0, free}, fn payload, {frames, written, free} ->
        len = byte_size(payload)
        if len < 1 or len > max_len(capacity), do: raise(ArgumentError, "payload length #{len}")
        need = occupancy(len)

        if need <= free,
          do:
            {:cont,
             {[encode(writer.seq + written &&& 0xFFFFFFFF, payload) | frames], written + 1,
              free - need}},
          else: {:halt, {frames, written, free}}
      end)

    stream = frames |> Enum.reverse() |> IO.iodata_to_binary()

    if stream != "" do
      put_stream(region, base, capacity, head, stream)
      put_field(region, direction, :head, head + byte_size(stream) &&& 0xFFFFFFFF)
    end

    {written, %{writer | seq: writer.seq + written &&& 0xFFFFFFFF}}
  end

  @doc """
  Reads up to `limit` frames with one `tail` store. Returns `{results,
  reader}`, each result `{:frame, seq, payload}` or `:dropped`; an empty list
  means the ring was empty.
  """
  def read(%Reader{} = reader, limit \\ :infinity) do
    %Reader{region: region, base: base, capacity: capacity} = reader
    direction = direction(reader)
    head = stable(region, direction, :head)
    tail = field(region, direction, :tail)
    in_flight = head - tail &&& 0xFFFFFFFF

    cond do
      in_flight == 0 ->
        {[], reader}

      in_flight > capacity or in_flight < @frame_header ->
        finish(reader, direction, head, [:dropped], 1)

      true ->
        stream = get_stream(region, base, capacity, tail, in_flight)
        {results, consumed, dropped, resynced} = parse(stream, limit, [], 0, 0)
        new_tail = if resynced, do: head, else: tail + consumed &&& 0xFFFFFFFF
        finish(reader, direction, new_tail, results, dropped)
    end
  end

  defp parse(_stream, 0, results, consumed, dropped),
    do: {Enum.reverse(results), consumed, dropped, false}

  defp parse(<<>>, _limit, results, consumed, dropped),
    do: {Enum.reverse(results), consumed, dropped, false}

  defp parse(stream, limit, results, consumed, dropped) do
    next = if limit == :infinity, do: :infinity, else: limit - 1

    case decode(stream) do
      {:frame, seq, payload, n} ->
        parse(
          binary_part(stream, n, byte_size(stream) - n),
          next,
          [{:frame, seq, payload} | results],
          consumed + n,
          dropped
        )

      {:crc, n} ->
        parse(
          binary_part(stream, n, byte_size(stream) - n),
          next,
          [:dropped | results],
          consumed + n,
          dropped + 1
        )

      :resync ->
        {Enum.reverse([:dropped | results]), consumed, dropped + 1, true}
    end
  end

  defp finish(reader, direction, tail, results, dropped) do
    if dropped > 0 do
      count = field(reader.region, direction, :dropped)
      put_field(reader.region, direction, :dropped, count + dropped &&& 0xFFFFFFFF)
    end

    put_field(reader.region, direction, :tail, tail)
    {results, %{reader | dropped: reader.dropped + dropped}}
  end

  @doc "Raw stream bytes at position `at` of ring `direction` (to damage a frame)."
  def put_bytes(%Region{capacity: capacity} = region, direction, at, bytes),
    do: put_stream(region, base(region, direction), capacity, at, bytes)

  def get_bytes(%Region{capacity: capacity} = region, direction, at, count),
    do: get_stream(region, base(region, direction), capacity, at, count)

  defp direction(%{region: region, base: base}),
    do: if(base == base(region, :a), do: :a, else: :b)

  defp put_stream(%Region{fd: fd}, base, capacity, at, bytes) do
    start = at &&& capacity - 1
    first = min(byte_size(bytes), capacity - start)
    :ok = :file.pwrite(fd, base + @header + start, binary_part(bytes, 0, first))

    if first < byte_size(bytes),
      do:
        :ok =
          :file.pwrite(fd, base + @header, binary_part(bytes, first, byte_size(bytes) - first))

    :ok
  end

  defp get_stream(%Region{fd: fd}, base, capacity, at, count) do
    start = at &&& capacity - 1
    first = min(count, capacity - start)
    {:ok, head} = :file.pread(fd, base + @header + start, first)

    if first < count do
      {:ok, rest} = :file.pread(fd, base + @header, count - first)
      head <> rest
    else
      head
    end
  end
end
