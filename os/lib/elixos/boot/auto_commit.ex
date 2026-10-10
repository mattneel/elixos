defmodule Elixos.Boot.AutoCommit do
  @moduledoc """
  Commits the running generation once it has stayed healthy for a while (ADR-007).

  Without a commit, every boot of a generation counts as an attempt, and after
  `elixos.max_attempts` the shim falls back. Committing is what tells the shim
  "this generation is good".

  Options:

    * `:env` (required) - the `%Elixos.Boot.Env{}` of this boot
    * `:after_ms` - healthy uptime required before committing, default from
      `Elixos.Boot.Cmdline.commit_after_ms/1`
    * `:healthy?` - zero-arity fun, default: the `Elixos.Supervisor` is alive
    * `:commit` - one-arity fun called with the generation, default
      `&Elixos.Shim.Control.commit/1`

  Rules:

    * rescue mode never commits: `start_link/1` returns `:ignore`
    * normal mode checks `healthy?` every `after_ms`; the first time it is true
      it calls `commit` exactly once and the process exits `:normal`
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    env = Keyword.fetch!(opts, :env)

    if env.mode == :rescue do
      # A rescue boot is the user recovering the machine: it must never turn
      # the factory (or the fallen-back generation) into last_good by itself.
      :ignore
    else
      state = %{
        generation: env.generation,
        after_ms: Keyword.get_lazy(opts, :after_ms, fn -> default_after_ms() end),
        healthy?: Keyword.get(opts, :healthy?, &healthy?/0),
        commit: Keyword.get(opts, :commit, &Elixos.Shim.Control.commit/1)
      }

      # The first check comes after a full interval: a boot is not committed
      # the moment it starts, it has to have lasted.
      Process.send_after(self(), :check, state.after_ms)
      {:ok, state}
    end
  end

  @impl true
  def handle_info(:check, state) do
    if state.healthy?.() do
      _ = state.commit.(state.generation)
      {:stop, :normal, state}
    else
      Process.send_after(self(), :check, state.after_ms)
      {:noreply, state}
    end
  end

  defp default_after_ms, do: Elixos.Boot.Cmdline.commit_after_ms(Elixos.Boot.Cmdline.current())

  # "Healthy" means the supervision tree we are part of is still up: a boot
  # that lost its tree is on its way down and must not be committed.
  defp healthy?, do: Process.whereis(Elixos.Supervisor) != nil
end
