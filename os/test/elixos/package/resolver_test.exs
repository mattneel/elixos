defmodule Elixos.Package.ResolverTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 10

  alias Elixos.Package.Resolver

  @os "0.1.3"

  defp pkg(app, version, deps \\ %{}), do: %{app: app, version: version, deps: deps}

  test "a fresh install of an app and its dependency" do
    incoming = [pkg(:my_app, "1.0.0", %{jason: "~> 1.4"}), pkg(:jason, "1.4.4")]

    assert Resolver.plan([], incoming, @os) ==
             {:ok, %{install: [:jason, :my_app], upgrade: [], unchanged: []}}
  end

  test "a compatible upgrade of a shared dependency" do
    installed = [pkg(:a, "1.0.0", %{jason: "~> 1.4"}), pkg(:jason, "1.4.0")]
    incoming = [pkg(:jason, "1.4.4")]

    assert Resolver.plan(installed, incoming, @os) ==
             {:ok, %{install: [], upgrade: [:jason], unchanged: [:a]}}
  end

  test "an install that would break an installed app is refused (one version per package)" do
    installed = [pkg(:a, "1.0.0", %{jason: "~> 1.4"}), pkg(:jason, "1.4.4")]
    incoming = [pkg(:b, "0.1.0", %{jason: "~> 2.0"}), pkg(:jason, "2.0.1")]

    assert Resolver.plan(installed, incoming, @os) ==
             {:error, [{:unsatisfied, :a, :jason, "~> 1.4", "2.0.1"}]}
  end

  test "a missing dependency" do
    incoming = [pkg(:c, "1.0.0", %{telemetry: "~> 1.0"})]

    assert Resolver.plan([], incoming, @os) ==
             {:error, [{:unsatisfied, :c, :telemetry, "~> 1.0", nil}]}
  end

  test "a dependency on elixos is satisfied by the running OS" do
    incoming = [pkg(:d, "1.0.0", %{elixos: "~> 0.1"})]
    assert {:ok, %{install: [:d]}} = Resolver.plan([], incoming, "0.1.3")

    assert Resolver.plan([], incoming, "1.0.0") ==
             {:error, [{:os_version, :d, "~> 0.1", "1.0.0"}]}
  end

  test "the OS package must never arrive bundled" do
    incoming = [pkg(:d, "1.0.0", %{elixos: "~> 0.1"}), pkg(:elixos, "0.1.9")]
    assert Resolver.plan([], incoming, @os) == {:error, [{:bundled_os, :elixos}]}
  end

  test "every conflict is reported, sorted" do
    installed = [pkg(:a, "1.0.0", %{jason: "~> 1.4"}), pkg(:jason, "1.4.4")]

    incoming = [
      pkg(:jason, "2.0.1"),
      pkg(:z, "1.0.0", %{nope: ">= 0.0.0"}),
      pkg(:e, "1.0.0", %{elixos: "~> 9.0"})
    ]

    assert Resolver.plan(installed, incoming, @os) ==
             {:error,
              Enum.sort([
                {:unsatisfied, :a, :jason, "~> 1.4", "2.0.1"},
                {:unsatisfied, :z, :nope, ">= 0.0.0", nil},
                {:os_version, :e, "~> 9.0", @os}
              ])}
  end
end
