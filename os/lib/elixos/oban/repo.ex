defmodule Elixos.Oban.Repo do
  @moduledoc """
  The BEAM's connection to the system database (M19, ADR-057).

  One Repo, started by `Elixos.Oban.Manager` only after `Elixos.Postgres` is
  ready. The postmaster the shim started - as the `postgres` uid, from the
  read-only `/system` image - listens on loopback only, and `initdb` ran with
  `-U postgres -A trust` (ADR-053), so the connection has no password to
  carry: there is nothing secret to keep and nothing else on the wire.

  This is not a user-facing API: it exists so Oban and, later, apps' own Ecto
  schemas share one pool and one migration history. Logging of statements is
  off - the console is the system's log, and every query would drown it.
  """

  use Ecto.Repo, otp_app: :elixos, adapter: Ecto.Adapters.Postgres

  @doc """
  The connection options, from `config :elixos, Elixos.Oban.Repo` - the same
  key `Repo.config/0` reports to Oban's notifier, peer and engine, so every
  connection this machine opens goes to the same place: M18's database, on
  loopback, as the `postgres` role (ADR-053, ADR-057).
  """
  @spec connection_options() :: keyword()
  def connection_options do
    Application.get_env(:elixos, __MODULE__, [])
  end
end
