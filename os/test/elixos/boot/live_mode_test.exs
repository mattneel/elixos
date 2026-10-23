defmodule Elixos.Boot.LiveModeTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 27

  alias Elixos.Boot.Cmdline

  test "Live console policy follows the shim's last valid flag, ignoring malformed overrides" do
    assert Cmdline.live?("elixos.live elixos.live=yes")
    assert Cmdline.live?("elixos.live=0 elixos.live=1 elixos.live=01")
    refute Cmdline.live?("elixos.live=1 elixos.live=0 elixos.live=true")
    refute Cmdline.live?("elixos.live=2 elixos.live= elixos.live=1=0")
    refute Cmdline.live?("other.live=1 elixos.live_extra=1")
  end
end
