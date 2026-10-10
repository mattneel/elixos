defmodule Elixos.MnesiaTest do
  @moduledoc """
  Mnesia's directory is pinned (M15 finding). Its default is `Mnesia.<node>`
  relative to the working directory, the VM never changes that (ADR-016), and
  the root is the RAM-backed initramfs: a schema would quietly live in memory
  and die with the boot. The pin is what makes the default a place that
  survives - before anything creates a disc copy.
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 15

  test "mnesia's directory is /priv, absolute, before anything uses a disc copy" do
    dir = Application.get_env(:mnesia, :dir)

    assert dir != nil,
           "mnesia's directory must be pinned: the default is the working directory"

    assert Path.type(to_string(dir)) == :absolute
    assert String.starts_with?(to_string(dir), "/priv/")

    # And mnesia resolves what was pinned, not a fallback.
    assert :mnesia.system_info(:is_running) == :yes
    assert to_string(:mnesia.system_info(:directory)) == to_string(dir)
  end
end
