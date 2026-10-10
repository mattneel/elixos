defmodule OrphanC.MixProject do
  use Mix.Project

  # Needs a >= 2.0.0: a constraint that must not outlive the pick that wanted
  # c in the first place.
  def project do
    [
      app: :orphan_c,
      version: "1.0.0",
      elixir: "~> 1.20",
      deps: [{:orphan_a, ">= 2.0.0"}],
      description: "Fixture package c: requires a >= 2.0.0",
      package: [licenses: ["Apache-2.0"], links: %{"Elixos" => "https://example.invalid/elixos"}]
    ]
  end

  def application, do: [extra_applications: []]
end
