import Config

# The OS itself follows the convention it asks of apps (ADR-010): host builds and
# tests use this file; `MIX_TARGET=elixos` builds add config/elixos.exs on top.
config :logger, level: :info

# Mnesia's default directory is `Mnesia.<node>` relative to the working
# directory, and the VM never changes its own (ADR-016) - so the default is
# the RAM-backed root. Pin it on the persistent disk before anything creates a
# disc copy: a schema that lands anywhere else is a memory that quietly dies
# with the machine, or a directory paid for in RAM at every boot.
#
# It is pinned here, not in config/elixos.exs: that file layers only when a
# build names MIX_TARGET=elixos (the factory's release does not), and this
# setting must hold for every build of the OS.
config :mnesia, dir: ~c"/priv/mnesia"

# The system database connection (M19, ADR-057): M18's postmaster on loopback,
# the `postgres` role, trust authentication (ADR-053). It lives in the app
# environment, not only in Ecto.Repo.start_link/1 options, because that is what
# `Repo.config/0` returns - and Oban's notifier, peer and engine open their own
# connections from exactly that (the host build and every release must agree on
# it; `Elixos.Oban.Repo.connection_options/0` reads the same key).
config :elixos, Elixos.Oban.Repo,
  hostname: "127.0.0.1",
  port: 5432,
  username: "postgres",
  database: "postgres",
  pool_size: 5,
  log: false

if config_target() == :elixos do
  import_config "elixos.exs"
end

# The GUI (M27): Emerge's minimal raster build - CPU raster, embedded FreeType,
# no Wayland, no GPU, no Mesa. That is the statically linked
# x86_64-unknown-linux-musl artifact, which loads on the host's glibc BEAM and
# inside the image alike; without this the default gnu artifact wants libgbm and
# libxkbcommon, which the image does not have (ADR-009: the box never
# downloads, so what the image shows is what was pinned at build time).
config :emerge, compiled_backends: []
