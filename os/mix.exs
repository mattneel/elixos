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
      elixos: [boot: :auto],
      # Generation 0 is this release. ELIXOS_ERTS points at the OTP the release
      # should carry; without it a dev release bundles the host's ERTS. The
      # factory package (M16, ADR-041) sets ELIXOS_INCLUDE_ERTS=0 instead: OTP
      # is an installed package there, and the release points at it (symlinks
      # at erts-<vsn> and erts) rather than carrying a second copy. No
      # executables: the shim execs erlexec itself (ADR-012).
      releases: [
        elixos: [
          include_erts:
            System.get_env("ELIXOS_INCLUDE_ERTS") != "0" and
              (System.get_env("ELIXOS_ERTS") || true),
          include_executables_for: []
        ]
      ]
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
  #
  # Jido is a direct dependency of Elixos itself (ADR-036): agents are part of
  # the operating system, so the framework that runs them ships in the factory
  # rather than being installed from a repository at run time. Its closure is
  # pure BEAM (no NIFs) and its OTP dependencies (mnesia, via jido_signal)
  # come from the same cross-built OTP as everything else.
  defp deps, do: [{:jido, "~> 2.4"}]
end
