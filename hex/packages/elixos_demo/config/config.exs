import Config

config :elixos_demo,
  target: config_target(),
  state_dir: Path.expand("../var/state", __DIR__),
  os_observer: nil

if config_target() == :elixos, do: import_config("elixos.exs")
