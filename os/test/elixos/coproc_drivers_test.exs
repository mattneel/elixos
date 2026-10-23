defmodule Elixos.CoprocDriversTest do
  @moduledoc """
  M32: the coprocessor exposes the subsystems the M30 gate assigned it as
  Erlang processes. Tested on the host against AtomVM's Unix build with
  simulated drivers in place of the K230's vendor RTOS drivers.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 32

  test "each coprocessor-owned subsystem is an Erlang process reachable from Elixos" do
    Elixos.NotImplemented.raise!(32, "simulated coprocessor drivers exposed as Erlang processes")
  end

  test "the coprocessor's drivers keep running while the Elixos BEAM restarts" do
    Elixos.NotImplemented.raise!(32, "coprocessor survives an Elixos BEAM restart")
  end

  test "the coprocessor's drivers keep running while Elixos switches generations" do
    Elixos.NotImplemented.raise!(32, "coprocessor survives a generation switch")
  end
end
