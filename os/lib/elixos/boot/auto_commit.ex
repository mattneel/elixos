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
    _ = opts
    Elixos.NotImplemented.raise!(5, "Elixos.Boot.AutoCommit.start_link/1")
  end

  @impl true
  def init(opts) do
    _ = opts
    Elixos.NotImplemented.raise!(5, "Elixos.Boot.AutoCommit.init/1")
  end
end
