defmodule Elixos.Package do
  @moduledoc """
  Installing software onto the running system (M11 self-hosting, M14 by name).

  A **path** is installed as it stands: `install("/data/src/my_app")` builds the
  Mix project in place with `MIX_TARGET=elixos` (so its `config/elixos.exs`
  applies and `targets: :elixos` deps are included), resolves its dependencies
  system-wide (`Elixos.Package.Resolver`), loads it into the running VM, starts
  the services from its `elixos:` key (`Elixos.Package.Spec`), and records it in
  the image so the next `Elixos.save/1` includes it. NIFs compile with the
  bundled `zig cc` (ADR-009) against the running ERTS.

  A **name** is installed from the trusted Hex repositories (M14, ADR-019):

      iex> Elixos.Package.install(:hello_pkg)
      {:ok, :hello_pkg}

  The name is resolved among the repositories `/data/hex/repos.exs` lists —
  which is the entire trust decision, so an install never trusts a repository
  implicitly — the tarball is fetched, verified and unpacked into
  `/data/apps/<name>-<version>/`, and that directory goes through the same path
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
  def install(dir) when is_binary(dir),
    do: Elixos.NotImplemented.raise!(11, "Elixos.Package.install/1 #{dir}")

  def install(name) when is_atom(name),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.install/1 #{inspect(name)}")

  @doc "Installed apps and versions."
  @spec installed() :: %{atom() => String.t()}
  def installed, do: Elixos.NotImplemented.raise!(11, "Elixos.Package.installed/0")

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
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.add_repo/3 #{inspect({name, url, opts})}")

  @doc "Removes a repository and its key. Installed packages stay installed."
  @spec remove_repo(atom()) :: :ok | {:error, term()}
  def remove_repo(name), do: Elixos.NotImplemented.raise!(14, "Elixos.Package.remove_repo/1 #{inspect(name)}")

  @doc "The trusted repositories, in configuration order."
  @spec repos() :: [Elixos.Package.Repo.t()]
  def repos, do: Elixos.NotImplemented.raise!(14, "Elixos.Package.repos/0")

  @doc """
  Packages whose name matches `query` (a string prefix or a `Regex`), across
  the trusted repositories. A static repository has no search API, so this
  matches against its names index.
  """
  @spec search(String.t() | Regex.t()) :: [%{name: String.t(), repo: atom(), versions: [String.t()]}]
  def search(query), do: Elixos.NotImplemented.raise!(14, "Elixos.Package.search/1 #{inspect(query)}")

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
  def upgrade(name), do: Elixos.NotImplemented.raise!(14, "Elixos.Package.upgrade/1 #{inspect(name)}")

  @doc "Uninstalls `name`: its services stop, its modules unload, its files go."
  @spec remove(atom()) :: :ok | {:error, term()}
  def remove(name), do: Elixos.NotImplemented.raise!(14, "Elixos.Package.remove/1 #{inspect(name)}")
end
