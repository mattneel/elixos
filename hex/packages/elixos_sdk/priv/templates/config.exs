import Config

config :@APP@,
  target: config_target(),
  state_dir: Path.expand("../var/state", __DIR__)

if config_target() == :elixos, do: import_config("elixos.exs")
