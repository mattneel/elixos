defmodule Elixos.Oban do
  @moduledoc """
  Oban on Elixos (M18, docs/ROADMAP.md): the machine's scheduler.

  Jobs are rows in the system Postgres (M17), so they survive a power cycle,
  fail and retry; an app declares its queues and its cron entries in its
  `elixos:` key, next to its services (M11's spec), and `options/1` turns one
  app's declaration into Oban's options. Oban is not boot-critical and does
  not run in rescue; it is stopped by the same shutdown hook as Postgres.
  """

  alias Elixos.Package.Spec

  @doc "The running scheduler: `{:ok, pid}` or `{:error, :not_running}`."
  @spec status() :: {:ok, pid()} | {:error, :not_running}
  def status, do: Elixos.NotImplemented.raise!(18, "Elixos.Oban.status/0")

  @doc """
  Inserts `worker` with `args` (keyword `opts` go to `Oban.Job.new/3`: queue,
  `schedule_in`, priority, and so on).
  """
  @spec enqueue(module(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def enqueue(_worker, _args, _opts \\ []) do
    Elixos.NotImplemented.raise!(18, "Elixos.Oban.enqueue/3")
  end

  @doc """
  One app's Oban options from its `elixos:` declaration: the queues it runs
  and the `Oban.Plugins.Cron` plugin it needs, if any.
  """
  @spec options(Spec.t()) :: keyword()
  def options(_spec), do: Elixos.NotImplemented.raise!(18, "Elixos.Oban.options/1")
end
