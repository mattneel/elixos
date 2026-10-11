defmodule Elixos.Oban.Migration do
  @moduledoc """
  Oban's own schema, as an ordinary Ecto migration (M19, ADR-057).

  `Elixos.Oban.Manager` runs it through `Ecto.Migrator` against
  `Elixos.Oban.Repo`, once, before the first queue can start; the version it
  records lives in `schema_migrations` like any other Ecto migration, so a
  later Oban upgrade is one new version here.

  Oban ships the migration itself (`Oban.Migrations.up/1` builds every table
  the running version needs), which is the documented way to run it without a
  Mix task - there is no build step in the factory, and no shell.
  """

  use Ecto.Migration

  # The version this migration records. It only ever moves forward; a new
  # Oban that needs a new schema version gets a higher one here.
  @version 20_260_101

  @doc "The `schema_migrations` version this migration is recorded under."
  @spec version() :: pos_integer()
  def version, do: @version

  def up, do: Oban.Migrations.up()

  def down, do: Oban.Migrations.down()
end
