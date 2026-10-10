defmodule Elixos.Package.Hex do
  @moduledoc """
  The Hex wire format, read from a trusted repository (ADR-019, M14).

  A static Hex repository (built with `mix hex.registry build`) serves:

    * `names` — the names index: every package name and its repository, signed
    * `versions` — every name and version ever published, signed
    * `packages/<name>` — the releases of one package, signed
    * `tarballs/<name>-<version>.tar` — the package itself
    * `public_key` — the RSA key the resources are verified against

  Everything here is verified against the repository's key (`Elixos.Package.Repo`)
  before it is used, and nothing is fetched from a repository that is not
  trusted. A static repository has no search API, so a query is matched against
  the names index.

  The tarball is Hex's own layout (`VERSION`, `CHECKSUM`, `metadata.config`,
  `contents.tar.gz`); `unpack/2` writes the contents into a directory and
  verifies the checksum, because from there the directory is just a Mix project
  for the M11 install path.
  """

  @doc "Names known to a repository, optionally matching `~r/pattern/`."
  @spec names(Elixos.Package.Repo.t(), Regex.t() | nil) :: {:ok, [String.t()]} | {:error, term()}
  def names(%Elixos.Package.Repo{} = repo, pattern \\ nil),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Hex.names/2 #{inspect({repo.name, pattern})}")

  @doc "Every release of `name` in `repo`, newest first."
  @spec releases(Elixos.Package.Repo.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def releases(%Elixos.Package.Repo{} = repo, name),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Hex.releases/2 #{inspect({repo.name, name})}")

  @doc """
  Resolves `name` (with an optional `requirement`, `~> 1.0` style) among the
  trusted repositories. Two repositories offering the same name is
  `{:error, {:name_in_multiple_repos, name, repo_a, repo_b}}`.
  """
  @spec resolve(String.t(), String.t() | nil) ::
          {:ok, %{repo: Elixos.Package.Repo.t(), name: String.t(), version: String.t()}}
          | {:error, term()}
  def resolve(name, requirement \\ nil),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Hex.resolve/2 #{inspect({name, requirement})}")

  @doc """
  Fetches and unpacks `name` `version` from `repo` into `dir`.

  `dir` is left holding the package's own files (no tarball wrapper): a Mix
  project, ready for `Elixos.Package.install/1`.
  """
  @spec unpack(Elixos.Package.Repo.t(), String.t(), String.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def unpack(%Elixos.Package.Repo{} = repo, name, version, dir),
    do: Elixos.NotImplemented.raise!(14, "Elixos.Package.Hex.unpack/4 #{inspect({repo.name, name, version, dir})}")
end
