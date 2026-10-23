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

  Project metadata and compilation both use `Mix.target() == :elixos` and
  `Mix.env() == :prod`. The exact declared app's application resource supplies
  its built version; dependencies are checked system-wide before building.
  Target config is recorded with the install and reapplied at boot.

  App state belongs in `data_dir/1`, outside its replaceable installed tree.
  Declared `persist:` directories are created there without following
  symlinks, and are retained on upgrades and removal. `boot: :manual` permits
  services and Oban at explicit installation but never auto-starts them from
  a later saved generation.

  A **name** is installed from the trusted Hex repositories (M14, ADR-019):

      iex> Elixos.Package.install(:hello_pkg)
      {:ok, :hello_pkg}

  The name is resolved among the repositories `/priv/hex/repos.exs` lists —
  which is the entire trust decision, so an install never trusts a repository
  implicitly — the tarball is fetched, verified and unpacked into
  `/priv/apps/<name>-<version>/`, and that directory goes through the same path
  as an explicit one. The compiled runtime tree is installed separately at
  `/priv/apps/<name>/`. A later build resolves an installed dependency there
  through `Elixos.Package.SCM` (M26). A name offered by two repositories is an error naming
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

    if File.regular?(Path.join(root, "mix.exs")) do
      install_project(root)
    else
      install_payload(root)
    end
  end

  def install(name) when is_atom(name) do
    string = Atom.to_string(name)

    with {:ok, closure} <- Elixos.Package.Hex.closure(string),
         :ok <- check_plan(closure),
         :ok <- install_closure(closure) do
      {:ok, name}
    end
  end

  # One version of every package (ADR-015): the resolver weighs the whole
  # closure, and everything already installed, before anything is unpacked.
  defp check_plan(closure) do
    check_packages(closure_packages(closure))
  end

  defp check_packages(incoming) do
    case Elixos.Package.Resolver.plan(installed_packages(), incoming, os_version()) do
      {:ok, _plan} -> :ok
      {:error, conflicts} -> {:error, {:conflicts, conflicts}}
    end
  end

  defp closure_packages(closure) do
    for entry <- closure do
      %{app: String.to_atom(entry.name), version: entry.version, deps: atom_deps(entry.deps)}
    end
  end

  # Dependencies first: a package that requires another compiles against it,
  # so it has to be there when the child ERTS builds it.
  defp install_closure(closure) do
    incoming = closure_packages(closure)

    Enum.reduce(Enum.zip(closure, incoming), incoming, fn {entry, expected}, pending ->
      dir = Path.join([os_priv(), "apps", "#{entry.name}-#{entry.version}"])

      case Elixos.Package.Hex.unpack(entry.repo, entry.name, entry.version, dir) do
        {:ok, ^dir} ->
          case install_project_or_payload(dir, expected, pending) do
            # Later planning must retain this install's actual target deps,
            # not replace them again with the registry's source-level deps.
            {:ok, _app} -> Enum.reject(pending, &(&1.app == expected.app))
            {:error, reason} -> throw({:error, {:install_failed, entry.name, reason}})
          end

        {:error, reason} ->
          throw({:error, {:unpack_failed, entry.name, reason}})
      end
    end)

    :ok
  catch
    {:error, reason} -> {:error, reason}
  end

  defp install_project_or_payload(dir, expected, incoming) do
    if File.regular?(Path.join(dir, "mix.exs")) do
      install_project(dir, expected, incoming)
    else
      install_payload(dir, expected, incoming)
    end
  end

  defp install_project(root, expected \\ nil, incoming \\ []) do
    with {:ok, project} <- Elixos.Package.Spec.read_project(root),
         :ok <- Elixos.Package.Spec.check_os(project.spec, os_version()),
         :ok <- check_identity(project, expected),
         :ok <- check_project_plan(project, incoming),
         {:ok, config} <- read_config(root),
         {:ok, app, version, ebin} <- build(root, project.app),
         :ok <- check_built_version(project, version),
         :ok <- install_tree(app, ebin, root),
         :ok <- prepare_app(app, project.spec.persist, config),
         :ok <- load(app, installed_ebin(app)),
         :ok <- configure_oban(app, project.spec.oban),
         :ok <- start_services(project.spec.services),
         :ok <- record(app, version, project.spec, project.deps, config) do
      {:ok, app}
    end
  end

  defp check_identity(_project, nil), do: :ok

  defp check_identity(%{app: app, version: version}, %{app: app, version: version}), do: :ok

  defp check_identity(project, expected) do
    {:error, {:package_identity_mismatch, {expected.app, expected.version}, {project.app, project.version}}}
  end

  defp check_project_plan(project, incoming) do
    package = Map.take(project, [:app, :version, :deps])
    # The signed closure was checked before unpacking. Keep planning over the
    # whole closure here, not an intermediate upgrade that temporarily still
    # has an old dependent installed, while also checking target-effective deps.
    remaining = Enum.reject(incoming, &(&1.app == project.app))
    check_packages([package | remaining])
  end

  defp check_built_version(%{version: version}, version), do: :ok
  defp check_built_version(project, version),
    do: {:error, {:built_version_mismatch, project.app, project.version, version}}

  # The scheduler is configured before the app's services start - a service
  # may enqueue - and a refusal is an install failure, not a silent drop: the
  # app is not recorded, so the next boot does not pretend it was installed.
  # No scheduler (rescue, or Postgres down) is not a refusal: the declaration
  # is recorded and applies at the next normal boot.
  defp configure_oban(app, declaration) do
    case Elixos.Oban.configure_app(app, declaration) do
      :ok -> :ok
      {:error, :not_running} -> :ok
      {:error, reason} -> {:error, {:oban, reason}}
    end
  end

  # A package without a Mix project is a *payload*: the toolchain (ADR-009) is
  # the only one, and it is taken where it lies (the disk's /priv/toolchain is
  # 421M; copying it would be waste) and recorded, so it is part of the image
  # like any package.
  defp install_payload(root, expected \\ nil, incoming \\ []) do
    package =
      expected || %{app: root |> Path.basename() |> String.to_atom(), version: payload_version(root), deps: %{}}

    with :ok <- check_packages(if(incoming == [], do: [package], else: incoming)),
         :ok <- record(package.app, package.version, %Elixos.Package.Spec{}, package.deps, []) do
      {:ok, package.app}
    end
  end

  defp payload_version(root) do
    case File.read(Path.join(root, "VERSION")) do
      {:ok, version} -> String.trim(version)
      _other -> "0.0.0"
    end
  end

  @doc "Installed apps and versions."
  @spec installed() :: %{atom() => String.t()}
  def installed do
    case Process.whereis(Elixos.Image) do
      nil -> %{}
      image -> Elixos.Image.apps(image)
    end
  end

  ## A path install

  # Metadata and compilation use the same target/environment pair.
  # The build half: a child ERTS, exec'd directly - this VM's working
  # directory is not a build directory (ADR-016) - running Mix with
  # MIX_TARGET=elixos so config/elixos.exs applies. `--no-deps-check` is what
  # makes `:elixos` a dependency on the *running OS*: its modules are loaded
  # here already, and Mix must not go looking for the path the project names.
  @doc false
  def compile_project do
    Mix.start()
    Mix.SCM.prepend(Elixos.Package.SCM)
    Mix.CLI.main(["compile", "--no-deps-check"])

    project = Mix.Project.config()
    app = Keyword.fetch!(project, :app)
    version = Keyword.fetch!(project, :version)
    resource = Path.join(Mix.Project.compile_path(), "#{app}.app")

    # A version read from another file need not change mix.exs or any BEAM.
    # Refresh only its stale application resource, not all native compilers.
    if app_version(app, resource) != {:ok, version} do
      Mix.Task.reenable("compile.app")

      case Mix.Task.run("compile.app", ["--force"]) do
        {:error, diagnostics} -> Mix.raise("application resource compilation failed: #{inspect(diagnostics)}")
        _result -> :ok
      end
    end
  end

  defp build(root, app) do
    env = [
      {"MIX_ENV", "prod"},
      {"MIX_TARGET", "elixos"},
      {"MIX_HOME", "/priv/mix"},
      {"HEX_HOME", "/priv/hex-home"},
      {"MIX_BUILD_PATH", nil},
      {"MIX_DEPS_PATH", nil},
      {"MIX_PATH", nil},
      {"ROOTDIR", factory()},
      {"BINDIR", Path.join(factory(), "erts/bin")}
    ]

    # -eval is Erlang, so this calls the Elixir Mix.CLI entry point the way
    # the mix script itself does: a list of binaries, no shell anywhere.
    # A failure makes the eval fail, which ends the child non-zero on its own;
    # a success halts explicitly, otherwise the clean child keeps running
    # and System.cmd waits forever.
    #
    # An installed package is a dependency (M26): prepended before any SCM Mix
    # starts with, Elixos.Package.SCM answers for dependencies this box already
    # has, so a project resolves them where they are installed instead of a
    # repository it cannot reach.
    code = ~s|'Elixir.Elixos.Package':compile_project(), erlang:halt(0)|

    # The release's boot script resolves $RELEASE_LIB against the boot_var the
    # shim passes, so a child ERTS has to pass it too.
    # A package that requires an installed one compiles against it: the
    # child sees every installed app's ebin, the way this VM does.
    args =
      [
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
      ] ++
        Enum.flat_map(Path.wildcard(Path.join(os_priv(), "apps/*/ebin")), &["-pa", &1])

    {output, status} =
      System.cmd(erlexec(), args, cd: root, env: env, stderr_to_stdout: true)

    if status == 0 do
      build_output(root, app)
    else
      {:error, {:build_failed, status, output}}
    end
  rescue
    error -> {:error, {:build_failed, Exception.message(error)}}
  end

  @doc false
  @spec build_output(Path.t(), atom()) ::
          {:ok, atom(), String.t(), Path.t()} | {:error, term()}
  def build_output(root, app) do
    ebin = Path.join([root, "_build", "elixos_prod", "lib", Atom.to_string(app), "ebin"])
    path = Path.join(ebin, "#{app}.app")

    case app_version(app, path) do
      {:ok, version} -> {:ok, app, version, ebin}
      {:error, :enoent} -> {:error, {:no_build_output, app, path}}
      {:error, reason} -> {:error, {:invalid_build_output, app, path, reason}}
    end
  end

  # Keep the target config itself, not only its effects on this VM: a saved
  # generation must apply it again before any installed service starts.
  defp read_config(root) do
    path = Path.join(root, "config/config.exs")

    if File.regular?(path),
      do: {:ok, Config.Reader.read!(path, env: :prod, target: :elixos)},
      else: {:ok, []}
  rescue
    error -> {:error, {:config_failed, Exception.message(error)}}
  end

  # The build's artifacts are part of the image: the whole app directory -
  # ebin for the code path, priv for what ebin loads (a NIF, for one) - is
  # copied to the disk, where the next boot finds it (PROTOCOL.md §7).
  defp install_tree(app, ebin, root) do
    dest = installed_dir(app)
    File.rm_rf!(dest)
    File.mkdir_p!(Path.dirname(dest))
    File.cp_r!(Path.dirname(ebin), dest, dereference_symlinks: true)

    # Mix links a project's priv into the build dir when the build starts; a
    # compiler that creates priv while compiling (the NIF fixture does) is
    # later than that, so the project's priv is what ebin loads from at run
    # time. Copy it beside ebin.
    priv = Path.join(root, "priv")
    if File.dir?(priv), do: File.cp_r!(priv, Path.join(dest, "priv"), dereference_symlinks: true)

    :ok
  end

  @doc """
  The directory an installed package lives in: `$priv/apps/<name>`.

  Its whole build dir - ebin and priv - is there (PROTOCOL.md §7). Public
  because a build resolves installed packages to it (M26,
  `Elixos.Package.SCM`).
  """
  def installed_dir(app), do: Path.join([os_priv(), "apps", Atom.to_string(app)])

  @doc """
  The app's state directory: `$priv/data/<app>` (`/priv/data/<app>` normally).

  `elixos: [persist: ...]` names relative directories below this root. State
  is ordinary filesystem data, separate from replaceable installed code and
  retained on upgrades and removal. This does not add reboot durability to
  a Live system whose `/priv` is in RAM.
  """
  @spec data_dir(atom()) :: Path.t()
  def data_dir(app) when is_atom(app) do
    name = Atom.to_string(app)

    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) do
      Path.join([os_priv(), "data", name])
    else
      raise ArgumentError, "invalid application name: #{inspect(app)}"
    end
  end

  @doc """
  Reapplies an installed app's recorded configuration and required state
  directories before a saved generation starts services or scheduler queues.
  The metadata also retains manual boot declarations; this step starts no
  service itself. Failure raises so boot cannot silently discard a policy.
  """
  @spec restore_app!(atom(), map()) :: :ok
  def restore_app!(app, metadata) do
    case prepare_app(app, metadata.persist, metadata.config) do
      :ok -> :ok
      {:error, {:persist_failed, path, reason}} ->
        raise File.Error, reason: reason, action: "create app data directory", path: path
      {:error, reason} ->
        raise ArgumentError, "cannot restore #{inspect(app)}: #{inspect(reason)}"
    end
  end

  defp prepare_app(app, paths, config) do
    with {:ok, _spec} <- Elixos.Package.Spec.from_project(elixos: [persist: paths]),
         :ok <- prepare_data_dir(app, paths) do
      for {configured_app, settings} <- config, {key, value} <- settings do
        # Application.load/1 must not replace the target config with defaults
        # from the .app resource when a service loads its application later.
        Application.put_env(configured_app, key, value, persistent: true)
      end

      :ok
    end
  end

  defp prepare_data_dir(app, paths) do
    root = data_dir(app)

    with :ok <- File.mkdir_p(os_priv()),
         :ok <- data_directory(Path.dirname(root)),
         :ok <- data_directory(root) do
      Enum.reduce_while(paths, :ok, fn path, :ok ->
        case make_relative_directories(root, Path.split(path)) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp make_relative_directories(_root, []), do: :ok
  defp make_relative_directories(root, ["." | rest]), do: make_relative_directories(root, rest)
  defp make_relative_directories(root, [name | rest]) do
    path = Path.join(root, name)
    with :ok <- data_directory(path), do: make_relative_directories(path, rest)
  end

  # mkdir, rather than mkdir_p, checks every existing component without
  # following an app-controlled symlink out of its data directory.
  defp data_directory(path) do
    case File.mkdir(path) do
      :ok -> :ok
      {:error, :eexist} ->
        case File.lstat(path) do
          {:ok, %{type: :directory}} -> :ok
          {:ok, _other} -> {:error, {:persist_failed, path, :enotdir}}
          {:error, reason} -> {:error, {:persist_failed, path, reason}}
        end
      {:error, reason} ->
        {:error, {:persist_failed, path, reason}}
    end
  end

  @doc """
  The version an installed package declares in its `.app`, or `nil` when it is
  not installed.
  """
  def installed_version(app) do
    app_file = Path.join([installed_dir(app), "ebin", "#{app}.app"])

    case app_version(app, app_file) do
      {:ok, version} -> version
      {:error, _reason} -> nil
    end
  end

  defp app_version(app, path) do
    case :file.consult(String.to_charlist(path)) do
      {:ok, [{:application, ^app, props}]} when is_list(props) ->
        with true <- Keyword.keyword?(props),
             version when is_list(version) or is_binary(version) <- props[:vsn],
             version = to_string(version),
             {:ok, _parsed} <- Version.parse(version) do
          {:ok, version}
        else
          _ -> {:error, :invalid_version}
        end

      {:ok, other} -> {:error, {:invalid_application, other}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, {:invalid_application, Exception.message(error)}}
  end

  defp installed_ebin(app), do: Path.join(installed_dir(app), "ebin")

  defp os_priv, do: Application.get_env(:elixos, :priv_dir, "/priv")

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
    case DynamicSupervisor.start_child(Elixos.Package.Services, child_spec(service)) do
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

  # A service is what the elixos: key wrote: a module, or a {module, arg}. A
  # dynamic supervisor wants exactly that - the module's own child_spec/1
  # (which `use GenServer` writes) carries the id and the restart policy.
  defp service_child({module, _arg}) when is_atom(module), do: true
  defp service_child(module) when is_atom(module), do: true
  defp service_child(_other), do: false

  defp child_spec(service), do: service

  defp record(app, version, spec, deps, config) do
    case Process.whereis(Elixos.Image) do
      nil -> {:error, :no_image}
      image -> Elixos.Image.record_app(image, app, version, spec, deps, config)
    end
  end

  defp installed_packages do
    case Process.whereis(Elixos.Image) do
      nil -> []
      image -> Elixos.Image.packages(image)
    end
  end

  defp os_version, do: to_string(Application.spec(:elixos, :vsn))

  defp atom_deps(deps),
    do: Map.new(deps, fn {name, requirement} -> {String.to_atom(name), requirement} end)

  defp factory, do: Application.get_env(:elixos, :factory_dir, "/factory")
  defp erlexec, do: Path.join([factory(), "erts", "bin", "erlexec"])
  defp mix_ebin, do: Path.join([factory(), "lib", "mix", "ebin"])
  # A build loads the release's modules but never starts another OS runtime.
  defp boot_script, do: Path.join([factory(), "releases", "current", "start_clean"])
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
  def add_repo(name, url, opts \\ []), do: Elixos.Package.Repo.add(name, url, opts)

  @doc "Removes a repository and its key. Installed packages stay installed."
  @spec remove_repo(atom()) :: :ok | {:error, term()}
  def remove_repo(name), do: Elixos.Package.Repo.remove(name)

  @doc "The trusted repositories, in configuration order."
  @spec repos() :: [Elixos.Package.Repo.t()]
  def repos, do: Elixos.Package.Repo.list()

  @doc """
  Packages whose name matches `query` (a string prefix or a `Regex`), across
  the trusted repositories. A static repository has no search API, so this
  matches against its names index.
  """
  @spec search(String.t() | Regex.t()) :: [
          %{name: String.t(), repo: atom(), versions: [String.t()]}
        ]
  def search(query) do
    for repo <- repos(),
        {:ok, names} <- [Elixos.Package.Hex.names(repo, query)],
        name <- names,
        {:ok, versions} <- [Elixos.Package.Hex.releases(repo, name)] do
      %{name: name, repo: repo.name, versions: versions}
    end
  end

  @doc """
  What is known about a package: its name, the repository it comes from, the
  versions available, and whether it is installed.
  """
  @spec info(String.t() | atom()) :: {:ok, map()} | {:error, term()}
  def info(name) do
    name = to_string(name)

    with {:ok, %{repo: repo, version: version}} <- Elixos.Package.Hex.resolve(name),
         {:ok, versions} <- Elixos.Package.Hex.releases(repo, name) do
      {:ok,
       %{
         name: name,
         repo: repo.name,
         version: version,
         versions: versions,
         installed: Map.has_key?(installed(), String.to_atom(name))
       }}
    end
  end

  @doc "Upgrades every installed package, or just `name`, to the newest release."
  @spec upgrade() :: %{atom() => {:ok, String.t()} | {:error, term()}}
  def upgrade do
    for {app, _version} <- installed(), into: %{} do
      {app, upgrade(app)}
    end
  end

  @spec upgrade(atom()) :: {:ok, String.t()} | {:error, term()}
  def upgrade(name) do
    string = to_string(name)

    with {:ok, %{version: version}} <- Elixos.Package.Hex.resolve(string) do
      if installed()[String.to_atom(string)] == version do
        {:ok, version}
      else
        with {:ok, _app} <- install(String.to_atom(string)), do: {:ok, version}
      end
    end
  end

  @doc "Uninstalls `name`: stops services, unloads modules and removes installed code; app data stays."
  @spec remove(atom()) :: :ok | {:error, term()}
  def remove(name) do
    case Process.whereis(Elixos.Image) do
      nil ->
        {:error, :no_image}

      image ->
        with {:ok, services} <- Elixos.Image.forget_app(image, name) do
          # The declaration leaves with the app; a scheduler that is not
          # running has nothing to remove.
          _ = Elixos.Oban.configure_app(name, [])
          stop_services(services)
          unload(name)
          _ = File.rm_rf(installed_dir(name))
          :ok
        end
    end
  end

  # The services this app started under the system tree, and only those: the
  # supervisor knows each child's modules, so the match is on the module.
  defp stop_services(services) do
    for service <- services, service_child(service) do
      module =
        case service do
          {module, _arg} when is_atom(module) -> module
          module when is_atom(module) -> module
          _other -> nil
        end

      for {_id, pid, _type, modules} <- Supervisor.which_children(Elixos.Package.Services),
          pid != :undefined,
          module != nil,
          module in modules do
        _ = DynamicSupervisor.terminate_child(Elixos.Package.Services, pid)
      end
    end

    :ok
  end

  # The app's files leave; so does the code they loaded: its directory comes
  # off the path and its modules are purged, so nothing half-installed stays
  # callable.
  defp unload(app) do
    ebin = installed_ebin(app)
    _ = :code.del_path(String.to_charlist(ebin))
    _ = Application.unload(app)
    prefix = String.to_charlist(ebin)

    for {module, path} <- :code.all_loaded(), is_list(path), List.starts_with?(path, prefix) do
      _ = :code.purge(module)
      _ = :code.delete(module)
    end

    :ok
  end
end
