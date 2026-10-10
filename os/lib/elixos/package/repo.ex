defmodule Elixos.Package.Repo do
  @moduledoc """
  Trusted Hex repositories: the configuration and the consent (ADR-019, M14).

  `/data/hex/repos.exs` is the whole trust decision: a repository is trusted
  exactly when it appears there, with its public key. An install can therefore
  never trust a repository implicitly — adding it is the consent step, and on a
  single-user machine (ADR-013) that is the only one there is.

      iex> pem = File.read!("/data/hex/keys/team.pub")
      iex> Elixos.Package.add_repo("team", "/data/mirrors/team", key: pem)
      :ok
      iex> Elixos.Package.repos()
      [%Elixos.Package.Repo{name: :team, url: "/data/mirrors/team"}]

  A repository is a static Hex repository (`mix hex.registry build`): `names`,
  `versions`, `packages/<name>` and `tarballs/<name>-<version>.tar`, each
  resource signed, and `public_key` serving the key above. `url` is `http(s)://`
  or a local path (PROTOCOL.md §8, Q8).

  The same key is written to `/data/hex/keys/<name>.pub`, so trust survives a
  power cycle and can be inspected by hand. Both files are written atomically.
  """

  defstruct [:name, :url, :key]

  @type t :: %__MODULE__{name: atom(), url: String.t(), key: String.t()}

  @type name :: atom()

  @doc "Every trusted repository, in the order they are configured."
  @spec list() :: [t()]
  def list, do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Repo.list/0")

  @doc "One repository, or `{:error, :unknown_repo}`."
  @spec get(name()) :: {:ok, t()} | {:error, :unknown_repo}
  def get(name), do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Repo.get/1 #{inspect(name)}")

  @doc """
  Adds `name` with `url` and its public key (`key:`, PEM), or refuses it.

  The key is used as given: `Repo` never fetches one from `url` on its own. A
  wrong key (not PEM, not RSA) is `{:error, :bad_key}`; an existing name is
  replaced only by `replace: true`.
  """
  @spec add(name(), String.t(), keyword()) :: :ok | {:error, term()}
  def add(name, url, opts \\ []),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Repo.add/3 #{inspect({name, url, opts})}")

  @doc "Removes `name` and its key file."
  @spec remove(name()) :: :ok | {:error, :unknown_repo}
  def remove(name), do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Repo.remove/1 #{inspect(name)}")

  @doc "Whether `name` is configured (and therefore trusted)."
  @spec trusted?(name()) :: boolean()
  def trusted?(name), do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Repo.trusted?/1 #{inspect(name)}")

  @doc "The key file for `name` (`/data/hex/keys/<name>.pub`)."
  @spec key_path(name()) :: Path.t()
  def key_path(name), do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Repo.key_path/1 #{inspect(name)}")

  @doc """
  Verifies that `resource` (the bytes a repository served) is signed by
  `repo`'s key. Hex resources carry their signature; nothing is installed from
  a resource that does not verify.
  """
  @spec verify(t(), binary()) :: {:ok, binary()} | {:error, :bad_signature}
  def verify(%__MODULE__{} = repo, resource),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Repo.verify/2 #{inspect(repo.name)}")
end
