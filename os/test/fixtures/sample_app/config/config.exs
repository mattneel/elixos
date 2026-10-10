import Config

config :sample_app, where: :host

# The Elixos convention (ADR-010): one line, and everything else stays standard.
if config_target() == :elixos, do: import_config("elixos.exs")
