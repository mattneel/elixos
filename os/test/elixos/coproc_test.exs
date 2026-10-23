defmodule Elixos.CoprocTest do
  @moduledoc """
  M29: Elixos.Coproc supervises the link to the coprocessor node - connect,
  monitor, reconnect, and run calls - against AtomVM's Unix build on the host.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 29

  test "Elixos.Coproc connects to a host AtomVM node with the cookie and runs a call on it" do
    Elixos.NotImplemented.raise!(29, "Elixos.Coproc connect and call against host AtomVM")
  end

  test "Elixos.Coproc reconnects after the AtomVM node restarts" do
    Elixos.NotImplemented.raise!(29, "Elixos.Coproc monitor and reconnect")
  end

  test "Elixos.Coproc refuses a wrong cookie" do
    Elixos.NotImplemented.raise!(29, "Elixos.Coproc rejects a peer with the wrong cookie")
  end
end
