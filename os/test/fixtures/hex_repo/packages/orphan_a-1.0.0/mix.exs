defmodule OrphanA.MixProject do
  use Mix.Project

  # 1.0.0 asks for nothing: when b pins a down to this version, c is stranded.
  def project do
    [
      app: :orphan_a,
      version: "1.0.0",
      elixir: "~> 1.20",
      description: "Fixture package: the version a that needs nothing",
      package: [licenses: ["Apache-2.0"], links: %{"Elixos" => "https://example.invalid/elixos"}]
    ]
  end

  def application, do: [extra_applications: []]
end
