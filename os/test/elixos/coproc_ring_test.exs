defmodule Elixos.CoprocRingTest do
  @moduledoc """
  M31: the inter-core ring protocol and the Zig helper that bridges it to a TUN
  device, tested on the host with a shared-memory file standing in for the
  reserved region.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 31
  @moduletag :tmp_dir

  test "frames written on one side of the ring arrive intact and in order at the sustained throughput" do
    Elixos.NotImplemented.raise!(31, "ring throughput over a shared-memory file")
  end

  test "a full ring applies backpressure to the writer instead of overwriting unread frames" do
    Elixos.NotImplemented.raise!(31, "ring backpressure")
  end

  test "a corrupted frame is detected and dropped, and the ring keeps going" do
    Elixos.NotImplemented.raise!(31, "ring corruption detection")
  end

  test "either side restarting resynchronises the ring without losing later frames" do
    Elixos.NotImplemented.raise!(31, "ring survives either side restarting")
  end

  test "the helper carries IP packets between the ring and a TUN device" do
    Elixos.NotImplemented.raise!(31, "ring-to-TUN helper over a shared-memory file")
  end
end
