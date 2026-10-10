defmodule HelloDep.MixProject do
  use Mix.Project

  # A throwaway package: hello_app depends on it, so the fixture repo can
  # exercise install-by-name resolving a dependency closure (M15).
  def project do
    [
      app: :hello_dep,
      version: "0.1.0",
      elixir: "~> 1.20",
      description: "Fixture dependency for the Elixos package tests",
      package: [licenses: ["Apache-2.0"], links: %{"Elixos" => "https://example.invalid/elixos"}]
    ]
  end

  def application, do: [extra_applications: []]
end
