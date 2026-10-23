defmodule Elixos.Boot.RuntimeTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 27

  alias Elixos.Boot.Env

  @launch %{
    "ELIXOS_GENERATION" => "3",
    "ELIXOS_MODE" => "normal",
    "ELIXOS_ATTEMPT" => "1",
    "ELIXOS_CTL_FD" => "4"
  }

  test "a runtime marker without the real launch contract does not impersonate the OS" do
    assert Env.runtime(%{"ELIXOS_RUNTIME" => "container"}) == {:ok, :host}
    assert Env.runtime(%{}) == {:ok, :host}

    assert Env.runtime(%{"ELIXOS_RUNTIME" => "container", "ELIXOS_MODE" => "normal"}) ==
             {:error, {:missing, "ELIXOS_GENERATION"}}
  end

  test "the same launch contract distinguishes a shared kernel from a machine boot" do
    assert Env.runtime(@launch) == {:ok, :machine}
    assert Env.runtime(Map.put(@launch, "ELIXOS_RUNTIME", "machine")) == {:ok, :machine}
    assert Env.runtime(Map.put(@launch, "ELIXOS_RUNTIME", "container")) == {:ok, :container}

    rescue_env =
      @launch |> Map.put("ELIXOS_MODE", "rescue") |> Map.put("ELIXOS_RUNTIME", "container")

    assert Env.runtime(rescue_env) == {:ok, :container}
  end

  test "invalid explicit runtimes fail instead of claiming machine guarantees" do
    for runtime <- ["", "host", "kvm", "Container"] do
      assert Env.runtime(Map.put(@launch, "ELIXOS_RUNTIME", runtime)) ==
               {:error, {:invalid, "ELIXOS_RUNTIME"}}
    end
  end
end
