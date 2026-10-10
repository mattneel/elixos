defmodule Elixos.Postgres do
  @moduledoc """
  The system PostgreSQL (M17, docs/ROADMAP.md).

  Postgres ships with the machine, in the read-only system image on `/system`,
  and runs as the `postgres` uid - never as root - started directly as a port.
  Nothing here is boot-critical: if the server does not come up, the prompt
  still does, in normal mode and in rescue. `Elixos.poweroff/0` and
  `Elixos.halt/0` stop it cleanly before the VM stops, so the next boot is not
  crash recovery.
  """

  @doc """
  The running server: `{:ok, pid}` - the port's OS process, whose uid is the
  one `/etc/passwd` names - or `{:error, :not_running}`.
  """
  @spec status() :: {:ok, pid()} | {:error, :not_running}
  def status, do: Elixos.NotImplemented.raise!(17, "Elixos.Postgres.status/0")

  @doc """
  Runs `sql` (one or more statements) through `psql` and returns its output.

  This is the prompt's interface to the database, not a wire client: what a
  person would type at a terminal is what a session types here.
  """
  @spec query(String.t()) :: {:ok, String.t()} | {:error, term()}
  def query(_sql), do: Elixos.NotImplemented.raise!(17, "Elixos.Postgres.query/1")
end
