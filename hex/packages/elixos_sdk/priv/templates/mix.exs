defmodule @MODULE@.MixProject do
  use Mix.Project

  def project do
    [
      app: :@APP@,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: deps(),
      elixos: os(),
      description: "A supervised durable counter for Elixos and ordinary Mix hosts",
      package: [
        files: ["lib", "config", "test", "mix.exs", "LICENSE", ".formatter.exs"],
        licenses: ["MIT"],
        links: %{"Elixos" => "https://github.com/mattneel/elixos"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {@MODULE@.Application, []}]
  end

  defp deps do
    [{:elixos, "~> 0.1", targets: :elixos}]
  end

  defp os do
    [
      services: [@MODULE@.Supervisor],
      persist: ["state"],
      min_os: "~> 0.1",
      boot: :@BOOT@
    ]
  end
end
