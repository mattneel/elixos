defmodule Elixos.Boot.EnvTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 2

  alias Elixos.Boot.Env

  @valid %{
    "ELIXOS_GENERATION" => "7",
    "ELIXOS_MODE" => "normal",
    "ELIXOS_ATTEMPT" => "2",
    "ELIXOS_CTL_FD" => "3"
  }

  test "no ELIXOS_* variables means we are on the dev host" do
    assert Env.parse(%{"HOME" => "/root", "TERM" => "linux"}) == {:ok, :host}
    assert Env.parse(%{}) == {:ok, :host}
  end

  test "parses the full contract" do
    assert Env.parse(@valid) ==
             {:ok, %Env{generation: 7, mode: :normal, attempt: 2, ctl_fd: 3}}
  end

  test "rescue mode and generation 0 (the factory)" do
    env = %{@valid | "ELIXOS_MODE" => "rescue", "ELIXOS_GENERATION" => "0"}
    assert {:ok, %Env{generation: 0, mode: :rescue}} = Env.parse(env)
  end

  test "other variables are ignored" do
    assert {:ok, %Env{}} = Env.parse(Map.put(@valid, "PATH", "/factory/bin"))
  end

  test "a partial contract names the first missing variable, in table order" do
    assert Env.parse(Map.delete(@valid, "ELIXOS_MODE")) == {:error, {:missing, "ELIXOS_MODE"}}

    partial = @valid |> Map.delete("ELIXOS_ATTEMPT") |> Map.delete("ELIXOS_CTL_FD")
    assert Env.parse(partial) == {:error, {:missing, "ELIXOS_ATTEMPT"}}
  end

  test "malformed values name the first invalid variable, in table order" do
    assert Env.parse(%{@valid | "ELIXOS_MODE" => "Normal"}) == {:error, {:invalid, "ELIXOS_MODE"}}

    both = %{@valid | "ELIXOS_GENERATION" => "x", "ELIXOS_CTL_FD" => "y"}
    assert Env.parse(both) == {:error, {:invalid, "ELIXOS_GENERATION"}}
  end

  test "numbers are canonical decimal u32 (PROTOCOL.md §1)" do
    for key <- ["ELIXOS_GENERATION", "ELIXOS_ATTEMPT", "ELIXOS_CTL_FD"],
        bad <- ["", "07", "-1", "+1", " 1", "1.0", "4294967296", "0x3"] do
      assert Env.parse(%{@valid | key => bad}) == {:error, {:invalid, key}},
             "#{key}=#{inspect(bad)} must be invalid"
    end

    assert {:ok, %Env{generation: 4_294_967_295}} =
             Env.parse(%{@valid | "ELIXOS_GENERATION" => "4294967295"})
  end
end
