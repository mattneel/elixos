defmodule ElixosDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixos_demo,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(),
      deps: deps(),
      elixos: os(),
      description: "A supervised durable measurement journal with native Elixos observations",
      package: [
        files: ["lib", "target", "config", "test", "mix.exs", "LICENSE", ".formatter.exs"],
        licenses: ["MIT"],
        links: %{"Elixos" => "https://github.com/mattneel/elixos"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {ElixosDemo.Application, []}]
  end

  defp elixirc_paths do
    if Mix.target() == :elixos, do: ["lib", "target/elixos"], else: ["lib"]
  end

  defp deps do
    [
      {:elixos, "~> 0.1", targets: :elixos},
      statistics_dependency()
    ]
  end

  # The colocated source checkout can run host tests without a repository.
  # Published/prod/target builds always retain the ordinary Hex requirement.
  defp statistics_dependency do
    local = Path.expand("../elixos_demo_stats", __DIR__)

    if Mix.env() == :test and Mix.target() == :host and File.regular?(Path.join(local, "mix.exs")) do
      {:elixos_demo_stats, "~> 0.1", path: local}
    else
      {:elixos_demo_stats, "~> 0.1"}
    end
  end

  defp os do
    [
      services: [ElixosDemo.Supervisor],
      persist: ["state"],
      min_os: "~> 0.1",
      boot: :auto
    ]
  end
end
