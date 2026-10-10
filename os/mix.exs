defmodule Elixos.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :elixos,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      # Fixtures under test/ are whole Mix projects, not tests.
      test_ignore_filters: [&String.starts_with?(&1, "test/fixtures/")],
      # Elixos dogfoods its own install metadata (ADR-011, docs/ARCHITECTURE.md §7).
      elixos: [boot: :auto]
    ]
  end

  def application do
    [
      mod: {Elixos.Application, []},
      # :ssh is optional so early factory builds without it still boot (M12 needs it).
      extra_applications: [:logger, :crypto, ssh: :optional]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # The OS core takes no runtime dependencies without an ADR in docs/DECISIONS.md.
  defp deps, do: []
end
