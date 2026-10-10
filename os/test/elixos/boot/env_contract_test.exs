defmodule Elixos.Boot.EnvContractTest do
  @moduledoc """
  Edge cases of the launch contract (PROTOCOL.md §3) that the shipped suite
  does not pin down. Added while implementing M2: the control pipe's write end
  is an inherited fd >= 3, because 0, 1 and 2 are /dev/console.
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 2

  alias Elixos.Boot.Env

  @valid %{
    "ELIXOS_GENERATION" => "7",
    "ELIXOS_MODE" => "normal",
    "ELIXOS_ATTEMPT" => "2",
    "ELIXOS_CTL_FD" => "3"
  }

  test "the control fd is an inherited descriptor, so it is at least 3" do
    for fd <- ["0", "1", "2"] do
      assert Env.parse(%{@valid | "ELIXOS_CTL_FD" => fd}) ==
               {:error, {:invalid, "ELIXOS_CTL_FD"}},
             "ELIXOS_CTL_FD=#{fd} is a console fd, not the control pipe"
    end

    assert {:ok, %Env{ctl_fd: 3}} = Env.parse(@valid)
    assert {:ok, %Env{ctl_fd: 4_294_967_295}} =
             Env.parse(%{@valid | "ELIXOS_CTL_FD" => "4294967295"})
  end

  test "an invalid mode still wins over an invalid control fd" do
    both = %{@valid | "ELIXOS_MODE" => "Rescue", "ELIXOS_CTL_FD" => "2"}
    assert Env.parse(both) == {:error, {:invalid, "ELIXOS_MODE"}}
  end
end
