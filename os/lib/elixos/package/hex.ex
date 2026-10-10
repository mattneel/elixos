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
  `contents.tar.gz`); `unpack/4` writes the contents into a directory after
  checking the tarball against the *signed* release: its SHA-256 must be the
  release's `outer_checksum`, and the `CHECKSUM` it carries must be the
  release's `inner_checksum`. The signature binds those values to the
  repository's key, so a tarball that is not the one the repository published
  cannot get in — and hex's inner checksum is over the tar as hex's own writer
  produced it, which is why it is taken from the signed registry rather than
  recomputed here.
  """

  alias Elixos.Package.{Proto, Repo}

  @doc "Names known to a repository, optionally matching `pattern`."
  @spec names(Repo.t(), String.t() | Regex.t() | nil) :: {:ok, [String.t()]} | {:error, term()}
  def names(%Repo{} = repo, pattern \\ nil) do
    with {:ok, payload} <- resource(repo, "names"),
         {:ok, message} <- Proto.decode(payload) do
      regex = pattern_regex(pattern)

      names =
        for entry <- Proto.all(message, 1),
            {:ok, package} <- [Proto.decode(entry)],
            name <- [Proto.one(package, 1)],
            is_binary(name),
            regex == nil or Regex.match?(regex, name),
            do: name

      {:ok, names}
    end
  end

  @doc "Every release of `name` in `repo`, newest first."
  @spec releases(Repo.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def releases(%Repo{} = repo, name) do
    with {:ok, payload} <- resource(repo, "versions"),
         {:ok, message} <- Proto.decode(payload) do
      versions =
        for entry <- Proto.all(message, 1),
            {:ok, package} <- [Proto.decode(entry)],
            Proto.one(package, 1) == name,
            version when is_binary(version) <- Proto.all(package, 2),
            do: version

      case versions do
        [] -> {:error, :no_such_package}
        list -> {:ok, Enum.sort(list, &(Version.compare(&1, &2) == :gt))}
      end
    end
  end

  @doc """
  Resolves `name` (with an optional `requirement`, `~> 1.0` style) among the
  trusted repositories. Two repositories offering the same name is
  `{:error, {:name_in_multiple_repos, name, repo_a, repo_b}}`.
  """
  @spec resolve(String.t(), String.t() | nil) ::
          {:ok, %{repo: Repo.t(), name: String.t(), version: String.t()}} | {:error, term()}
  def resolve(name, requirement \\ nil) do
    # ":elixos is not a package: a dependency on it is satisfied by the
    # running OS, and a package that bundles it is refused" (PROTOCOL.md §8).
    if name == "elixos" do
      {:error, :elixos_is_the_os}
    else
      resolve_among_repos(name, requirement)
    end
  end

  defp resolve_among_repos(name, requirement) do
    offering =
      for repo <- Repo.list(), {:ok, names} <- [names(repo, nil)], name in names, do: repo

    case offering do
      [] ->
        {:error, :no_such_package}

      [repo] ->
        with {:ok, versions} <- releases(repo, name),
             [version | _] <- matching(versions, requirement) do
          {:ok, %{repo: repo, name: name, version: version}}
        else
          [] -> {:error, {:no_matching_version, name, requirement}}
          {:error, reason} -> {:error, reason}
        end

      [repo_a, repo_b | _rest] ->
        {:error, {:name_in_multiple_repos, name, repo_a.name, repo_b.name}}
    end
  end

  @doc """
  Fetches and unpacks `name` `version` from `repo` into `dir`.

  `dir` is left holding the package's own files (no tarball wrapper): a Mix
  project, ready for `Elixos.Package.install/1`.
  """
  @spec unpack(Repo.t(), String.t(), String.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def unpack(%Repo{} = repo, name, version, dir) do
    with {:ok, release} <- release(repo, name, version),
         # The tarball is not a signed resource of its own: the signed release
         # pins it by checksum, which is what `check_outer/2` verifies.
         {:ok, tarball} <- fetch(repo, "tarballs/#{name}-#{version}.tar"),
         :ok <- check_outer(tarball, release.outer_checksum),
         {:ok, files} <- read_tarball(tarball, release.inner_checksum),
         :ok <- write_files(dir, files) do
      {:ok, dir}
    end
  end

  ## Reading a repository

  # A resource as served: bytes, verified against the repository's key, and
  # the payload behind the signature.
  defp resource(%Repo{} = repo, path) do
    with {:ok, bytes} <- fetch(repo, path) do
      Repo.verify(repo, bytes)
    end
  end

  defp fetch(%Repo{url: "http" <> _ = url}, path), do: http_get(url <> "/" <> path)

  defp fetch(%Repo{url: root}, path), do: File.read(Path.join(root, path))

  # The image has no HTTP client (no :inets in the release, M14 scope); a
  # mirror on the disk is what an offline box installs from. Where :inets
  # exists - the dev host, tests - an http(s) repository works.
  defp http_get(url) do
    with {:ok, _apps} <- Application.ensure_all_started(:inets) do
      # Through apply/3: the compiler is happy without :inets on its path, and
      # the call is the same one.
      case apply(:httpc, :request, [
             :get,
             {String.to_charlist(url), []},
             [],
             [body_format: :binary]
           ]) do
        {:ok, {{_version, 200, _reason}, _headers, body}} -> {:ok, body}
        other -> {:error, {:fetch_failed, other}}
      end
    else
      {:error, reason} -> {:error, {:fetch_failed, reason}}
    end
  end

  defp release(repo, name, version) do
    with {:ok, payload} <- resource(repo, "packages/#{name}"),
         {:ok, message} <- Proto.decode(payload),
         # The signature says *a* repository resource, not which one: the
         # message's own name field is what ties it to the package asked for,
         # so another same-version package cannot be served under this name.
         true <- Proto.one(message, 2) == name do
      releases =
        for entry <- Proto.all(message, 1),
            {:ok, release} <- [Proto.decode(entry)],
            Proto.one(release, 1) == version,
            do: release

      case releases do
        [release] ->
          {:ok,
           %{
             version: version,
             inner_checksum: Proto.one(release, 2),
             outer_checksum: Proto.one(release, 5),
             deps: deps_of(release)
           }}

        [] ->
          {:error, :no_such_release}
      end
    else
      false -> {:error, :package_mismatch}
      {:error, _reason} = error -> error
    end
  end

  # A release's requirements: name => requirement. Optional dependencies are
  # not required and are left out; a dependency on `:elixos` is kept, because
  # the resolver checks it against the running OS like any other.
  defp deps_of(release) do
    for entry <- Proto.all(release, 3),
        {:ok, dep} <- [Proto.decode(entry)],
        name when is_binary(name) <- [Proto.one(dep, 1)],
        Proto.one(dep, 3) != 1,
        requirement = Proto.one(dep, 2),
        is_binary(requirement),
        into: %{},
        do: {name, requirement}
  end

  @doc """
  The dependency closure of `name`: every release that has to be installed
  for it, each dependency before what requires it (ADR-015, M15).

  Releases carry their requirements - they are part of the signed registry -
  so the closure is read from the trusted resources: for every name the
  newest release satisfying *every* requirement seen for it. A requirement
  nothing satisfies is `{:error, {:no_matching_version, name, requirements}}`,
  and a name in two trusted repositories is `resolve/2`'s error.
  """
  @spec closure(String.t(), String.t() | nil) ::
          {:ok,
           [
             %{
               name: String.t(),
               version: String.t(),
               repo: Repo.t(),
               deps: %{String.t() => String.t()}
             }
           ]}
          | {:error, term()}
  def closure(name, requirement \\ nil) do
    requirements = if requirement, do: [requirement], else: []

    with {:ok, root} <- resolve_all(name, requirements),
         {:ok, picked} <- solve(%{name => %{repo: root.repo, requirements: requirements}}),
         {:ok, ordered} <- order(picked) do
      {:ok, ordered}
    end
  end

  # Fixpoint: pick every constrained name from the requirements seen so far,
  # read what the picked release requires, add those, repeat until a pass adds
  # nothing new.
  defp solve(constraints) do
    with {:ok, picked} <- pick_all(constraints) do
      {constraints, grown?} = add_requirements(constraints, picked)
      if grown?, do: solve(constraints), else: {:ok, picked}
    end
  end

  defp pick_all(constraints) do
    Enum.reduce_while(constraints, {:ok, %{}}, fn {name,
                                                   %{repo: repo, requirements: requirements}},
                                                  {:ok, acc} ->
      with {:ok, versions} <- releases(repo, name),
           [version | _] <- matching_all(versions, requirements),
           {:ok, release} <- release(repo, name, version) do
        {:cont,
         {:ok,
          Map.put(acc, name, %{name: name, version: version, repo: repo, deps: release.deps})}}
      else
        [] -> {:halt, {:error, {:no_matching_version, name, requirements}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp add_requirements(constraints, picked) do
    Enum.reduce(picked, {constraints, false}, fn {_name, entry}, {acc, grown?} ->
      Enum.reduce(entry.deps, {acc, grown?}, fn
        {"elixos", _requirement}, {acc, grown?} ->
          {acc, grown?}

        {dep, requirement}, {acc, grown?} ->
          merge_requirement(acc, dep, entry.repo, requirement, grown?)
      end)
    end)
  end

  defp merge_requirement(constraints, dep, repo, requirement, grown?) do
    case Map.fetch(constraints, dep) do
      :error ->
        {Map.put(constraints, dep, %{repo: repo, requirements: [requirement]}), true}

      {:ok, %{requirements: requirements}} ->
        if requirement in requirements do
          {constraints, grown?}
        else
          {Map.put(constraints, dep, %{repo: repo, requirements: requirements ++ [requirement]}),
           true}
        end
    end
  end

  defp matching_all(versions, requirements) do
    Enum.filter(versions, fn version ->
      Enum.all?(requirements, fn requirement ->
        case Version.parse_requirement(requirement) do
          {:ok, parsed} -> Version.match?(version, parsed, allow_pre: false)
          :error -> false
        end
      end)
    end)
  end

  # Dependencies first, deterministically: repeatedly take the names whose
  # dependencies are all placed, sorted. Anything left over is a cycle.
  defp order(picked) do
    graph = Map.new(picked, fn {name, entry} -> {name, Map.keys(entry.deps) -- ["elixos"]} end)

    case place(Map.keys(graph), graph, []) do
      {:ok, names} -> {:ok, Enum.map(names, &Map.fetch!(picked, &1))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp place([], _graph, acc), do: {:ok, Enum.reverse(acc)}

  defp place(remaining, graph, acc) do
    ready =
      remaining |> Enum.filter(fn name -> Enum.all?(graph[name], &(&1 in acc)) end) |> Enum.sort()

    if ready == [] do
      {:error, {:dependency_cycle, Enum.sort(remaining)}}
    else
      place(remaining -- ready, graph, Enum.reverse(ready) ++ acc)
    end
  end

  # Requirements-aware resolution: the one trusted repository, and the newest
  # release satisfying all of `requirements`.
  defp resolve_all(name, requirements) do
    offering =
      for repo <- Repo.list(), {:ok, names} <- [names(repo, nil)], name in names, do: repo

    case offering do
      [] ->
        {:error, :no_such_package}

      [repo] ->
        with {:ok, versions} <- releases(repo, name),
             [version | _] <- matching_all(versions, requirements) do
          {:ok, %{repo: repo, version: version}}
        else
          [] -> {:error, {:no_matching_version, name, requirements}}
          {:error, reason} -> {:error, reason}
        end

      [repo_a, repo_b | _rest] ->
        {:error, {:name_in_multiple_repos, name, repo_a.name, repo_b.name}}
    end
  end

  ## The tarball

  defp check_outer(tarball, expected) when is_binary(expected) do
    if :crypto.hash(:sha256, tarball) == expected do
      :ok
    else
      {:error, :bad_checksum}
    end
  end

  defp check_outer(_tarball, _expected), do: {:error, :bad_checksum}

  defp read_tarball(tarball, inner_checksum) do
    with {:ok, members} <- :erl_tar.extract({:binary, tarball}, [:memory]),
         members = Map.new(members, fn {name, bits} -> {to_string(name), bits} end),
         "3" <- members["VERSION"],
         checksum when is_binary(checksum) <- members["CHECKSUM"],
         contents when is_binary(contents) <- members["contents.tar.gz"],
         true <- decode_base16(checksum) == inner_checksum,
         {:ok, entries} <- :erl_tar.extract({:binary, :zlib.gunzip(contents)}, [:memory]) do
      {:ok, plain_files(entries)}
    else
      _other -> {:error, :bad_tarball}
    end
  end

  # The contents tar, as a list of files (its directory entries carry no
  # bytes of their own; `write_files/2` creates the directories).
  defp plain_files(entries) do
    for {name, bits} <- entries,
        not String.ends_with?(to_string(name), "/"),
        do: {to_string(name), bits}
  end

  # The package's own files, and nothing that could escape `dir`.
  defp write_files(dir, files) do
    # A fresh directory: a tarball must not land among files (or symlinks)
    # something else left there.
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    for {name, bits} <- files do
      case Path.safe_relative(name) do
        {:ok, relative} ->
          path = Path.join(dir, relative)

          with :ok <- File.mkdir_p(Path.dirname(path)),
               :ok <- File.write(path, bits) do
            :ok
          else
            {:error, reason} -> throw({:error, {:write_failed, name, reason}})
          end

        :error ->
          throw({:error, {:unsafe_path, name}})
      end
    end

    :ok
  catch
    {:error, reason} -> {:error, reason}
  end

  defp matching(versions, nil), do: versions

  defp matching(versions, requirement) do
    case Version.parse_requirement(requirement) do
      {:ok, parsed} -> Enum.filter(versions, &Version.match?(&1, parsed, allow_pre: false))
      :error -> []
    end
  end

  defp pattern_regex(nil), do: nil
  defp pattern_regex(%Regex{} = regex), do: regex
  defp pattern_regex(pattern) when is_binary(pattern), do: Regex.compile!(Regex.escape(pattern))

  defp decode_base16(hex) do
    case Base.decode16(String.upcase(hex)) do
      {:ok, bytes} -> bytes
      :error -> nil
    end
  end
end
