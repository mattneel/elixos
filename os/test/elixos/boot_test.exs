defmodule Elixos.BootTest do
  @moduledoc """
  Boot facts (M4). The QEMU tests read the same map from the console; these
  cover the dev-host path, where there is no shim.
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 4

  alias Elixos.Boot

  test "on the dev host the mode is :host and there is no generation" do
    assert Boot.info() ==
             %{
               arch: Boot.arch(),
               generation: nil,
               mode: :host,
               attempt: nil,
               version: Boot.version()
             }
  end

  test "the arch is the short marker of ERTS's target triple" do
    [short | _] = String.split(to_string(:erlang.system_info(:system_architecture)), "-")

    assert Boot.arch() == short
    assert Boot.info().arch == short
  end

  test "the version is the :elixos application's" do
    assert Boot.version() == "0.1.0"
    assert Application.spec(:elixos, :vsn) |> to_string() == Boot.version()
  end

  test "Elixos.info/0 is the same map" do
    assert Elixos.info() == Boot.info()
  end
end
