defmodule Elixos.Health do
  @moduledoc """
  Fail-closed generation health.

  `run/0` is the full gate: supervision liveness, the complete portable system
  suite, the selected host-tool smoke suite, and a separate candidate
  project's own suite when applicable. Normal guest health also compares each
  loaded generation module's VM MD5 identity with its SHA256-verified store
  BEAM. All suites run in isolated child ERTS workers against verified
  generation bytecode, not freshly compiled source. Missing source, loaded
  code, ExUnit, evidence, or tests is a failed check. Image export requires it.

  `boot/0` is the gate `Elixos.Boot.AutoCommit` uses (ADR-095): liveness, the
  running-generation identity check, and - for a generation that came from
  `Elixos.Candidate.propose/1` - its unchanged, successful suite evidence. The
  suites ran before NEXT was written; re-running the whole system suite on
  every boot does not fit the commit window or a small machine's RAM.

  A trusted host may set `:elixos, :health_checks` to named zero-arity checks;
  both gates then run exactly those. Every check runs; errors, exceptions,
  throws and invalid return values are retained by name under
  `/priv/evidence/<generation>/health.term`. `run/2` accepts explicit checks
  and a `:generation` for isolated host integration. Neither this module nor
  its child workers sends NEXT, COMMIT, or reboot requests.
  """

  alias Elixos.Candidate
  alias Elixos.Candidate.Evidence

  @type check :: {atom(), (-> :ok | {:error, term()})}

  @spec checks() :: [check()]
  def checks do
    case Application.fetch_env(:elixos, :health_checks) do
      {:ok, checks} -> checks
      :error -> default_checks(current_generation())
    end
  end

  @spec run([check()], keyword()) :: :ok | {:error, [{atom(), term()}]}
  def run(checks \\ checks(), opts \\ []) do
    failures = evaluate(checks)
    result = if failures == [], do: :ok, else: {:error, failures}
    generation = Keyword.get(opts, :generation, current_generation())
    receipt = %{generation: generation, result: result, checked_at: DateTime.utc_now()}

    case Evidence.record(Candidate.evidence_dir(generation), "health", receipt) do
      :ok -> result
      {:error, reason} -> {:error, failures ++ [evidence: reason]}
    end
  end

  @doc "The boot gate AutoCommit uses (ADR-095); see the moduledoc."
  @spec boot() :: :ok | {:error, [{atom(), term()}]}
  def boot do
    case Application.fetch_env(:elixos, :health_checks) do
      {:ok, checks} -> run(checks)
      :error -> run(boot_checks(current_generation()))
    end
  end

  defp boot_checks(generation) do
    [liveness: &liveness/0, proposal: fn -> Candidate.proposal_validated(generation) end] ++
      live_checks(generation)
  end

  defp liveness do
    if Process.whereis(Elixos.Supervisor), do: :ok, else: {:error, :supervisor_not_running}
  end

  @doc "Runs the real default suite gates for a stored generation without promoting it."
  def run_generation(number) when is_integer(number) and number >= 0 do
    run(default_checks(number), generation: number)
  end

  defp evaluate([]), do: [checks: :empty]

  defp evaluate(checks) when is_list(checks) do
    Enum.flat_map(checks, fn
      {name, check} when is_atom(name) and is_function(check, 0) ->
        case execute(check) do
          :ok -> []
          {:error, reason} -> [{name, reason}]
        end

      invalid ->
        [checks: {:invalid_check, inspect(invalid)}]
    end)
  end

  defp evaluate(_), do: [checks: :invalid]

  defp execute(check) do
    case check.() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      value -> {:error, {:invalid_result, value}}
    end
  rescue
    error -> {:error, {:exception, Exception.message(error)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp default_checks(generation) do
    [
      liveness: fn ->
        if Process.whereis(Elixos.Supervisor), do: :ok, else: {:error, :supervisor_not_running}
      end,
      system_suite: fn -> Candidate.health_check(generation, :system_suite) end,
      toolset_smoke: fn -> Candidate.health_check(generation, :toolset_smoke) end
    ] ++ live_checks(generation) ++ Candidate.additional_health_checks(generation)
  end

  defp live_checks(generation) do
    case Elixos.Boot.Env.current() do
      {:ok, %{generation: ^generation}} ->
        [live_image: fn -> Candidate.verify_running_generation(generation) end]

      _host_or_other_generation ->
        []
    end
  end

  defp current_generation do
    case Elixos.Boot.Env.current() do
      {:ok, %{generation: number}} -> number
      _ -> 0
    end
  end
end
