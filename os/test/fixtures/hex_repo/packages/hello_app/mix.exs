defmodule HelloApp.MixProject do
  use Mix.Project

  # Depends on hello_dep (same repository): installing hello_app by name must
  # install hello_dep first, and only then can this compile.
  def project do
    [
      app: :hello_app,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: [{:hello_dep, "~> 0.1"}],
      description: "Fixture package that depends on hello_dep",
      package: [licenses: ["Apache-2.0"], links: %{"Elixos" => "https://example.invalid/elixos"}]
    ]
  end

  def application, do: [extra_applications: []]
end
