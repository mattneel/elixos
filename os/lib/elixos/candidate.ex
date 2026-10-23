defmodule Elixos.Candidate do
  @moduledoc """
  Isolated, generation-only candidate validation owned by Elixos.

  `checkout/1` creates a source bundle and returns its Mix project directory.
  `build/2` snapshots that project, compiles it in a separate ERTS using the
  installed runtime and dependencies, and stores bytecode without loading it.
  `test/1` runs the portable unit suite, selected host-tool suite, and a
  separate userland project's own suite in fresh, non-distributed child ERTS
  workers. Empty, failed, or stale suites deny `propose/1`. The fingerprint
  binds source/BEAM plus the complete manifest, provenance and trusted
  build/boot/test policy. The ordinary Port boundary accepts bounded JSON data
  only, never OTP peer ETF frames, origin messages, executable funs, or host MFAs.

  A proposal is an Image generation overlay, followed by the existing NEXT
  protocol write. It is not a promotion acknowledgment and never reboots or
  commits. Protected factory/OTP/Elixir modules are refused; changing the
  sticky base requires a separately authorized factory build.

  Build options are `:provenance` (required: session, model, tools, parent),
  `:image` and `:control` (existing service handles), `:target` (`:host` or
  `:elixos`), `:deps_path`, trusted `:system_source`, `:tool_tests`, `:boot`,
  and `:timeout`. The OS suite baseline defaults to installed factory/current
  source, independently of a separate userland candidate project.
  Source/test snapshots, logs and receipts persist under the configured
  `:elixos, :priv_dir`. A failed or fallen-back generation never deletes them.
  Child workers isolate VM state, not filesystem/network or escaped native
  descendant authority; hosts must approve candidate execution and supply
  their trusted source, tool-test policy, and any required OS sandbox.
  """

  alias Elixos.Candidate.{Child, Evidence}
  alias Elixos.Image
  alias Elixos.Image.{Generation, Store}

  @default_tools [
    "test/tools/**/*_test.exs",
    "test/elixos/approvals_test.exs",
    "test/elixos/session_test.exs",
    "test/elixos/browser_test.exs"
  ]
  @source Path.expand("../..", __DIR__)

  defstruct [
    :id,
    :root,
    :source,
    :system_source,
    :ebin,
    :evidence_dir,
    :manifest,
    :fingerprint,
    :settings,
    :image,
    :control
  ]

  @type provenance :: %{
          session: term(),
          model: String.t(),
          tools: map(),
          parent: non_neg_integer()
        }
  @opaque t :: %__MODULE__{}

  @spec checkout(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def checkout(destination) when is_binary(destination) do
    destination = Path.expand(destination)

    if File.exists?(destination) do
      {:error, :exists}
    else
      with {:ok, source} <- checkout_source(),
           :ok <- Evidence.separate_destination(source, destination),
           :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.mkdir(destination),
           project = Path.join(destination, "os"),
           :ok <- Evidence.copy_source(source, project),
           :ok <- Evidence.copy_inputs(source, destination),
           :ok <-
             Evidence.write(project, ".candidate-origin", %{
               deps_path: Path.join(source, "deps"),
               coding_source: coding_source(source)
             }) do
        {:ok, project}
      else
        {:error, :eexist} -> {:error, :exists}
        error -> error
      end
    end
  end

  @spec build(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def build(source, opts) when is_binary(source) and is_list(opts) do
    with {:ok, provenance} <- validate_provenance(Keyword.get(opts, :provenance)),
         {:ok, settings} <- settings(Path.expand(source), opts) do
      build_snapshot(Path.expand(source), provenance, settings, opts)
    end
  end

  @doc """
  Reconstructs a durable candidate handle by its build identity. Service
  handles are transient and may be rebound with `:image` and `:control`;
  library adapters need persist only the string `candidate.id`.
  """
  @spec open(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def open(id, opts \\ []) when is_binary(id) do
    if Regex.match?(~r/\A[0-9a-f]{32}\z/, id) do
      root = priv()
      directory = Path.join([root, "evidence", "candidates", id])

      with {:ok, stored} <-
             stored_candidate(%__MODULE__{id: id, root: root, evidence_dir: directory}) do
        candidate = struct!(__MODULE__, stored)

        {:ok,
         %{candidate | image: Keyword.get(opts, :image), control: Keyword.get(opts, :control)}}
      end
    else
      {:error, :invalid_candidate}
    end
  rescue
    ArgumentError -> {:error, :invalid_candidate}
  end

  @spec test(t()) :: :ok | {:error, term()}
  def test(%__MODULE__{} = candidate) do
    with {:ok, stored} <- stored_candidate(candidate),
         :ok <- unchanged(stored) do
      {failures, suites} = run_suites(stored)
      result = if failures == [], do: :ok, else: {:error, failures}

      receipt = %{
        fingerprint: stored.fingerprint,
        result: result,
        suites: suites,
        checked_at: DateTime.utc_now()
      }

      with :ok <- Evidence.record(stored.evidence_dir, "test", receipt), do: result
    end
  end

  @spec propose(t()) :: {:ok, pos_integer()} | {:error, term()}
  def propose(%__MODULE__{} = candidate) do
    with {:ok, stored} <- stored_candidate(candidate),
         :ok <- unchanged(stored),
         :ok <- validated(stored),
         {:ok, image} <- service(candidate.image, Image, :image_not_running),
         {:ok, control} <- service(candidate.control, Elixos.Shim.Control, :control_not_running),
         {:ok, number} <- Image.stage(image, stored.manifest),
         :ok <- retain_proposal(stored, number, :prepared) do
      case Elixos.Shim.Control.next(control, number) do
        :ok ->
          case retain_proposal(stored, number, :next_written) do
            :ok -> {:ok, number}
            {:error, reason} -> {:error, {:next_written_evidence_failed, number, reason}}
          end

        {:error, reason} ->
          {:error, {:next_failed, number, reason}}
      end
    end
  catch
    :exit, reason -> {:error, {:service_failed, reason}}
  end

  @spec provenance(non_neg_integer()) :: {:ok, provenance()} | {:error, term()}
  def provenance(number) when is_integer(number) and number >= 0 do
    with {:ok, manifest} <- Generation.read(Path.join(priv(), "generations"), number) do
      if is_map(manifest.provenance),
        do: {:ok, manifest.provenance},
        else: {:error, :no_provenance}
    end
  end

  @spec evidence_dir(non_neg_integer()) :: Path.t()
  def evidence_dir(number) when is_integer(number) and number >= 0,
    do: Path.join([priv(), "evidence", Integer.to_string(number)])

  @doc "Reads a durable build/test receipt without executing candidate code."
  def evidence(%__MODULE__{evidence_dir: directory}, phase) when phase in [:build, :test],
    do: Evidence.read(directory, Atom.to_string(phase))

  @doc false
  def source_root do
    Application.get_env(:elixos, :candidate_source, factory_source())
  end

  defp factory_source do
    case Elixos.Boot.Env.current() do
      {:ok, :host} -> @source
      _ -> Path.join(Application.get_env(:elixos, :factory_dir, "/factory"), "source/os")
    end
  end

  @doc false
  def health_check(number, suite) do
    with {:ok, manifest} <- health_manifest(number),
         {:ok, source, config_source, settings} <- health_inputs(number, suite),
         {:ok, ebin, directory} <- health_artifacts(number, manifest),
         snapshot = Path.join(directory, "source/os"),
         :ok <- Evidence.copy_source(source, snapshot),
         :ok <- Evidence.copy_inputs(source, Path.dirname(snapshot)) do
      # Health reads the generation's actual verified store bytes, never a
      # fresh source compilation which could mask a faulty running module.
      run_suite(snapshot, ebin, suite, settings, directory, config_source) |> suite_result()
    end
  end

  @doc false
  def additional_health_checks(number) do
    with {:ok, %{candidate_dir: directory}} <- Evidence.read(evidence_dir(number), "proposal"),
         {:ok, %{source: source, system_source: system}} <- Evidence.read(directory, "candidate"),
         true <- source != system do
      [candidate_suite: fn -> health_check(number, :candidate_suite) end]
    else
      _ -> []
    end
  end

  @doc """
  Boot-time evidence check (ADR-095): a generation that came from `propose/1`
  must still be the candidate whose recorded suites passed - same fingerprint,
  unchanged inputs and a successful test receipt. Generations that never went
  through a candidate (the factory, a prompt `Elixos.save/1`) have no proposal
  and pass.
  """
  def proposal_validated(number) when is_integer(number) and number >= 0 do
    case Evidence.read(evidence_dir(number), "proposal") do
      {:ok, %{candidate_dir: directory, fingerprint: fingerprint}} ->
        with {:ok, %{fingerprint: ^fingerprint} = stored} <- Evidence.read(directory, "candidate"),
             :ok <- unchanged(stored),
             :ok <- validated(stored) do
          :ok
        else
          {:error, reason} -> {:error, reason}
          _ -> {:error, :proposal_mismatch}
        end

      {:error, :enoent} ->
        :ok

      other ->
        {:error, {:proposal_unreadable, other}}
    end
  end

  @doc "Checks that the running generation's loaded code matches its verified store bytes."
  def verify_running_generation(number) when is_integer(number) and number >= 0 do
    with {:ok, manifest} <- health_manifest(number),
         {:ok, store} <- Store.open(Path.join(priv(), "store")) do
      Enum.reduce_while(manifest.modules, :ok, fn {module, hash}, :ok ->
        with {:ok, bytes} <- Store.get(store, hash),
             {:ok, {^module, digest}} <- :beam_lib.md5(bytes),
             loaded when loaded != false <- :code.is_loaded(module),
             ^digest <- module.module_info(:md5) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:running_generation_mismatch, module}}}
        end
      end)
    end
  rescue
    _error -> {:error, :running_generation_unavailable}
  end

  defp build_snapshot(source, provenance, settings, opts) do
    id = unique_id()
    root = priv()
    directory = Path.join([root, "evidence", "candidates", id])
    snapshot = Path.join(directory, "source/os")
    build_dir = Path.join(directory, "build")

    with :ok <- File.mkdir_p(directory),
         :ok <- Evidence.write(directory, "origin", %{source: source, provenance: provenance}),
         :ok <- Evidence.copy_source(source, snapshot),
         :ok <- Evidence.copy_inputs(source, Path.dirname(snapshot)),
         {:ok, system_source} <-
           snapshot_system(source, snapshot, settings.system_source, directory) do
      child_opts = Map.put(settings, :runtime_dir, Path.join(directory, "build-runtime"))
      # The OS mix.exs names its Oh-My-Jido path dependency relative to itself
      # unless ELIXOS_OH_MY_JIDO_SOURCE says otherwise; a snapshot has moved,
      # so the child is told where the origin's copy is.
      child_result =
        Child.run(:build, [snapshot, build_dir, child_opts],
          timeout: settings.timeout,
          evidence_dir: directory,
          env: [{"ELIXOS_OH_MY_JIDO_SOURCE", settings.coding_source}]
        )

      finish_build(
        child_result,
        id,
        root,
        directory,
        snapshot,
        system_source,
        provenance,
        settings,
        opts
      )
    else
      {:error, reason} ->
        _ = Evidence.write(directory, "build", %{result: {:error, reason}, output: ""})
        {:error, {:build_failed, reason, directory}}
    end
  end

  defp finish_build(
         {:ok, result, output},
         id,
         root,
         directory,
         source,
         system_source,
         provenance,
         settings,
         opts
       ) do
    with {:ok, modules} <- store_artifacts(result.ebin, root),
         manifest = %Generation{
           parent: provenance.parent,
           modules: modules,
           boot: settings.boot,
           provenance: provenance
         },
         {:ok, fingerprint} <-
           candidate_fingerprint(source, system_source, result.ebin, manifest, settings),
         stored = %{
           id: id,
           root: root,
           source: source,
           system_source: system_source,
           ebin: result.ebin,
           evidence_dir: directory,
           manifest: manifest,
           fingerprint: fingerprint,
           settings: settings
         },
         :ok <- Evidence.write(directory, "candidate", stored),
         :ok <-
           Evidence.write(directory, "build", %{
             result: :ok,
             output: output,
             runtime: Map.take(result, [:os_pid, :node, :architecture]),
             fingerprint: fingerprint
           }) do
      candidate = struct!(__MODULE__, stored)
      {:ok, %{candidate | image: Keyword.get(opts, :image), control: Keyword.get(opts, :control)}}
    else
      {:error, reason} ->
        _ = Evidence.write(directory, "build", %{result: {:error, reason}, output: output})
        {:error, {:build_failed, reason, directory}}
    end
  end

  defp finish_build(
         {:error, reason, output},
         _id,
         _root,
         directory,
         _source,
         _system,
         _provenance,
         _settings,
         _opts
       ) do
    with :ok <- Evidence.write(directory, "build", %{result: {:error, reason}, output: output}) do
      {:error, {:build_failed, reason, directory}}
    end
  end

  defp snapshot_system(source, snapshot, system, _directory) when source == system,
    do: {:ok, snapshot}

  defp snapshot_system(_source, _snapshot, system, directory) do
    snapshot = Path.join(directory, "system/os")

    with :ok <- Evidence.copy_source(system, snapshot),
         :ok <- Evidence.copy_inputs(system, Path.dirname(snapshot)) do
      {:ok, snapshot}
    end
  end

  defp store_artifacts(ebin, root) do
    with {:ok, store} <- Store.open(Path.join(root, "store")) do
      Path.wildcard(Path.join(ebin, "*.beam"))
      |> Enum.reduce_while(%{}, fn path, modules ->
        with {:ok, bytes} <- File.read(path),
             info when is_list(info) <- :beam_lib.info(bytes),
             module when is_atom(module) and not is_nil(module) <- Keyword.get(info, :module),
             {:ok, hash} <- Store.put(store, bytes) do
          {:cont, Map.put(modules, module, hash)}
        else
          _ -> {:halt, {:error, {:invalid_build_artifact, path}}}
        end
      end)
      |> case do
        {:error, _} = error -> error
        modules when map_size(modules) > 0 -> {:ok, modules}
        _ -> {:error, :no_build_output}
      end
    end
  end

  defp run_suites(stored) do
    plan = [system_suite: stored.system_source, toolset_smoke: stored.system_source]

    plan =
      if stored.source == stored.system_source,
        do: plan,
        else: plan ++ [candidate_suite: stored.source]

    Enum.reduce(plan, {[], %{}}, fn {suite, source}, {failures, suites} ->
      directory = Path.join(stored.evidence_dir, "#{suite}-#{unique_id()}")

      {result, receipt} =
        run_suite(source, stored.ebin, suite, stored.settings, directory, stored.source)

      case result do
        :ok -> {failures, Map.put(suites, suite, receipt)}
        {:error, reason} -> {failures ++ [{suite, reason}], Map.put(suites, suite, receipt)}
      end
    end)
  end

  defp run_suite(source, ebin, suite, settings, directory, config_source) do
    files = suite_files(source, suite, settings.tool_tests)

    result =
      if files == [] do
        {:error, :suite_missing, ""}
      else
        Child.run(
          :suite,
          [source, ebin, files, Path.join(directory, "runtime"), settings.target, config_source],
          timeout: settings.timeout,
          evidence_dir: directory
        )
      end

    {outcome, receipt} =
      case result do
        {:ok, data, output} ->
          {:ok, Map.merge(data, %{result: :ok, output: output})}

        {:error, reason, output} ->
          {{:error, reason}, %{result: {:error, reason}, output: output}}
      end

    case Evidence.write(directory, "suite", receipt) do
      :ok -> {outcome, receipt}
      {:error, reason} -> {{:error, {:evidence_failed, reason}}, receipt}
    end
  end

  defp suite_result({result, _receipt}), do: result

  defp suite_files(source, suite, _tools) when suite in [:system_suite, :candidate_suite] do
    Path.wildcard(Path.join(source, "test/**/*_test.exs"))
    |> Enum.reject(
      &(String.contains?(&1, "/test/fixtures/") or String.contains?(&1, "/test/integration/"))
    )
  end

  defp suite_files(source, :toolset_smoke, tools) do
    tools |> Enum.flat_map(&Path.wildcard(Path.join(source, &1))) |> Enum.uniq() |> Enum.sort()
  end

  defp candidate_fingerprint(source, system_source, ebin, manifest, settings) do
    with {:ok, inputs} <- Evidence.fingerprint(Path.dirname(source)),
         {:ok, system} <-
           if(source == system_source,
             do: {:ok, inputs},
             else: Evidence.fingerprint(Path.dirname(system_source))
           ),
         {:ok, artifacts} <- Evidence.fingerprint(ebin) do
      contract = :erlang.term_to_binary({manifest, settings}, [:deterministic])
      {:ok, Store.hash(inputs <> system <> artifacts <> contract)}
    end
  end

  defp unchanged(stored) do
    case candidate_fingerprint(
           stored.source,
           stored.system_source,
           stored.ebin,
           stored.manifest,
           stored.settings
         ) do
      {:ok, fingerprint} when fingerprint == stored.fingerprint -> :ok
      _ -> {:error, :candidate_changed}
    end
  end

  defp validated(stored) do
    case Evidence.read(stored.evidence_dir, "test") do
      {:ok, %{result: :ok, fingerprint: fingerprint}} when fingerprint == stored.fingerprint ->
        :ok

      _ ->
        {:error, :not_validated}
    end
  end

  defp stored_candidate(%__MODULE__{id: id, root: root, evidence_dir: directory}) do
    with {:ok, %{id: ^id, root: ^root} = stored} <- Evidence.read(directory, "candidate"),
         true <- directory == Path.join([root, "evidence", "candidates", id]) do
      {:ok, stored}
    else
      _ -> {:error, :invalid_candidate}
    end
  end

  defp retain_proposal(stored, number, status) do
    directory = Path.join([stored.root, "evidence", Integer.to_string(number)])

    Evidence.write(directory, "proposal", %{
      generation: number,
      candidate_dir: stored.evidence_dir,
      provenance: stored.manifest.provenance,
      fingerprint: stored.fingerprint,
      status: status,
      created_at: DateTime.utc_now()
    })
  end

  defp health_manifest(0), do: {:ok, %Generation{number: 0}}
  defp health_manifest(number), do: Generation.read(Path.join(priv(), "generations"), number)

  defp health_inputs(number, suite) do
    case Evidence.read(evidence_dir(number), "proposal") do
      {:ok, %{candidate_dir: directory}} ->
        with {:ok, stored} <- Evidence.read(directory, "candidate"),
             :ok <- unchanged(stored) do
          source = if suite == :candidate_suite, do: stored.source, else: stored.system_source
          {:ok, source, stored.source, stored.settings}
        end

      {:error, :enoent} ->
        source = Application.get_env(:elixos, :health_source, factory_source())

        settings(source, [])
        |> case do
          {:ok, settings} -> {:ok, source, source, settings}
          error -> error
        end

      _ ->
        {:error, :corrupt_proposal_evidence}
    end
  end

  defp health_artifacts(number, manifest) do
    directory = Path.join(evidence_dir(number), "health-#{unique_id()}")
    ebin = Path.join(directory, "ebin")

    with :ok <- File.mkdir_p(ebin),
         {:ok, store} <- Store.open(Path.join(priv(), "store")) do
      Enum.reduce_while(manifest.modules, :ok, fn {module, hash}, :ok ->
        with {:ok, bytes} <- Store.get(store, hash),
             info when is_list(info) <- :beam_lib.info(bytes),
             ^module <- Keyword.get(info, :module),
             :ok <- File.write(Path.join(ebin, Atom.to_string(module) <> ".beam"), bytes) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:invalid_generation_blob, module}}}
        end
      end)
      |> case do
        :ok -> {:ok, ebin, directory}
        error -> error
      end
    end
  end

  defp checkout_source do
    case Application.fetch_env(:elixos, :candidate_source) do
      {:ok, source} when is_binary(source) -> {:ok, Path.expand(source)}
      :error -> generation_source()
      _ -> {:error, :invalid_source}
    end
  end

  defp generation_source do
    case Elixos.Boot.Env.current() do
      {:ok, %{generation: generation}} when generation > 0 ->
        with {:ok, %{candidate_dir: directory}} <-
               Evidence.read(evidence_dir(generation), "proposal"),
             {:ok, %{source: source}} <- Evidence.read(directory, "candidate") do
          {:ok, source}
        else
          {:error, :enoent} -> {:error, :generation_source_unavailable}
          error -> error
        end

      _ ->
        {:ok, source_root()}
    end
  end

  defp settings(source, opts) do
    target =
      Keyword.get(
        opts,
        :target,
        if(match?({:ok, :host}, Elixos.Boot.Env.current()), do: :host, else: :elixos)
      )

    tools = Keyword.get(opts, :tool_tests, default_tool_tests())
    timeout = Keyword.get(opts, :timeout, 120_000)
    boot = Keyword.get(opts, :boot, [])

    origin =
      case Evidence.read(source, ".candidate-origin") do
        {:ok, origin} when is_map(origin) -> origin
        _ -> %{}
      end

    deps = Keyword.get(opts, :deps_path, Map.get(origin, :deps_path, Path.join(source, "deps")))

    coding =
      Keyword.get(opts, :coding_source, Map.get(origin, :coding_source, coding_source(source)))

    system_source =
      Keyword.get(
        opts,
        :system_source,
        Application.get_env(:elixos, :candidate_system_source, factory_source())
      )

    if target in [:host, :elixos] and is_integer(timeout) and timeout > 0 and
         is_binary(deps) and is_binary(coding) and is_binary(system_source) and is_list(tools) and
         Enum.all?(tools, &relative_pattern?/1) and is_list(boot) and
         Enum.all?(boot, &boot_mfa?/1) do
      {:ok,
       %{
         target: target,
         tool_tests: tools,
         timeout: timeout,
         boot: boot,
         deps_path: Path.expand(deps),
         coding_source: Path.expand(coding),
         system_source: Path.expand(system_source)
       }}
    else
      {:error, :invalid_build_options}
    end
  end

  # Where `source`'s mix.exs finds Oh-My-Jido: the factory ships it beside the
  # OS source (`/factory/source/oh_my_jido`); a host checkout keeps mix.exs's
  # own default, unless the caller's environment overrides both.
  defp coding_source(source) do
    sibling = Path.join(Path.dirname(source), "oh_my_jido")

    cond do
      value = System.get_env("ELIXOS_OH_MY_JIDO_SOURCE") -> Path.expand(value)
      File.regular?(Path.join(sibling, "mix.exs")) -> sibling
      true -> Path.expand("../../oh_my_jido", source)
    end
  end

  defp relative_pattern?(pattern) when is_binary(pattern),
    do: Path.type(pattern) == :relative and ".." not in Path.split(pattern)

  defp relative_pattern?(_), do: false

  defp boot_mfa?({module, function, args}),
    do: is_atom(module) and is_atom(function) and is_list(args) and durable?(args)

  defp boot_mfa?(_), do: false

  defp validate_provenance(
         %{session: session, model: model, tools: tools, parent: parent} = provenance
       )
       when is_binary(model) and byte_size(model) > 0 and is_map(tools) and
              is_integer(parent) and parent >= 0 and parent <= 4_294_967_295 do
    if durable?(session) and durable?(provenance),
      do: {:ok, provenance},
      else: {:error, :invalid_provenance}
  end

  defp validate_provenance(_), do: {:error, :invalid_provenance}

  defp durable?(value)
       when is_pid(value) or is_port(value) or is_reference(value) or is_function(value),
       do: false

  defp durable?(value) when is_map(value),
    do: Enum.all?(value, fn {key, value} -> durable?(key) and durable?(value) end)

  defp durable?(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.all?(&durable?/1)

  defp durable?(value) when is_list(value), do: Enum.all?(value, &durable?/1)
  defp durable?(_), do: true

  defp service(nil, name, error) do
    case Process.whereis(name) do
      nil -> {:error, error}
      pid -> {:ok, pid}
    end
  end

  defp service(server, _name, _error), do: {:ok, server}

  defp default_tool_tests, do: Application.get_env(:elixos, :candidate_tool_tests, @default_tools)
  defp priv, do: Path.expand(Application.get_env(:elixos, :priv_dir, "/priv"))
  defp unique_id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
end
