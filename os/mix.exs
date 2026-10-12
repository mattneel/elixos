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
          include_executables_for: [],
          # ADR-047: ship the engine without loading its application spec;
          # Jido discovery must never enumerate its NIFs in the main VM.
          applications: [quickbeam: :none, oxc: :none]
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
  # Oban, Ecto SQL and Postgrex are the scheduler on M18's Postgres (ADR-057,
  # M19). Pure BEAM, no NIFs: the postmaster is a shim helper and the BEAM
  # reaches it as an ordinary PostgreSQL client over loopback.
  #
  # The browser (M25, ADR-065) speaks the ecosystem's protocol: `cdp_ex` is the
  # CDP client, and `Elixos.Browser.CDP` gives it the same little interface
  # jido_browser's Lightpanda adapter expects, with the process started here as
  # an ordinary Port (ADR-012: no shell, and no launcher that wants one).
  #
  # Two packages are deliberately *not* dependencies. `light_cdp` spawns the
  # browser through `erlexec`, which refuses to start unless SHELL is set - the
  # one variable this OS must not invent. `jido_browser` hard-depends on
  # `extractous_ex`, whose Rust crate downloads a GraalVM JDK and Apache Tika
  # natives and does not build on musl: a JVM-shaped payload is not worth it for
  # a browser, and the interface implemented here means either is one line away
  # if that changes.
  defp deps,
    do: [
      {:jido, "~> 2.4"},
      {:oban, "~> 2.24"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:cdp_ex, "~> 0.10"},
      # The image packages Emerge's musl raster NIF separately from its BEAM.
      # Rustler generates a loader without compiling/downloading native code.
      {:rustler, "~> 0.38.0", runtime: false},
      {:emerge, "0.4.2"},
      # Loaded and started only by the supervised tool peer (ADR-047).
      {:quickbeam, "0.11.3", runtime: false},
      {:oxc, "0.19.0", runtime: false}
    ]
end
