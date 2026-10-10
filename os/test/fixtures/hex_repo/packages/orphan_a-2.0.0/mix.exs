defmodule OrphanA.MixProject do
  use Mix.Project

  # 2.0.0 needs c, and c needs a >= 2.0.0: both only make sense while 2.0.0 is
  # the pick. b's ~> 1.0 takes it away.
  def project do
    [
      app: :orphan_a,
      version: "2.0.0",
      elixir: "~> 1.20",
      deps: [{:orphan_c, "~> 1.0"}],
      description: "Fixture package: the version a that needs c",
      package: [licenses: ["Apache-2.0"], links: %{"Elixos" => "https://example.invalid/elixos"}]
    ]
  end

  def application, do: [extra_applications: []]
end
