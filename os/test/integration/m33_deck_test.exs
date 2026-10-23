defmodule Elixos.Integration.M33DeckTest do
  @moduledoc """
  M33: the Elixos side of the deck, in QEMU. Elixos renders into a
  shared-memory framebuffer the coprocessor scans out, a terminal view hosts
  the login REPL, and input arrives as messages from a simulated coprocessor.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 33
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  test "frames rendered by Elixos appear in the shared-memory framebuffer in the protocol's layout" do
    Elixos.NotImplemented.raise!(33, "deck framebuffer protocol in the shared-memory region")
  end

  test "boot lands in the terminal view hosting the login REPL while the serial console stays available" do
    Elixos.NotImplemented.raise!(33, "terminal view hosts the login REPL; serial console still answers")
  end

  test "simulated coprocessor touch events drive the on-screen keyboard into the REPL session" do
    Elixos.NotImplemented.raise!(33, "simulated coprocessor touch input and on-screen keyboard")
  end

  test "the terminal view shows rescue status when booted into rescue" do
    Elixos.NotImplemented.raise!(33, "terminal view shows rescue status")
  end
end
