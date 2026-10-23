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
    * `:healthy?` - zero-arity fun returning `:ok` or `true` only on success;
      default: `Elixos.Health.boot/0` (ADR-095)
    * `:commit` - one-arity fun called with the generation, default
      `&Elixos.Shim.Control.commit/1`
    * `:evidence_dir` - durable result directory, default for this generation;
      isolated consumers may supply their temporary storage explicitly

  Rules:

    * rescue mode never commits: `start_link/1` returns `:ignore`
    * normal mode rechecks failed health every `after_ms`; successful health
      permits exactly one `commit` attempt, then the process exits `:normal`
    * a control-write failure is retained as failure, never an acknowledgment
      of promotion, and is not automatically retried
  """
  # :transient, because this child is done when it commits: a :permanent
  # restart would commit again and again, and at a short commit_after the
  # restarts would exceed the supervisor's limit and take the tree down.
  use GenServer, restart: :transient

  require Logger

  alias Elixos.Candidate.Evidence

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
        healthy?: Keyword.get(opts, :healthy?, &Elixos.Health.boot/0),
        commit: Keyword.get(opts, :commit, &Elixos.Shim.Control.commit/1),
        evidence_dir:
          Keyword.get(opts, :evidence_dir, Elixos.Candidate.evidence_dir(env.generation))
      }

      # The first check comes after a full interval: a boot is not committed
      # the moment it starts, it has to have lasted.
      Process.send_after(self(), :check, state.after_ms)
      {:ok, state}
    end
  end

  @impl true
  def handle_info(:check, state) do
    case check_health(state.healthy?) do
      :ok ->
        result = commit(state.commit, state.generation)
        receipt = %{generation: state.generation, result: result, checked_at: DateTime.utc_now()}

        case Evidence.record(state.evidence_dir, "auto_commit", receipt) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("Elixos AutoCommit evidence failed: #{inspect(reason)}")
        end

        if result != :ok,
          do: Logger.error("Elixos AutoCommit control write failed: #{inspect(result)}")

        {:stop, :normal, state}

      {:error, reason} ->
        Logger.warning("Elixos AutoCommit denied by health: #{inspect(reason)}")
        Process.send_after(self(), :check, state.after_ms)
        {:noreply, state}
    end
  end

  defp default_after_ms, do: Elixos.Boot.Cmdline.commit_after_ms(Elixos.Boot.Cmdline.current())

  defp check_health(check) do
    case check.() do
      result when result in [:ok, true] -> :ok
      {:error, reason} -> {:error, reason}
      value -> {:error, {:invalid_health_result, value}}
    end
  rescue
    error -> {:error, {:exception, Exception.message(error)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp commit(callback, generation) do
    case callback.(generation) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      value -> {:error, {:invalid_commit_result, value}}
    end
  rescue
    error -> {:error, {:exception, Exception.message(error)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
