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

    if File.regular?(Path.join(root, "mix.exs")) do
      install_project(root, %{})
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
    case Elixos.Package.Resolver.plan(
           installed_packages(),
           closure_packages(closure),
           os_version()
         ) do
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
    Enum.each(closure, fn entry ->
      dir = Path.join([os_priv(), "apps", "#{entry.name}-#{entry.version}"])

      case Elixos.Package.Hex.unpack(entry.repo, entry.name, entry.version, dir) do
        {:ok, ^dir} ->
          case install_project_or_payload(dir, atom_deps(entry.deps)) do
            {:ok, _app} -> :ok
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

  defp install_project_or_payload(dir, deps) do
    if File.regular?(Path.join(dir, "mix.exs")) do
      install_project(dir, deps)
    else
      install_payload(dir, deps)
    end
  end

  defp install_project(root, deps) do
    with {:ok, spec} <- spec(root),
         {:ok, app, version, ebin} <- build(root),
         :ok <- apply_config(root),
         :ok <- install_tree(app, ebin, root),
         :ok <- load(app, installed_ebin(app)),
         :ok <- start_services(spec.services),
         :ok <- record(app, version, spec, deps) do
      {:ok, app}
    end
  end

  # A package without a Mix project is a *payload*: the toolchain (ADR-009) is
  # the only one, and it is taken where it lies (the disk's /priv/toolchain is
  # 421M; copying it would be waste) and recorded, so it is part of the image
  # like any package.
  defp install_payload(root, deps \\ %{}) do
    name = root |> Path.basename() |> String.to_atom()

    with :ok <- record(name, payload_version(root), %Elixos.Package.Spec{}, deps) do
      {:ok, name}
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
    # A failure makes the eval fail, which ends the child non-zero on its own;
    # a success has to say so, or the release's boot leaves the child running
    # as a daemon and System.cmd waits forever.
    code = ~s|'Elixir.Mix.CLI':main([<<"compile">>, <<"--no-deps-check">>]), erlang:halt(0)|

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

  # The build dir names both: _build/elixos_prod/lib/<app>-<version>/ebin.
  defp app_of(ebin) do
    ebin |> Path.dirname() |> Path.basename() |> String.split("-") |> hd() |> String.to_atom()
  end

  defp version_of(ebin) do
    ebin |> Path.dirname() |> Path.basename() |> String.split("-") |> List.last()
  end

  # The app's own config/*.exs is its settings (ADR-010): read it the way mix
  # does - env and target set - and put every value into this VM, so the app
  # behaves as built. Case 1's SampleApp.where() is exactly this.
  defp apply_config(root) do
    path = Path.join(root, "config/config.exs")

    if File.regular?(path) do
      for {app, settings} <- Config.Reader.read!(path, env: :prod, target: :elixos),
          {key, value} <- settings do
        Application.put_env(app, key, value)
      end
    end

    :ok
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
    File.cp_r!(Path.dirname(ebin), dest)

    # Mix links a project's priv into the build dir when the build starts; a
    # compiler that creates priv while compiling (the NIF fixture does) is
    # later than that, so the project's priv is what ebin loads from at run
    # time. Copy it beside ebin.
    priv = Path.join(root, "priv")
    if File.dir?(priv), do: File.cp_r!(priv, Path.join(dest, "priv"))

    :ok
  end

  # Where an installed app lives on the disk: its whole build dir (ebin and
  # priv) under /priv/apps (PROTOCOL.md §7).
  defp installed_dir(app), do: Path.join([os_priv(), "apps", Atom.to_string(app)])

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

  defp record(app, version, spec, deps) do
    case Process.whereis(Elixos.Image) do
      nil -> {:error, :no_image}
      image -> Elixos.Image.record_app(image, app, version, spec.services, deps)
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

  @doc "Uninstalls `name`: its services stop, its modules unload, its files go."
  @spec remove(atom()) :: :ok | {:error, term()}
  def remove(name) do
    case Process.whereis(Elixos.Image) do
      nil ->
        {:error, :no_image}

      image ->
        with {:ok, services} <- Elixos.Image.forget_app(image, name) do
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
