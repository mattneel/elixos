import Config

# Settings for the OS when built for the Elixos target (MIX_TARGET=elixos).
# Paths here are inside the running system, not on the dev host.
config :elixos,
  data_dir: "/data",
  heartbeat_ms: 1_000
