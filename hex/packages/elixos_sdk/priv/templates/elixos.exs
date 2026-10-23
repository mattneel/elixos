import Config

# Relative persist paths in os/0 live beneath Elixos.Package.data_dir(:@APP@).
# This is filesystem durability, not a snapshot of a Live system's RAM.
config :@APP@, state_dir: "/priv/data/@APP@/state"
