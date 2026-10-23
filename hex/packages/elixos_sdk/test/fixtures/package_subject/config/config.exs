import Config

config :package_subject, target: config_target()
if config_target() == :elixos, do: import_config("elixos.exs")
