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
    Elixos.NotImplemented.raise!(10, "Elixos.Package.Spec.from_project/1")
  end

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
  def read_project(dir),
    do: Elixos.NotImplemented.raise!(10, "Elixos.Package.Spec.read_project/1 #{dir}")

  @spec check_os(t(), String.t()) :: :ok | {:error, {:incompatible_os, String.t(), String.t()}}
  def check_os(%__MODULE__{} = spec, os_version) do
    _ = {spec, os_version}
    Elixos.NotImplemented.raise!(10, "Elixos.Package.Spec.check_os/2")
  end
end
