import Config

# Build-time native profile selection; never sourced by the default factory.
import_config "/home/build/os/config/config.exs"

config :snakepit,
  python_executable: "/opt/oh-my-jido-eval/venv/bin/python3",
  python: [strategy: :system, managed: false],
  grpc_listener: %{mode: :internal}

# This configuration grants no session permission and starts no application.
# The explicit frontend starts native prerequisites without Snakepit.Application
# (whose general-purpose bootstrap can provision Python on other hosts).
config :oh_my_jido, :eval,
  backends: %{
    elixir: [isolation: :trusted, schedulers: 2],
    javascript: [isolation: :trusted, schedulers: 2],
    python: [isolation: :trusted,
      adapter_env: [{"PYTHONNOUSERSITE", "1"}, {"PYTHONDONTWRITEBYTECODE", "1"}]]
  },
  max_kernels: 6,
  callback_timeout: 20_000,
  idle_timeout: 60_000
