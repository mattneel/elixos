defmodule Elixos.Application do
  @moduledoc """
  The OS application.

  On the dev host (unit tests) `Elixos.Boot.Env.current/0` returns `{:ok, :host}`
  and nothing is started. Under the shim (M4 onward) this is where the system
  comes up, in order:

    1. `Elixos.Shim.Control` on the inherited control fd (heartbeats start).
    2. The generation's modules and boot spec (`Elixos.Image.restore/2`, M6).
    3. `Elixos.Boot.AutoCommit` in normal mode (M5).
    4. The login REPL on the console via `:shell.start_interactive/1` (M4, M9).

  A failure in steps 1-3 must exit the VM with a non-zero status so the shim
  counts the attempt and falls back (ADR-007). Never swallow it.
  """
  use Application

  @impl true
  def start(_type, _args) do
    # TODO(M4): when Elixos.Boot.Env.current() returns {:ok, %Elixos.Boot.Env{}},
    # start the children listed in the moduledoc.
    children = []
    Supervisor.start_link(children, strategy: :one_for_one, name: Elixos.Supervisor)
  end
end
