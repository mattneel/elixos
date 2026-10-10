defmodule OrphanB.MixProject do
  use Mix.Project

  # Pins a below 2.0.0, which is what strands c.
  def project do
    [
      app: :orphan_b,
      version: "1.0.0",
      elixir: "~> 1.20",
      deps: [{:orphan_a, "~> 1.0"}],
      description: "Fixture package that pins a below 2.0.0",
      package: [licenses: ["Apache-2.0"], links: %{"Elixos" => "https://example.invalid/elixos"}]
    ]
  end

  def application, do: [extra_applications: []]
end
