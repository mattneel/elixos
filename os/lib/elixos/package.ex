defmodule Elixos.Package do
  @moduledoc """
  Installing software onto the running system (M11 self-hosting, M14 by name).

  A **path** is installed as it stands: `install("/priv/src/my_app")` builds the
  Mix project in place with `MIX_TARGET=elixos` (so its `config/elixos.exs`
  applies and `targets: :elixos` deps are included), resolves its dependencies
  system-wide (`Elixos.Package.Resolver`), loads it into the running VM, starts
  the services from its `elixos:` key (`Elixos.Package.Spec`), and records it in
  the image so the next `Elixos.save/1` includes it. NIFs compile with the
  bundled `zig cc` (ADR-009) against the running ERTS.

  A **name** is installed from the trusted Hex repositories (M14, ADR-019):

      iex> Elixos.Package.install(:hello_pkg)
      {:ok, :hello_pkg}

  The name is resolved among the repositories `/priv/hex/repos.exs` lists —
  which is the entire trust decision, so an install never trusts a repository
  implicitly — the tarball is fetched, verified and unpacked into
  `/priv/apps/<name>-<version>/`, and that directory goes through the same path
  as an explicit one. A name offered by two repositories is an error naming
  both. `:elixos` is never fetched: it is the running OS.

  The apt verbs are functions here, not commands (ADR-019): `add_repo/3`,
  `remove_repo/1`, `repos/0`, `search/1`, `info/1`, `upgrade/0,1`, `remove/1`.
  """

  @doc """
  Installs the Mix project at `dir`, or the package called `name`.

  With a name, the repository is chosen among the trusted ones and the unpacked
  directory is installed as if it had been given directly.
  """
  @spec install(Path.t() | atom()) :: {:ok, atom()} | {:error, term()}
  def install(dir) when is_binary(dir) do
    root = Path.expand(dir)

    with {:ok, spec} <- spec(root),
         {:ok, app, version, ebin} <- build(root),
         :ok <- load(app, ebin),
         :ok <- start_services(spec.services),
         :ok <- record(app, version, spec) do
      {:ok, app}
    end
  end

  def install(name) when is_atom(name),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.install/1 #{inspect(name)}")

  @doc "Installed apps and versions."
  @spec installed() :: %{atom() => String.t()}
  def installed do
    case Process.whereis(Elixos.Image) do
      nil -> %{}
      image -> Elixos.Image.apps(image)
    end
  end

  ## A path install

  defp spec(root) do
    case Elixos.Package.Spec.read_project(root) do
      {:ok, :none} -> {:ok, %Elixos.Package.Spec{}}
      {:ok, spec} -> {:ok, spec}
      {:error, reason} -> {:error, {:malformed_spec, reason}}
    end
  end

  # The build half: a child ERTS, exec'd directly - this VM's working
  # directory is not a build directory (ADR-016) - running Mix with
  # MIX_TARGET=elixos so config/elixos.exs applies. `--no-deps-check` is what
  # makes `:elixos` a dependency on the *running OS*: its modules are loaded
  # here already, and Mix must not go looking for the path the project names.
  defp build(root) do
    env = [
      {"MIX_ENV", "prod"},
      {"MIX_TARGET", "elixos"},
      {"MIX_HOME", "/priv/mix"},
      {"HEX_HOME", "/priv/hex-home"},
      {"ROOTDIR", factory()},
      {"BINDIR", Path.join(factory(), "erts/bin")}
    ]

    # -eval is Erlang, so this calls the Elixir Mix.Own entry point the way
    # the mix script itself does: a list of binaries, no shell anywhere.
    code = ~s|'Elixir.Mix.CLI':main([<<"compile">>, <<"--no-deps-check">>])|

    # The release's boot script resolves $RELEASE_LIB against the boot_var the
    # shim passes, so a child ERTS has to pass it too.
    args = [
      "-noshell",
      "-boot",
      boot_script(),
      "-boot_var",
      "RELEASE_LIB",
      lib_dir(),
      "-config",
      sys_config(),
      "-pa",
      mix_ebin(),
      "-eval",
      code
    ]

    {output, status} =
      System.cmd(erlexec(), args, cd: root, env: env, stderr_to_stdout: true)

    if status == 0 do
      ebin = Path.join([root, "_build", "elixos_prod", "lib", app_dir(root), "ebin"])

      cond do
        ebin == nil -> {:error, {:no_build_output, root, output}}
        true -> {:ok, app_of(ebin), version_of(ebin), ebin}
      end
    else
      {:error, {:build_failed, status, output}}
    end
  end

  defp app_dir(root) do
    case File.ls(Path.join([root, "_build", "elixos_prod", "lib"])) do
      {:ok, [dir | _]} -> dir
      _other -> nil
    end
  end

  defp app_of(ebin) do
    Path.basename(ebin)
    |> String.split("-")
    |> hd()
    |> String.to_atom()
  end

  defp version_of(ebin) do
    Path.basename(ebin)
    |> String.split("-")
    |> List.last()
  end

  defp load(app, ebin) do
    :code.add_paths([String.to_charlist(ebin)])

    case Application.load(app) do
      :ok -> :ok
      {:error, {:already_loaded, ^app}} -> :ok
      {:error, reason} -> {:error, {:load_failed, app, reason}}
    end
  end

  @doc """
  Starts one service under the system's tree. (M11)

  The generation's boot list calls this, which is what brings an installed
  app's services back after a power cycle.
  """
  @spec start_service(term()) :: :ok | {:error, term()}
  def start_service(service) do
    case DynamicSupervisor.start_child(Elixos.Supervisor, child_spec(service)) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, {:service_failed, service, reason}}
    end
  end

  defp start_services(services) do
    for service <- services, service_child(service) do
      case start_service(service) do
        :ok -> :ok
        {:error, reason} -> throw({:error, reason})
      end
    end

    :ok
  catch
    {:error, reason} -> {:error, reason}
  end

  defp service_child({module, _arg}) when is_atom(module), do: true
  defp service_child(module) when is_atom(module), do: true
  defp service_child(_other), do: false

  defp child_spec({module, arg}), do: %{id: module, start: {module, :start_link, [arg]}}
  defp child_spec(module), do: %{id: module, start: {module, :start_link, []}}

  defp record(app, version, spec) do
    case Process.whereis(Elixos.Image) do
      nil -> {:error, :no_image}
      image -> Elixos.Image.record_app(image, app, version, spec.services)
    end
  end

  defp factory, do: Application.get_env(:elixos, :factory_dir, "/factory")
  defp erlexec, do: Path.join([factory(), "erts", "bin", "erlexec"])
  defp mix_ebin, do: Path.join([factory(), "lib", "mix", "ebin"])
  defp boot_script, do: Path.join([factory(), "releases", "current", "start"])
  defp lib_dir, do: Path.join(factory(), "lib")
  defp sys_config, do: Path.join([factory(), "releases", "current", "sys.config"])

  @doc """
  Adds the Hex repository `name` at `url`, trusting it with `key` (its RSA
  public key, PEM). `{:error, :bad_key}` for anything that is not one, and
  `{:error, :already_configured}` unless `replace: true`.

  Nothing is fetched from `url` to learn the key: a repository's key arrives
  from the human (or a fingerprint they verified), which is what makes adding
  it the consent step (ADR-019).
  """
  @spec add_repo(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def add_repo(name, url, opts \\ []),
    do:
      Elixos.NotImplemented.raise!(14, "Elixos.Package.add_repo/3 #{inspect({name, url, opts})}")

  @doc "Removes a repository and its key. Installed packages stay installed."
  @spec remove_repo(atom()) :: :ok | {:error, term()}
  def remove_repo(name),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.remove_repo/1 #{inspect(name)}")

  @doc "The trusted repositories, in configuration order."
  @spec repos() :: [Elixos.Package.Repo.t()]
  def repos, do: Elixos.NotImplemented.raise!(14, "Elixos.Package.repos/0")

  @doc """
  Packages whose name matches `query` (a string prefix or a `Regex`), across
  the trusted repositories. A static repository has no search API, so this
  matches against its names index.
  """
  @spec search(String.t() | Regex.t()) :: [
          %{name: String.t(), repo: atom(), versions: [String.t()]}
        ]
  def search(query),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.search/1 #{inspect(query)}")

  @doc """
  What is known about a package: its name, the repository it comes from, the
  versions available, and whether it is installed.
  """
  @spec info(String.t() | atom()) :: {:ok, map()} | {:error, term()}
  def info(name), do: Elixos.NotImplemented.raise!(14, "Elixos.Package.info/1 #{inspect(name)}")

  @doc "Upgrades every installed package, or just `name`, to the newest release."
  @spec upgrade() :: %{atom() => {:ok, String.t()} | {:error, term()}}
  def upgrade, do: Elixos.NotImplemented.raise!(14, "Elixos.Package.upgrade/0")

  @spec upgrade(atom()) :: {:ok, String.t()} | {:error, term()}
  def upgrade(name),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.upgrade/1 #{inspect(name)}")

  @doc "Uninstalls `name`: its services stop, its modules unload, its files go."
  @spec remove(atom()) :: :ok | {:error, term()}
  def remove(name),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.remove/1 #{inspect(name)}")
end
