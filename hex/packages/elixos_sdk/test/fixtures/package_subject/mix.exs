defmodule PackageSubject.MixProject do
  use Mix.Project

  def project do
    [
      app: :package_subject,
      version: "0.1.0",
      elixir: "~> 1.20",
      compilers: [:must_not_compile_during_packaging],
      aliases: ["hex.build": ["must_not_run_a_project_alias"]],
      deps: deps(),
      elixos: [services: [], persist: ["state"], min_os: "~> 0.1", boot: :manual],
      description: "Consumer fixture proving source packaging does not compile or fetch",
      package: [
        files: ["lib", "target", "config", "mix.exs"],
        licenses: ["MIT"],
        links: %{"Elixos" => "https://github.com/mattneel/elixos"}
      ]
    ]
  end

  def application, do: [extra_applications: []]

  defp deps do
    conditional =
      if Mix.target() == :elixos,
        do: {:target_conditional, "~> 0.2", only: :prod},
        else: {:host_conditional, "~> 0.2"}

    [
      {:elixos, "~> 0.1", targets: :elixos},
      {:elixos_demo_stats, "~> 0.1", targets: :elixos, repo: "explicit_sample"},
      {:host_only, path: "missing-host-source", targets: :host},
      {:test_only, path: "missing-test-source", only: :test},
      conditional
    ]
  end
end
