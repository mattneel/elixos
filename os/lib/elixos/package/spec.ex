defmodule Elixos.Package.Spec do
  @moduledoc """
  The `elixos:` key in a regular `mix.exs` (ADR-011, docs/ARCHITECTURE.md §7).

  It says how an app wants to be installed on Elixos. Plain Mix ignores the key,
  so the same project still builds and runs on any host.

      def project do
        [
          app: :my_app,
          # ...
          elixos: [
            services: [MyApp.Worker, {MyApp.Server, port: 4000}],
            persist: ["db", "uploads"],
            min_os: "~> 0.1",
            boot: :auto
          ]
        ]
      end

  Keys:

    * `:services` - modules or `{module, arg}` started under the system
      supervision tree when the app is installed
    * `:oban` - `queues:` and `cron:` the app wants the system's scheduler to
      run (M19, docs/ROADMAP.md)
    * `:persist` - relative paths (no `..`, not absolute) under the app's data dir
    * `:min_os` - `Version` requirement on the running Elixos
    * `:boot` - `:auto` (start at boot) or `:manual`

  `from_project/1` returns `{:ok, :none}` when there is no `elixos:` key, and
  otherwise collects every problem as `{key, reason}` sorted by key:

    * `{:elixos, :not_a_keyword_list}`
    * `{:services, :invalid}`
    * `{:oban, :invalid}`
    * `{:persist, :invalid | :absolute_path | :parent_path}`
    * `{:min_os, :invalid_requirement}`
    * `{:boot, :invalid}`
    * `{key, :unknown_key}`
  """

  defstruct services: [], oban: [], persist: [], min_os: nil, boot: :auto

  @type t :: %__MODULE__{
          services: [module() | {module(), term()}],
          oban: keyword(),
          persist: [String.t()],
          min_os: String.t() | nil,
          boot: :auto | :manual
        }

  @spec from_project(keyword()) :: {:ok, t() | :none} | {:error, [{atom(), atom()}]}
  def from_project(project) when is_list(project) do
    case Keyword.fetch(project, :elixos) do
      :error -> {:ok, :none}
      {:ok, elixos} -> build(elixos)
    end
  end

  # Every problem is collected, not just the first: an app that opts in should
  # learn everything that is wrong in one go.
  defp build(elixos) do
    if Keyword.keyword?(elixos),
      do: collect(elixos),
      else: {:error, [elixos: :not_a_keyword_list]}
  end

  defp collect(elixos) do
    errors =
      elixos
      |> Enum.flat_map(&check/1)
      |> Enum.sort()

    if errors == [] do
      {:ok,
       %__MODULE__{
         services: Keyword.get(elixos, :services, []),
         oban: Keyword.get(elixos, :oban, []),
         persist: Keyword.get(elixos, :persist, []),
         min_os: Keyword.get(elixos, :min_os),
         boot: Keyword.get(elixos, :boot, :auto)
       }}
    else
      {:error, errors}
    end
  end

  defp check({:services, services}) when is_list(services) do
    # An empty list is the default, said out loud, and is fine.
    if Enum.all?(services, &service?/1), do: [], else: [services: :invalid]
  end

  defp check({:services, _other}), do: [services: :invalid]

  # Queues and cron are validated by the scheduler's own declaration module
  # (M19): the shape an app writes is the shape Oban is configured with.
  defp check({:oban, oban}) do
    case Elixos.Oban.Declaration.validate(oban) do
      :ok -> []
      {:error, :invalid} -> [oban: :invalid]
    end
  end

  defp check({:persist, paths}) when is_list(paths) do
    Enum.flat_map(paths, fn
      path when is_binary(path) ->
        cond do
          path == "" or String.contains?(path, <<0>>) -> [persist: :invalid]
          Path.type(path) != :relative -> [persist: :absolute_path]
          ".." in Path.split(path) -> [persist: :parent_path]
          true -> []
        end

      _other ->
        [persist: :invalid]
    end)
  end

  defp check({:persist, _other}), do: [persist: :invalid]

  defp check({:min_os, requirement}) when is_binary(requirement) do
    case Version.parse_requirement(requirement) do
      {:ok, _parsed} -> []
      :error -> [min_os: :invalid_requirement]
    end
  end

  defp check({:min_os, _other}), do: [min_os: :invalid_requirement]

  defp check({:boot, boot}) when boot in [:auto, :manual], do: []
  defp check({:boot, _other}), do: [boot: :invalid]

  defp check({key, _value}), do: [{key, :unknown_key}]

  defp service?(module) when is_atom(module), do: true
  defp service?({module, _arg}) when is_atom(module), do: true
  defp service?(_other), do: false

  @doc """
  Reads the app, version, effective dependencies and `elixos:` declaration of
  the Mix project in `dir` under the installer's `:prod` / `:elixos` settings.

  The locked read never changes the VM's cwd or OS environment. Mix's scoped
  environment, target and complete project stack are restored even if project
  evaluation fails, and modules defined by the project file are unloaded.
  """
  @spec read_project(Path.t()) ::
          {:ok, %{app: atom(), version: String.t(), deps: %{atom() => String.t()}, spec: t()}}
          | {:error, term()}
  def read_project(dir) do
    path = Path.expand("mix.exs", dir)

    # Lock requesters must be distinct: a constant requester ID would let
    # concurrent reads share a lock and exchange Mix's global project state.
    :global.trans({__MODULE__, self()}, fn -> read_locked(path) end, [node()])
  end

  defp loaded_modules do
    MapSet.new(for {module, _file} <- :code.all_loaded(), do: module)
  end

  defp read_locked(path) do
    env = Mix.env()
    target = Mix.target()
    loaded = loaded_modules()

    try do
      Mix.env(:prod)
      Mix.target(:elixos)

      Mix.ProjectStack.on_clean_slate(fn ->
        Code.compile_file(path)

        if Mix.Project.get() do
          project_metadata(Mix.Project.config())
        else
          {:error, :no_mix_project}
        end
      end)
    rescue
      error -> {:error, error}
    after
      Mix.env(env)
      Mix.target(target)
      loaded_modules()
      |> MapSet.difference(loaded)
      |> Enum.filter(&defined_in?(&1, path))
      |> unload()
    end
  end

  defp project_metadata(project) do
    app = project[:app]
    version = project[:version]

    with :ok <- check_app(app),
         {:ok, _version} <- Version.parse(version || ""),
         {:ok, deps} <- project_deps(project[:deps] || []),
         {:ok, spec} <- from_project(project) do
      {:ok,
       %{app: app, version: version, deps: deps, spec: if(spec == :none, do: %__MODULE__{}, else: spec)}}
    else
      :error -> {:error, {:invalid_project_version, version}}
      {:error, _reason} = error -> error
    end
  end

  defp check_app(app) when is_atom(app) and app not in [nil, true, false] do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, Atom.to_string(app)),
      do: :ok,
      else: {:error, {:invalid_project_app, app}}
  end

  defp check_app(app), do: {:error, {:invalid_project_app, app}}

  defp project_deps(deps) when is_list(deps) do
    Enum.reduce_while(deps, {:ok, %{}}, fn dep, {:ok, requirements} ->
      with {:ok, app, requirement, opts} <- dependency(dep),
           :ok <- check_app(app),
           true <- Keyword.keyword?(opts) do
        cond do
          Mix.Dep.Loader.skip?(%Mix.Dep{opts: opts}, {:prod, :elixos}) ->
            {:cont, {:ok, requirements}}

          is_nil(requirement) ->
            {:cont, {:ok, Map.put(requirements, app, ">= 0.0.0")}}

          is_binary(requirement) and match?({:ok, _}, Version.parse_requirement(requirement)) ->
            {:cont, {:ok, Map.put(requirements, app, requirement)}}

          true ->
            {:halt, {:error, {:invalid_dependency, dep}}}
        end
      else
        _ -> {:halt, {:error, {:invalid_dependency, dep}}}
      end
    end)
  end

  defp project_deps(deps), do: {:error, {:invalid_dependencies, deps}}

  defp dependency({app, opts}) when is_list(opts), do: {:ok, app, nil, opts}
  defp dependency({app, requirement}), do: {:ok, app, requirement, []}
  defp dependency({app, requirement, opts}) when is_list(opts), do: {:ok, app, requirement, opts}
  defp dependency(dep), do: {:error, {:invalid_dependency, dep}}

  defp defined_in?(module, path) do
    source = module.module_info(:compile)[:source]
    source != nil and Path.expand(to_string(source)) == path
  rescue
    _ -> false
  end

  # Only modules this read loaded are unloaded. A module that was already
  # loaded stays as it is: purging it could kill processes still running the
  # old version, and the reader has no business doing that to the VM.
  defp unload(modules) do
    for module <- modules do
      :code.purge(module)
      :code.delete(module)
      :code.purge(module)
    end
  end

  @spec check_os(t(), String.t()) :: :ok | {:error, {:incompatible_os, String.t(), String.t()}}
  def check_os(%__MODULE__{min_os: nil}, _os_version), do: :ok

  def check_os(%__MODULE__{min_os: requirement}, os_version) do
    # Elixir's own semantics: "~> 0.1" is >= 0.1.0 and < 1.0.0.
    if Version.match?(os_version, requirement) do
      :ok
    else
      {:error, {:incompatible_os, requirement, os_version}}
    end
  end
end
