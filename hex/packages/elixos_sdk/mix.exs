defmodule ElixosSDK.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixos_sdk,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: [],
      test_ignore_filters: [
        &String.starts_with?(&1, "test/fixtures/"),
        &String.starts_with?(&1, "test/support/")
      ],
      description:
        "Build-time Mix project generation and source packaging for native Elixos apps",
      package: [
        files: ["lib", "priv", "test", "mix.exs", "LICENSE", ".formatter.exs"],
        licenses: ["MIT"],
        links: %{"Elixos" => "https://github.com/mattneel/elixos"}
      ]
    ]
  end

  def application, do: [extra_applications: []]
end
