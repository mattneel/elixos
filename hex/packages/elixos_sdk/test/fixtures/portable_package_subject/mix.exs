defmodule PortablePackageSubject.MixProject do
  use Mix.Project

  def project do
    [
      app: :portable_package_subject,
      version: "0.1.0",
      elixir: "~> 1.20",
      compilers: [:must_not_compile_during_packaging],
      aliases: ["hex.build": ["must_not_run_a_project_alias"]],
      deps: [],
      description: "Portable library consumer without an Elixos contract or OS dependency",
      package: [
        files: ["lib", "mix.exs"],
        licenses: ["MIT"],
        links: %{"Elixos" => "https://github.com/mattneel/elixos"}
      ]
    ]
  end

  def application, do: [extra_applications: []]
end
