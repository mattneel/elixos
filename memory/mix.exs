defmodule HelloPkg.MixProject do
  use Mix.Project

  # A throwaway package for the Elixos test fixture: its tarball is published
  # into the local static Hex repo that M14's tests install from.
  def project do
    [
      app: :hello_pkg,
      version: "0.1.0",
      elixir: "~> 1.20",
      description: "Fixture package for the Elixos M14 acceptance tests",
      package: [licenses: ["Apache-2.0"], links: %{"Elixos" => "https://example.invalid/elixos"}]
    ]
  end

  def application, do: []
end
