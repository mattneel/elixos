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
    * `:persist` - relative paths (no `..`, not absolute) under the app's data dir
    * `:min_os` - `Version` requirement on the running Elixos
    * `:boot` - `:auto` (start at boot) or `:manual`

  `from_project/1` returns `{:ok, :none}` when there is no `elixos:` key, and
  otherwise collects every problem as `{key, reason}` sorted by key:

    * `{:elixos, :not_a_keyword_list}`
    * `{:services, :invalid}`
    * `{:persist, :invalid | :absolute_path | :parent_path}`
    * `{:min_os, :invalid_requirement}`
    * `{:boot, :invalid}`
    * `{key, :unknown_key}`
  """

  defstruct services: [], persist: [], min_os: nil, boot: :auto

  @type t :: %__MODULE__{
          services: [module() | {module(), term()}],
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
  defp build(elixos) when is_list(elixos) do
    errors =
      elixos
      |> Enum.flat_map(&check/1)
      |> Enum.sort()

    if errors == [] do
      {:ok,
       %__MODULE__{
         services: Keyword.get(elixos, :services, []),
         persist: Keyword.get(elixos, :persist, []),
         min_os: Keyword.get(elixos, :min_os),
         boot: Keyword.get(elixos, :boot, :auto)
       }}
    else
      {:error, errors}
    end
  end

  defp build(_other), do: {:error, [elixos: :not_a_keyword_list]}

  defp check({:services, services}) do
    case services do
      [_ | _] = list ->
        if Enum.all?(list, &service?/1), do: [], else: [services: :invalid]

      _other ->
        [services: :invalid]
    end
  end

  defp check({:persist, paths}) when is_list(paths) do
    Enum.flat_map(paths, fn
      path when is_binary(path) ->
        cond do
          Path.type(path) == :absolute -> [persist: :absolute_path]
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
  Reads the `elixos:` key from the Mix project in `dir` without building it.

  It must not change the VM's working directory, not even briefly (ADR-016):
  every program on Elixos shares this VM, and `Mix.Project.in_project/4`
  cd's all of them. Hint, verified on Elixir 1.20.4: compiling a mix.exs runs
  `Mix.Project.__after_compile__/2`, which pushes the project onto Mix's
  stack; read `Mix.Project.config/0`, `Mix.Project.pop/0`, then unload the
  modules mix.exs defined.
  """
  @spec read_project(Path.t()) :: {:ok, t() | :none} | {:error, term()}
  def read_project(dir) do
    path = Path.join(dir, "mix.exs")

    with {:ok, modules} <- compile_mix_exs(path) do
      try do
        # Compiling the file is what pushes the project (its __after_compile__),
        # so the stack is balanced by popping it here whatever happens next.
        config = Mix.Project.config()
        Mix.Project.pop()
        from_project(config)
      after
        unload(modules)
      end
    end
  end

  defp compile_mix_exs(path) do
    {:ok, Code.compile_file(path)}
  rescue
    error -> {:error, error}
  end

  # mix.exs defines its project module in this VM, and read_project has no
  # business leaving it loaded: the next read would see it as already there.
  defp unload(modules) do
    for {module, _binary} <- modules do
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
