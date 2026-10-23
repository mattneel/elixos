defmodule Elixos.CoprocRingTest do
  @moduledoc """
  M31: the inter-core ring protocol and the Zig helper that bridges it to a TUN
  device, tested on the host with a shared-memory file standing in for the
  reserved region.

  The helper is the real `elixos-link` (built by `zig build`), each instance
  in its own unprivileged user and network namespace
  (`Elixos.Test.RingLink`). The other side of a ring is either a second
  helper or the tests' Elixir ring (`Elixos.Test.Ring`) on the same file.
  Traffic comes from python3 sockets inside the namespaces. Without user
  namespaces, /dev/net/tun, util-linux or python3 these tests fail, saying
  which; they never skip. Building the helper and creating namespaces is host
  orchestration, so a candidate's portable suite (`Elixos.Candidate`)
  excludes this module, as it does other build-driving tests.
  """
  use ExUnit.Case, async: false

  alias Elixos.Test.{Ring, RingLink}

  @moduletag milestone: 31
  @moduletag :host_orchestration
  @moduletag :tmp_dir
  @moduletag timeout: 120_000

  # Sends datagrams first..first+n-1 to host:port, each `size` bytes: the
  # index as 8 big-endian bytes, then bytes (index + k) mod 256.
  @sender """
  import socket, sys, time
  host, port, n, size, gap, first = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), int(sys.argv[6])
  s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
  base = bytes(range(256)) * (size // 256 + 2)
  for i in range(first, first + n):
      s.sendto(i.to_bytes(8, "big") + base[i % 256:i % 256 + size - 8], (host, port))
      if gap:
          time.sleep(gap)
  """

  # Prints "ready", then each datagram's payload in hex, until `count`
  # arrived or `quiet` seconds pass without one; then "done".
  @receiver """
  import socket, sys
  s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
  s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 22)
  s.bind((sys.argv[1], int(sys.argv[2])))
  s.settimeout(float(sys.argv[4]))
  print("ready", flush=True)
  for _ in range(int(sys.argv[3])):
      try:
          data, _ = s.recvfrom(65536)
      except socket.timeout:
          break
      print(data.hex(), flush=True)
  print("done", flush=True)
  """

  # Receives one TCP stream on host:port; prints its length and SHA-256.
  @tcp_sink """
  import hashlib, socket, sys
  l = socket.socket()
  l.bind((sys.argv[1], int(sys.argv[2])))
  l.listen(1)
  print("ready", flush=True)
  c, _ = l.accept()
  h, n = hashlib.sha256(), 0
  while True:
      d = c.recv(1 << 16)
      if not d:
          break
      h.update(d)
      n += len(d)
  print(n, h.hexdigest(), flush=True)
  """

  # Sends `n` bytes (a fixed pseudo-random block, repeated) over TCP to
  # host:port; prints the bytes, their SHA-256 and the seconds it took.
  @tcp_source """
  import hashlib, random, socket, sys, time
  host, port, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
  block = random.Random(31).randbytes(1 << 16)
  h = hashlib.sha256()
  c = socket.create_connection((host, port), timeout=60)
  start, sent = time.monotonic(), 0
  while sent < n:
      chunk = block[: min(len(block), n - sent)]
      c.sendall(chunk)
      h.update(chunk)
      sent += len(chunk)
  c.shutdown(socket.SHUT_WR)
  c.recv(1)
  print(sent, h.hexdigest(), round(time.monotonic() - start, 3), flush=True)
  """

  @big "10.9.0.1"
  @little "10.9.0.2"

  test "frames written on one side of the ring arrive intact and in order at the sustained throughput",
       %{tmp_dir: dir} do
    # The helper writes ring A from its TUN device as fast as python3 can
    # send; the Elixir reader drains it concurrently. Capacity 256 KiB, so
    # the 21 MB stream wraps the data area some eighty times.
    size = 528_384
    path = Ring.create(Path.join(dir, "region"), size)
    big = RingLink.start(path, size, address: "#{@big}/30")
    region = Ring.open(path, size)
    assert region.capacity == 256 * 1024
    reader = Ring.reader(region, :a)
    count = 20_000
    datagram = 1024

    started = System.monotonic_time(:microsecond)

    sender =
      RingLink.spawn(big, [
        "python3",
        "-c",
        @sender,
        @little,
        "9",
        "#{count}",
        "#{datagram}",
        "0",
        "0"
      ])

    {frames, reader} = drain(reader, sender, [])
    # Everything still queued on TUN is in the ring once tx stops moving.
    stats = settle(big)
    {rest, reader} = drain_until(reader, stats.tx - length(frames), [])
    frames = frames ++ rest

    # Every frame the helper wrote arrived, in ring order, and none was corrupt.
    assert length(frames) == stats.tx
    assert Enum.map(frames, fn {seq, _payload, _at} -> seq end) == Enum.to_list(0..(stats.tx - 1))
    assert reader.dropped == 0 and Ring.field(region, :a, :dropped) == 0
    assert stats.dropped == 0

    # Each frame is one intact datagram; datagrams are in sending order (TUN
    # may have dropped some before the ring under load, never reordered).
    indices = Enum.map(frames, fn {_seq, payload, _at} -> datagram_index!(payload, datagram) end)
    assert indices == Enum.sort(Enum.uniq(indices))
    # A full ring refuses (and counts) what the reader has no room for yet;
    # a slow reader may cost frames, never the stream's integrity. At least
    # a tenth of the datagrams, eight times the capacity, must get through.
    assert length(frames) >= div(count, 10),
           "only #{length(frames)} of #{count} datagrams reached the ring"

    # Sustained rate: every delivered byte over the whole run, python3's
    # start-up included, from the Zig writer to the Elixir reader. Measured
    # 54-81 MB/s (7000-9800 frames in 0.13-0.14 s; WSL2, 32 threads). 5 MB/s,
    # a tenth of that, holds on a loaded machine and still catches a loop
    # that waits out its 1 ms idle poll between packets (about 1 MB/s).
    {_, _, last} = List.last(frames)
    bytes = frames |> Enum.map(fn {_, payload, _} -> byte_size(payload) end) |> Enum.sum()
    seconds = (last - started) / 1_000_000
    rate = bytes / seconds

    assert rate >= 5_000_000,
           "ring throughput #{round(rate / 1000)} kB/s (#{length(frames)} frames in #{seconds} s)"
  end

  test "a full ring applies backpressure to the writer instead of overwriting unread frames", %{
    tmp_dir: dir
  } do
    # Capacity 4096: four 928-byte IP packets (944 bytes as frames) fit, a fifth does not.
    size = 12_288
    path = Ring.create(Path.join(dir, "region"), size)
    big = RingLink.start(path, size, address: "#{@big}/30")
    region = Ring.open(path, size)
    assert region.capacity == 4096

    RingLink.cmd(big, ["python3", "-c", @sender, @little, "9", "20", "900", "0.002", "0"])
    stats = await_stats(big, &(&1.tx + &1.full == 20))
    assert stats == %{tx: 4, rx: 0, full: 16, dropped: 0}
    head = Ring.field(region, :a, :head)
    assert head == 4 * Ring.occupancy(928)
    assert Ring.field(region, :a, :tail) == 0

    # More traffic is refused as well, and the ring is untouched.
    RingLink.cmd(big, ["python3", "-c", @sender, @little, "9", "5", "900", "0.002", "20"])
    assert await_stats(big, &(&1.tx + &1.full == 25)) == %{tx: 4, rx: 0, full: 21, dropped: 0}
    assert Ring.field(region, :a, :head) == head

    # The four refused-to-be-overwritten frames are the first four datagrams, intact.
    reader = Ring.reader(region, :a, restart: false)
    {results, reader} = Ring.read(reader)
    assert [{:frame, 0, p0}, {:frame, 1, p1}, {:frame, 2, p2}, {:frame, 3, p3}] = results
    assert Enum.map([p0, p1, p2, p3], &datagram_index!(&1, 900)) == [0, 1, 2, 3]

    # Once read, the space is the writer's again.
    RingLink.cmd(big, ["python3", "-c", @sender, @little, "9", "4", "900", "0.002", "30"])
    assert await_stats(big, &(&1.tx + &1.full == 29)) == %{tx: 8, rx: 0, full: 21, dropped: 0}
    {results, _reader} = Ring.read(reader)
    assert [4, 5, 6, 7] == Enum.map(results, fn {:frame, seq, _} -> seq end)

    assert [30, 31, 32, 33] ==
             Enum.map(results, fn {:frame, _, payload} -> datagram_index!(payload, 900) end)
  end

  test "a corrupted frame is detected and dropped, and the ring keeps going", %{tmp_dir: dir} do
    # The Elixir ring plays the little core writing ring B; the helper reads
    # it onto TUN, where a socket in its namespace receives the datagrams.
    size = 12_288
    path = Ring.create(Path.join(dir, "region"), size)
    big = RingLink.start(path, size, address: "#{@big}/30")
    region = Ring.open(path, size)

    receiver =
      RingLink.spawn(big, ["python3", "-c", @receiver, @big, "5000", "3", "10"]) |> await_ready()

    writer = Ring.writer(region, :b)

    # A flipped payload byte fails the CRC: that frame alone is dropped.
    one = udp("one")
    RingLink.pause(big)
    {3, writer} = Ring.write(writer, [one, udp("two"), udp("three")])
    at = Ring.occupancy(byte_size(one)) + 16 + 30
    <<byte>> = Ring.get_bytes(region, :b, at, 1)
    Ring.put_bytes(region, :b, at, <<Bitwise.bxor(byte, 0x01)>>)
    RingLink.resume(big)
    assert await_stats(big, &(&1.rx + &1.dropped == 3)) == %{tx: 0, rx: 2, full: 0, dropped: 1}
    assert Ring.field(region, :b, :dropped) == 1

    # A len outside 1-65535 makes the stream unparseable: one drop, tail = head.
    RingLink.pause(big)
    head = Ring.field(region, :b, :head)
    {2, writer} = Ring.write(writer, [udp("lost"), udp("lost too")])
    Ring.put_bytes(region, :b, head, <<70_000::32-little>>)
    RingLink.resume(big)
    assert await_stats(big, &(&1.dropped == 2)) == %{tx: 0, rx: 2, full: 0, dropped: 2}
    assert Ring.field(region, :b, :tail) == Ring.field(region, :b, :head)

    # Later frames arrive.
    RingLink.pause(big)
    {1, _writer} = Ring.write(writer, [udp("four")])
    RingLink.resume(big)
    assert await_stats(big, &(&1.rx == 3)) == %{tx: 0, rx: 3, full: 0, dropped: 2}
    assert received(receiver) == ["one", "three", "four"]
    assert Ring.field(region, :b, :dropped) == 2
  end

  test "either side restarting resynchronises the ring without losing later frames", %{
    tmp_dir: dir
  } do
    size = 266_240
    path = Ring.create(Path.join(dir, "region"), size)
    region = Ring.open(path, size)
    big = RingLink.start(path, size, address: "#{@big}/30")
    little = RingLink.start(path, size, side: :little, address: "#{@little}/30")

    # The little side (reader of A, writer of B) restarts while three frames
    # for it are in flight: those were for its previous incarnation and are
    # skipped; every frame written after the restart arrives.
    RingLink.pause(little)
    RingLink.cmd(big, ["python3", "-c", @sender, @little, "5000", "3", "64", "0", "0"])
    assert await_stats(big, &(&1.tx + &1.full == 3)) == %{tx: 3, rx: 0, full: 0, dropped: 0}
    in_flight = Ring.field(region, :a, :head) - Ring.field(region, :a, :tail)
    assert in_flight == 3 * Ring.occupancy(20 + 8 + 64)
    {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(little.os_pid)])
    little = RingLink.start(path, size, side: :little, address: "#{@little}/30")
    assert Ring.field(region, :a, :reader_epoch) == 2
    assert Ring.field(region, :b, :writer_epoch) == 2
    assert Ring.field(region, :a, :tail) == Ring.field(region, :a, :head)

    receiver =
      RingLink.spawn(little, ["python3", "-c", @receiver, @little, "5000", "100", "5"])
      |> await_ready()

    RingLink.cmd(big, ["python3", "-c", @sender, @little, "5000", "100", "64", "0.001", "100"])
    assert Enum.map(received(receiver), &datagram_index!(&1, 64)) == Enum.to_list(100..199)
    assert RingLink.stats(little) == %{tx: 0, rx: 100, full: 0, dropped: 0}

    # The big side (writer of A, reader of B) restarts while three of its
    # frames are still unread: a restarted writer keeps them and continues at
    # head, so the little side gets all six in order.
    receiver =
      RingLink.spawn(little, ["python3", "-c", @receiver, @little, "5000", "6", "5"])
      |> await_ready()

    RingLink.pause(little)
    RingLink.cmd(big, ["python3", "-c", @sender, @little, "5000", "3", "64", "0", "200"])
    assert await_stats(big, &(&1.tx + &1.full == 106)).tx == 106
    head = Ring.field(region, :a, :head)
    RingLink.stop(big)
    big = RingLink.start(path, size, address: "#{@big}/30")
    assert Ring.field(region, :a, :writer_epoch) == 2
    assert Ring.field(region, :b, :reader_epoch) == 2
    assert Ring.field(region, :a, :head) == head
    RingLink.cmd(big, ["python3", "-c", @sender, @little, "5000", "3", "64", "0", "203"])
    assert await_stats(big, &(&1.tx + &1.full == 3)).tx == 3
    RingLink.resume(little)
    assert Enum.map(received(receiver), &datagram_index!(&1, 64)) == Enum.to_list(200..205)
    assert Ring.field(region, :a, :dropped) == 0
    assert Ring.field(region, :b, :dropped) == 0
  end

  test "the helper carries IP packets between the ring and a TUN device", %{tmp_dir: dir} do
    # Two helpers on one region file: a complete point-to-point IP link.
    size = 266_240
    path = Ring.create(Path.join(dir, "region"), size)
    big = RingLink.start(path, size, address: "#{@big}/30")
    little = RingLink.start(path, size, side: :little, address: "#{@little}/30")

    assert RingLink.cmd(big, ["ping", "-c", "5", "-i", "0.2", "-W", "2", @little]) =~
             " 5 received"

    assert RingLink.cmd(little, ["ping", "-c", "5", "-i", "0.2", "-W", "2", @big]) =~
             " 5 received"

    # TCP across it: 8 MiB, byte for byte.
    {sink, rest} =
      RingLink.spawn(little, ["python3", "-c", @tcp_sink, @little, "7000"]) |> await_ready()

    bytes = 8 * 1024 * 1024

    [sent, digest, _seconds] =
      RingLink.cmd(big, ["python3", "-c", @tcp_source, @little, "7000", "#{bytes}"])
      |> String.split()

    assert sent == "#{bytes}"
    {output, 0} = RingLink.collect(sink, rest, 30_000)
    assert "#{bytes} #{digest}\n" == output

    # Packets crossed both rings, intact; then a clean exit with the stats line.
    big_stats = RingLink.stop(big)
    little_stats = RingLink.stop(little)
    assert big_stats.dropped == 0 and little_stats.dropped == 0
    assert big_stats.tx > 10 and big_stats.rx > 10
    assert little_stats.rx == big_stats.tx
    assert big_stats.rx == little_stats.tx
  end

  ## Helpers

  # Reads frames until the sender port exits: [{seq, payload, microseconds}].
  defp drain(reader, sender, acc) do
    {results, reader} = Ring.read(reader)
    now = System.monotonic_time(:microsecond)
    acc = Enum.reduce(results, acc, &[frame!(&1, now) | &2])

    receive do
      {^sender, {:exit_status, 0}} -> {Enum.reverse(acc), reader}
      {^sender, {:exit_status, status}} -> flunk("sender exited #{status}")
      {^sender, {:data, data}} -> flunk("sender: " <> data)
    after
      0 ->
        if results == [], do: Process.sleep(1)
        drain(reader, sender, acc)
    end
  end

  defp drain_until(reader, missing, acc, deadline \\ System.monotonic_time(:millisecond) + 10_000)

  defp drain_until(reader, missing, acc, _deadline) when missing <= 0,
    do: {Enum.reverse(acc), reader}

  defp drain_until(reader, missing, acc, deadline) do
    if System.monotonic_time(:millisecond) > deadline,
      do: flunk("#{missing} frames never arrived")

    {results, reader} = Ring.read(reader)
    now = System.monotonic_time(:microsecond)
    if results == [], do: Process.sleep(1)

    drain_until(
      reader,
      missing - length(results),
      Enum.reduce(results, acc, &[frame!(&1, now) | &2]),
      deadline
    )
  end

  defp frame!({:frame, seq, payload}, now), do: {seq, payload, now}
  defp frame!(:dropped, _now), do: flunk("the reader dropped a frame")

  # Stats once tx + full stop moving (TUN has nothing queued for the ring).
  defp settle(link, previous \\ nil) do
    Process.sleep(50)
    stats = RingLink.stats(link)
    if stats == previous, do: stats, else: settle(link, stats)
  end

  defp await_stats(link, done?, deadline \\ System.monotonic_time(:millisecond) + 10_000) do
    stats = RingLink.stats(link)

    cond do
      done?.(stats) ->
        stats

      System.monotonic_time(:millisecond) > deadline ->
        flunk("stats never got there: #{inspect(stats)}")

      true ->
        Process.sleep(10) && await_stats(link, done?, deadline)
    end
  end

  # Waits for a namespace program's "ready" line: {port, output after it}.
  defp await_ready(port, acc \\ "") do
    receive do
      {^port, {:data, data}} ->
        case String.split(acc <> data, "ready\n", parts: 2) do
          [_, rest] -> {port, rest}
          [acc] -> await_ready(port, acc)
        end

      {^port, {:exit_status, status}} ->
        flunk("exited #{status} before ready: " <> acc)
    after
      10_000 -> flunk("never ready: " <> acc)
    end
  end

  # The payloads a receiver printed after "ready", decoded.
  defp received({port, rest}) do
    {output, 0} = RingLink.collect(port, rest, 30_000)
    ["done" | lines] = output |> String.split("\n", trim: true) |> Enum.reverse()
    lines |> Enum.reverse() |> Enum.map(&Base.decode16!(&1, case: :lower))
  end

  # An IPv4/UDP packet carrying `data` from the little side to the helper's
  # socket: 10.9.0.2:5001 -> 10.9.0.1:5000, UDP checksum 0 (none).
  defp udp(data) do
    length = 20 + 8 + byte_size(data)
    header = <<0x45, 0, length::16, 0::16, 0x4000::16, 64, 17, 0::16, 10, 9, 0, 2, 10, 9, 0, 1>>
    <<pre::binary-size(10), 0::16, post::binary>> = header

    <<pre::binary, ip_checksum(header)::16, post::binary, 5001::16, 5000::16,
      8 + byte_size(data)::16, 0::16, data::binary>>
  end

  defp ip_checksum(header) do
    sum = for <<word::16 <- header>>, reduce: 0, do: (acc -> acc + word)
    sum = Bitwise.band(sum, 0xFFFF) + Bitwise.bsr(sum, 16)
    sum = Bitwise.band(sum, 0xFFFF) + Bitwise.bsr(sum, 16)
    Bitwise.bxor(sum, 0xFFFF)
  end

  # A sender datagram, raw or inside its IPv4/UDP packet: checks the pattern
  # and returns its index.
  defp datagram_index!(
         <<0x45, _::binary-size(8), 17, _::binary-size(10), _udp::binary-size(8), data::binary>>,
         size
       )
       when byte_size(data) == size,
       do: datagram_index!(data, size)

  defp datagram_index!(<<index::64, rest::binary>>, size) when byte_size(rest) == size - 8 do
    assert rest == pattern(index, size - 8), "datagram #{index} damaged"
    index
  end

  defp datagram_index!(other, size),
    do: flunk("not a #{size}-byte sender datagram: #{inspect(other, limit: 40)}")

  @pattern :binary.copy(:binary.list_to_bin(Enum.to_list(0..255)), 8)

  defp pattern(index, length), do: binary_part(@pattern, rem(index, 256), length)
end
