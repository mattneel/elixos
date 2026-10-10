import Config

# The OS itself follows the convention it asks of apps (ADR-010): host builds and
# tests use this file; `MIX_TARGET=elixos` builds add config/elixos.exs on top.
config :logger, level: :info

if config_target() == :elixos do
  import_config "elixos.exs"
end
