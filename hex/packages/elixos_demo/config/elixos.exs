import Config

# The state directory is independent of the replaceable installed ebin/priv.
# Live RAM remains volatile across a kernel reboot; no snapshots are implied.
config :elixos_demo,
  state_dir: "/priv/data/elixos_demo/state",
  os_observer: ElixosDemo.OS
