defmodule ElixosDemoStats.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixos_demo_stats,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: [],
      description:
        "Portable, dependency-free summary statistics for the Elixos measurement journal",
      package: [
        files: ["lib", "test", "mix.exs", "LICENSE", ".formatter.exs"],
        licenses: ["MIT"],
        links: %{"Elixos" => "https://github.com/mattneel/elixos"}
      ]
    ]
  end

  def application, do: [extra_applications: []]
end
