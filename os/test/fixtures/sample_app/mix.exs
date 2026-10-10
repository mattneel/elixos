defmodule SampleApp.MixProject do
  # A regular Elixir app that opts into Elixos (docs/ARCHITECTURE.md §7).
  # Plain `mix` ignores the elixos: key, so this still builds anywhere.
  use Mix.Project

  def project do
    [
      app: :sample_app,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: deps(),
      elixos: [
        services: [SampleApp.Worker],
        persist: ["data"],
        min_os: "~> 0.1"
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  # The OS provides the elixos API (ADR-015). Here it points at this repo's
  # os/ project; a published app would use {:elixos, "~> 0.1", targets: :elixos}.
  defp deps, do: [{:elixos, path: "../../..", targets: :elixos}]
end
