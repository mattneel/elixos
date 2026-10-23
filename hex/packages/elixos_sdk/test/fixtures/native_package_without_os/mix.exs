defmodule NativePackageWithoutOS.MixProject do
  use Mix.Project

  def project do
    [
      app: :native_package_without_os,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: [],
      elixos: [],
      description:
        "Native consumer declaring an empty Elixos contract without the OS requirement",
      package: [
        files: ["mix.exs"],
        licenses: ["MIT"],
        links: %{"Elixos" => "https://github.com/mattneel/elixos"}
      ]
    ]
  end

  def application, do: [extra_applications: []]
end
