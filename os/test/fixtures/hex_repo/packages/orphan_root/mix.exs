defmodule OrphanRoot.MixProject do
  use Mix.Project

  # The root of the unreachable-pick test (M15 finding): it needs a and b; the
  # newest a needs c, and b pins a down to a version that does not - so c must
  # fall out of the closure instead of vetoing it with its own requirement.
  def project do
    [
      app: :orphan_root,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: [{:orphan_a, ">= 1.0.0"}, {:orphan_b, "~> 1.0"}],
      description: "Fixture root for the resolver's unreachable-pick test",
      package: [licenses: ["Apache-2.0"], links: %{"Elixos" => "https://example.invalid/elixos"}]
    ]
  end

  def application, do: [extra_applications: []]
end
