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

if config_target() == :elixos do
  import_config "elixos.exs"
end
