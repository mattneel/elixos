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

  @hostname "127.0.0.1"
  @port 5432
  @username "postgres"
  @database "postgres"

  @doc """
  The fixed connection options, exactly M18's database: the same host, role
  and database `Elixos.Postgres.query/1` uses, so the prompt, Oban and the
  Repo all see one database.
  """
  @spec connection_options() :: keyword()
  def connection_options do
    [
      hostname: @hostname,
      port: @port,
      username: @username,
      database: @database,
      pool_size: 5,
      log: false
    ]
  end
end
