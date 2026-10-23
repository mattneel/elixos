defmodule Elixos.Container.Image do
  @moduledoc """
  Exports a committed native container generation as an immutable deployment seed.

  Call `export/1` after a normal container reboot, the real health check and
  `Elixos.commit/0`. The shim remains the only writer of `boot.state`: this API
  waits at most two seconds for an asynchronous COMMIT, then copies its original
  bytes to `.container.boot.state`, published after every other seed file.

  Only the running generation, its verified module blobs, canonical installed
  `ebin`/`priv`/`include` trees and explicitly configured public repository trust
  are exported. The ordinary journal is compacted through `Elixos.Image.Journal`
  to deployment metadata; agent state, history, workspaces, caches, user data,
  PostgreSQL and SSH identities are not captured. Generations requiring agents
  or boot actions outside ordinary package preparation/services are refused.

  The destination must be a new directory with an existing, unlinked parent.
  A destination inside the persistent root must be a separate direct child, not
  an OS state directory. Files are read-only;
  executable resources retain execution permission. The exporting BEAM owns the
  result. The final OCI build must use `COPY --chown=0:0` so the shim can trust
  the seed. A failed export never publishes a usable boot-state marker and may
  leave an incomplete destination for its caller to remove.
  """

  alias Elixos.Boot.Env
  alias Elixos.Image
  alias Elixos.Image.{Generation, Journal, Store}
  alias Elixos.Package
  alias Elixos.Package.{Repo, Spec}

  @commit_wait_ms 2_000
  @commit_poll_ms 25
  @chunk_size 65_536
  @state_keys %{"current" => :current, "last_good" => :last_good, "attempts" => :attempts}
  @reserved ~w(apps data generations store hex home postgres ssh cache crash evidence toolchain system run tmp lost+found)
  @private_key ~r/-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----/

  @doc "Exports the actual saved running generation, returning its number and installed app versions."
  @spec export(Path.t()) :: {:ok, %{generation: pos_integer(), apps: map()}} | {:error, term()}
  def export(destination) when is_binary(destination) do
    root = Application.get_env(:elixos, :priv_dir, "/priv") |> Path.expand()

    with {:ok, env} <- launch(),
         {:ok, image} <- running_image(),
         {:ok, state_bytes} <- committed_state(root, env.generation),
         {:ok, snapshot} <- snapshot(root, image, env.generation),
         {:ok, destination} <- destination(destination, root),
         :ok <- create_destination(destination),
         :ok <- write_seed(destination, root, snapshot),
         :ok <- unchanged(root, image, snapshot, state_bytes),
         :ok <- seal_directories(destination, false),
         :ok <- publish_state(destination, state_bytes) do
      {:ok, %{generation: env.generation, apps: versions(snapshot.apps)}}
    end
  catch
    :exit, reason -> {:error, {:image_unavailable, reason}}
  end

  def export(_destination), do: {:error, :invalid_destination}

  defp launch do
    environment = System.get_env()

    with {:ok, runtime} <- Env.runtime(environment),
         true <- runtime == :container || {:error, :not_container},
         {:ok, %Env{} = env} <- Env.parse(environment),
         true <- env.mode == :normal || {:error, :not_normal_boot},
         true <- env.generation > 0 || {:error, :factory_generation} do
      {:ok, env}
    else
      {:error, {kind, name}} when kind in [:missing, :invalid] ->
        {:error, {:launch_contract, {kind, name}}}

      {:error, _reason} = error ->
        error
    end
  end

  defp running_image do
    case Process.whereis(Image) do
      nil -> {:error, :no_image}
      image -> {:ok, image}
    end
  end

  defp committed_state(root, generation) do
    deadline = System.monotonic_time(:millisecond) + @commit_wait_ms
    await_commit(Path.join(root, "boot.state"), generation, deadline)
  end

  defp await_commit(path, generation, deadline) do
    with {:ok, bytes} <- read_artifact(path),
         {:ok, state} <- parse_state(bytes) do
      cond do
        state.current != generation ->
          {:error, {:running_generation_mismatch, generation, state.current}}

        state.last_good == generation and state.attempts == 0 ->
          {:ok, bytes}

        System.monotonic_time(:millisecond) >= deadline ->
          {:error, {:uncommitted_generation, generation, state}}

        true ->
          Process.sleep(@commit_poll_ms)
          await_commit(path, generation, deadline)
      end
    end
  end

  # Match shim/src/statefile.zig's grammar; Elixos.Decimal is the shared u32
  # parser. Preserve the input bytes rather than re-encoding shim-owned state.
  defp parse_state(bytes) do
    body = String.replace_suffix(bytes, "\n", "")
    lines = if body == "", do: [], else: String.split(body, "\n")

    result =
      Enum.reduce_while(lines, {:ok, %{}}, fn line, {:ok, state} ->
        case String.split(line, "=", parts: 2) do
          [key, value] when key != "" ->
            cond do
              not Map.has_key?(@state_keys, key) ->
                {:halt, {:error, :unknown_key}}

              Map.has_key?(state, @state_keys[key]) ->
                {:halt, {:error, :duplicate_key}}

              true ->
                case Elixos.Decimal.parse_u32(value) do
                  {:ok, number} -> {:cont, {:ok, Map.put(state, @state_keys[key], number)}}
                  :error -> {:halt, {:error, :bad_value}}
                end
            end

          _other ->
            {:halt, {:error, :bad_line}}
        end
      end)

    case result do
      {:ok, state} when map_size(state) == 3 -> {:ok, state}
      {:ok, _state} -> {:error, {:boot_state, :missing_key}}
      {:error, reason} -> {:error, {:boot_state, reason}}
    end
  end

  defp snapshot(root, image, number) do
    path = Generation.path(Path.join(root, "generations"), number)
    journal_path = Path.join(root, "journal.log")

    with :ok <- generation_file(path, number),
         {:ok, generation_bytes} <- read_artifact(path),
         {:ok, %Generation{number: ^number} = generation} <- read_generation(root, number),
         true <-
           (is_map(generation.modules) and is_list(generation.boot)) ||
             {:error, {:generation, number, :corrupt}},
         {:ok, journal_bytes} <- read_artifact(journal_path),
         {:ok, entries} <- read_journal(journal_path),
         {:ok, saved_entries} <- saved_entries(entries, number),
         apps = GenServer.call(image, :apps),
         true <- apps == saved_apps(saved_entries) || {:error, :unsaved_apps},
         true <- Image.modules(image) == generation.modules || {:error, :unsaved_modules},
         true <-
           (Image.agents(image) == %{} and saved_agents(saved_entries) == %{}) ||
             {:error, :agent_state_not_exportable},
         :ok <- validate_apps(apps),
         :ok <- validate_boot(generation.boot, apps),
         {:ok, repositories} <- repositories(root) do
      {:ok,
       %{
         generation: generation,
         generation_bytes: generation_bytes,
         journal_bytes: journal_bytes,
         apps: apps,
         repositories: repositories
       }}
    else
      {:ok, _other} -> {:error, {:generation, number, :corrupt}}
      {:error, _reason} = error -> error
    end
  end

  defp generation_file(path, number) do
    case artifact(path, :regular) do
      {:ok, _stat} -> :ok
      {:error, {:artifact, _missing, :enoent}} -> {:error, {:generation, number, :not_found}}
      {:error, _reason} = error -> error
    end
  end

  defp read_generation(root, number) do
    case Generation.read(Path.join(root, "generations"), number) do
      {:ok, generation} -> {:ok, generation}
      {:error, reason} -> {:error, {:generation, number, reason}}
    end
  end

  defp read_journal(path) do
    case Journal.read(path) do
      {:ok, entries, :clean} -> {:ok, entries}
      {:ok, _entries, :torn} -> {:error, {:journal, :torn}}
      {:error, reason} -> {:error, {:journal, reason}}
    end
  end

  defp saved_entries(entries, number) do
    case Enum.split_while(entries, fn {_seq, entry} -> entry != {:generation, number} end) do
      {_before, []} -> {:error, {:generation_not_journaled, number}}
      {before, _rest} -> {:ok, before}
    end
  end

  # Use the Image journal's record migration defaults, including the historical
  # tuples it still accepts. Compare effective metadata, not the mere existence
  # of post-save records (normal preparation may repeat an identical install).
  defp saved_apps(entries) do
    defaults = Map.merge(Map.from_struct(%Spec{}), %{version: nil, deps: %{}, config: []})

    Enum.reduce(entries, %{}, fn {_seq, entry}, apps ->
      case entry do
        {:app, app, metadata} when is_map(metadata) ->
          Map.put(apps, app, Map.merge(defaults, metadata))

        {:app, app, version, services, deps, oban} ->
          Map.put(
            apps,
            app,
            Map.merge(defaults, %{version: version, services: services, deps: deps, oban: oban})
          )

        {:app, app, version, services} ->
          Map.put(apps, app, Map.merge(defaults, %{version: version, services: services}))

        {:uninstall, app} ->
          Map.delete(apps, app)

        {:app_deps, app, deps} ->
          if Map.has_key?(apps, app),
            do: Map.update!(apps, app, &Map.put(&1, :deps, deps)),
            else: apps

        _other ->
          apps
      end
    end)
  end

  defp saved_agents(entries) do
    Enum.reduce(entries, %{}, fn {_seq, entry}, agents ->
      case entry do
        {:agent, id, module, opts} -> Map.put(agents, id, {module, opts})
        {:agent_removed, id} -> Map.delete(agents, id)
        _other -> agents
      end
    end)
  end

  defp validate_apps(apps) do
    each(Enum.sort(apps), fn {app, metadata} ->
      cond do
        not is_atom(app) or not Regex.match?(~r/^[a-z][a-z0-9_]*$/, Atom.to_string(app)) ->
          {:error, {:invalid_installed_app, app}}

        private_term?(metadata) ->
          {:error, {:private_package_metadata, app}}

        true ->
          path = Path.join(Package.installed_dir(app), "ebin/#{app}.app")

          with {:ok, _stat} <- artifact(path, :regular) do
            case Package.installed_version(app) do
              version when is_binary(version) and version == metadata.version -> :ok
              actual -> {:error, {:installed_version_mismatch, app, metadata.version, actual}}
            end
          end
      end
    end)
  end

  defp validate_boot(boot, apps) do
    each(boot, fn entry ->
      allowed? =
        case entry do
          {Package, :restore_app!, [app, metadata]} ->
            Map.fetch(apps, app) == {:ok, metadata}

          {Package, :start_service, [service]} ->
            Enum.any?(apps, fn {_app, metadata} ->
              metadata.boot == :auto and service in metadata.services
            end)

          {Elixos.Oban, :configure_app!, [app, declaration]} ->
            case Map.get(apps, app) do
              %{boot: :auto, oban: ^declaration} -> true
              _other -> false
            end

          _other ->
            false
        end

      if allowed?, do: :ok, else: {:error, {:non_deployable_boot_entry, entry}}
    end)
  end

  defp destination(path, root) do
    expanded = Path.expand(path)
    inside? = expanded == root or String.starts_with?(expanded, root <> "/")

    cond do
      path == "" or String.contains?(path, <<0>>) or ".." in Path.split(path) ->
        {:error, {:unsafe_destination, path}}

      inside? and
          (Path.dirname(expanded) != root or Path.basename(expanded) in @reserved or
             String.starts_with?(Path.basename(expanded), ".")) ->
        {:error, {:unsafe_destination, path}}

      String.starts_with?(root, expanded <> "/") ->
        {:error, {:unsafe_destination, path}}

      true ->
        with {:ok, _stat} <- artifact(Path.dirname(expanded), :directory) do
          case File.lstat(expanded) do
            {:error, :enoent} -> {:ok, expanded}
            {:ok, _stat} -> {:error, {:destination_exists, expanded}}
            {:error, reason} -> {:error, {:artifact, expanded, reason}}
          end
        end
    end
  end

  defp create_destination(path) do
    with :ok <- file_result(File.mkdir(path), path),
         :ok <- file_result(File.chmod(path, 0o700), path),
         do: :ok
  end

  defp write_seed(destination, root, snapshot) do
    generation = snapshot.generation

    with :ok <- directory(Path.join(destination, "apps")),
         :ok <- directory(Path.join(destination, "store")),
         :ok <-
           each(Enum.sort(snapshot.apps), fn {app, _metadata} ->
             copy_app(Package.installed_dir(app), Path.join(destination, "apps/#{app}"))
           end),
         :ok <-
           each(generation.modules |> Map.values() |> Enum.uniq() |> Enum.sort(), fn hash ->
             copy_blob(root, destination, hash)
           end),
         :ok <-
           write_artifact(
             Generation.path(Path.join(destination, "generations"), generation.number),
             snapshot.generation_bytes
           ),
         :ok <- write_journal(Path.join(destination, "journal.log"), generation, snapshot.apps),
         :ok <- write_repositories(destination, snapshot.repositories) do
      :ok
    end
  end

  defp copy_app(source, destination) do
    with {:ok, _stat} <- artifact(source, :directory),
         :ok <- directory(destination),
         :ok <- copy_tree(Path.join(source, "ebin"), Path.join(destination, "ebin"), :ebin) do
      each(["priv", "include"], fn name ->
        path = Path.join(source, name)

        case File.lstat(path) do
          {:error, :enoent} -> :ok
          _other -> copy_tree(path, Path.join(destination, name), :resource)
        end
      end)
    end
  end

  defp copy_tree(source, destination, kind) do
    with {:ok, stat} <- artifact(source),
         true <- not private_name?(Path.basename(source)) || {:error, {:private_artifact, source}} do
      case stat.type do
        :directory ->
          with :ok <- directory(destination),
               {:ok, entries} <- list_artifact(source) do
            each(Enum.sort(entries), fn name ->
              if kind == :ebin and Path.extname(name) not in [".app", ".beam"] do
                {:error, {:non_runtime_artifact, Path.join(source, name)}}
              else
                copy_tree(Path.join(source, name), Path.join(destination, name), kind)
              end
            end)
          end

        :regular ->
          copy_artifact(source, destination, stat)
      end
    else
      {:error, _reason} = error -> error
    end
  end

  defp copy_blob(root, destination, hash) do
    store = %Store{root: Path.join(root, "store")}

    with {:ok, source} <- blob_path(store, hash),
         {:ok, _stat} <- artifact(source, :regular) do
      case Store.get(store, hash) do
        {:ok, bytes} ->
          target = Store.path_for(%Store{root: Path.join(destination, "store")}, hash)
          write_artifact(target, bytes)

        {:error, reason} ->
          {:error, {:blob, hash, reason}}
      end
    end
  end

  defp blob_path(store, hash) do
    {:ok, Store.path_for(store, hash)}
  rescue
    ArgumentError -> {:error, {:blob, hash, :invalid_hash}}
  end

  defp write_journal(path, generation, apps) do
    entries =
      Enum.map(Enum.sort(generation.modules), fn {module, hash} -> {:module, module, hash} end) ++
        Enum.map(Enum.sort(apps), fn {app, metadata} -> {:app, app, metadata} end) ++
        [{:generation, generation.number}]

    with {:ok, journal} <- Journal.open(path) do
      result =
        try do
          each(entries, fn entry ->
            case Journal.append(journal, entry) do
              {:ok, _seq} -> :ok
              {:error, reason} -> {:error, {:artifact, path, reason}}
            end
          end)
        after
          Journal.close(journal)
        end

      with :ok <- result, do: seal_file(path, 0o444)
    end
  end

  defp repositories(root) do
    hex = Application.get_env(:elixos, :hex_dir, Path.join(root, "hex")) |> Path.expand()
    path = Path.join(hex, "repos.exs")

    case File.lstat(hex) do
      {:error, :enoent} ->
        {:ok, nil}

      _other ->
        with {:ok, _stat} <- artifact(hex, :directory) do
          case File.lstat(path) do
            {:error, :enoent} ->
              {:ok, nil}

            _other ->
              with {:ok, bytes} <- read_artifact(path),
                   {:ok, pairs} <- repository_pairs(bytes),
                   :ok <- each(pairs, fn {name, opts} -> validate_repository(name, opts, hex) end) do
                {:ok, %{path: path, bytes: bytes, pairs: pairs}}
              end
          end
        end
    end
  end

  # Repo.add/3 writes a literal keyword list. Never export/evaluate arbitrary
  # executable repos.exs source or accept Repo.list/0's log-and-empty fallback.
  defp repository_pairs(bytes) do
    with {:ok, pairs} <- Code.string_to_quoted(bytes),
         true <- Keyword.keyword?(pairs),
         true <- length(Keyword.keys(pairs)) == length(Enum.uniq(Keyword.keys(pairs))),
         true <-
           Enum.all?(pairs, fn {name, opts} ->
             Regex.match?(~r/^[a-z][a-z0-9_-]*$/, Atom.to_string(name)) and Keyword.keyword?(opts) and
               Enum.sort(Keyword.keys(opts)) == [:key, :url] and is_binary(opts[:key]) and
               is_binary(opts[:url])
           end) do
      {:ok, pairs}
    else
      _other -> {:error, {:repositories, :malformed}}
    end
  end

  defp validate_repository(name, opts, hex) do
    with {:ok, _key} <- public_key(opts[:key], name),
         {:ok, key_bytes} <- read_artifact(Repo.key_path(name)),
         true <- key_bytes == opts[:key] || {:error, {:repository, name, :key_mismatch}},
         :ok <- public_url(name, opts[:url], hex) do
      :ok
    end
  end

  defp public_key(bytes, name) do
    case :public_key.pem_decode(bytes) do
      [entry = {type, _der, :not_encrypted}]
      when type in [:RSAPublicKey, :SubjectPublicKeyInfo] ->
        case :public_key.pem_entry_decode(entry) do
          {:RSAPublicKey, modulus, exponent} = key when modulus > 0 and exponent > 0 -> {:ok, key}
          _other -> {:error, {:repository, name, :bad_public_key}}
        end

      _other ->
        {:error, {:repository, name, :bad_public_key}}
    end
  rescue
    _error -> {:error, {:repository, name, :bad_public_key}}
  end

  defp public_url(name, url, hex) do
    uri = URI.parse(url)
    mirror = Path.join([hex, "mirrors", Atom.to_string(name)])

    cond do
      uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
        uri.userinfo == nil and uri.query == nil and uri.fragment == nil ->
        :ok

      url == mirror ->
        :ok

      true ->
        {:error, {:repository, name, :non_public_url}}
    end
  end

  defp write_repositories(_destination, nil), do: :ok

  defp write_repositories(destination, repositories) do
    hex = Path.join(destination, "hex")
    pairs = repositories.pairs

    with :ok <-
           write_artifact(
             Path.join(hex, "repos.exs"),
             inspect(pairs, limit: :infinity, printable_limit: :infinity) <> "\n"
           ) do
      each(pairs, fn {name, opts} ->
        with :ok <- write_artifact(Path.join(hex, "keys/#{name}.pub"), opts[:key]) do
          if URI.parse(opts[:url]).scheme in ["http", "https"] do
            :ok
          else
            repo = %Repo{name: name, url: opts[:url], key: opts[:key]}
            copy_mirror(repo, Path.join(hex, "mirrors/#{name}"))
          end
        end
      end)
    end
  end

  defp copy_mirror(repo, destination) do
    with {:ok, _stat} <- artifact(repo.url, :directory),
         {:ok, public_bytes} <- read_artifact(Path.join(repo.url, "public_key")),
         {:ok, expected_key} <- public_key(repo.key, repo.name),
         {:ok, actual_key} <- public_key(public_bytes, repo.name),
         true <- expected_key == actual_key || {:error, {:repository, repo.name, :key_mismatch}},
         :ok <- write_artifact(Path.join(destination, "public_key"), public_bytes),
         :ok <-
           each(["names", "versions"], fn name ->
             copy_signed(repo, name, Path.join(destination, name))
           end) do
      each(["packages", "tarballs"], fn kind ->
        source = Path.join(repo.url, kind)

        with {:ok, _stat} <- artifact(source, :directory),
             {:ok, entries} <- list_artifact(source),
             :ok <- directory(Path.join(destination, kind)) do
          each(Enum.sort(entries), fn name ->
            relative = kind <> "/" <> name
            target = Path.join(destination, relative)

            cond do
              kind == "packages" and Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) ->
                copy_signed(repo, relative, target)

              kind == "tarballs" and
                  Regex.match?(~r/^[a-z][a-z0-9_]*-[0-9][0-9A-Za-z.+_-]*\.tar$/, name) ->
                path = Path.join(repo.url, relative)

                with {:ok, stat} <- artifact(path, :regular),
                     do: copy_artifact(path, target, stat)

              true ->
                {:error, {:repository, repo.name, {:invalid_resource, relative}}}
            end
          end)
        end
      end)
    end
  end

  defp copy_signed(repo, relative, destination) do
    with {:ok, bytes} <- read_artifact(Path.join(repo.url, relative)),
         :ok <- verify_resource(repo, relative, bytes),
         do: write_artifact(destination, bytes)
  end

  defp verify_resource(repo, relative, bytes) do
    case Repo.verify(repo, bytes) do
      {:ok, _payload} ->
        :ok

      {:error, reason} ->
        {:error, {:repository, repo.name, {:invalid_resource, relative, reason}}}
    end
  rescue
    _error -> {:error, {:repository, repo.name, {:invalid_resource, relative, :bad_signature}}}
  end

  defp unchanged(root, image, snapshot, state_bytes) do
    generation_path = Generation.path(Path.join(root, "generations"), snapshot.generation.number)

    with :ok <- same_bytes(Path.join(root, "boot.state"), state_bytes),
         :ok <- same_bytes(generation_path, snapshot.generation_bytes),
         :ok <- same_bytes(Path.join(root, "journal.log"), snapshot.journal_bytes),
         true <-
           (GenServer.call(image, :apps) == snapshot.apps and
              Image.modules(image) == snapshot.generation.modules and Image.agents(image) == %{}) ||
             {:error, :image_changed_during_export} do
      case snapshot.repositories do
        nil ->
          case repositories(root) do
            {:ok, nil} -> :ok
            {:ok, _new_repositories} -> {:error, :repositories_changed_during_export}
            {:error, _reason} = error -> error
          end

        repositories ->
          same_bytes(repositories.path, repositories.bytes)
      end
    end
  end

  defp same_bytes(path, expected) do
    with {:ok, actual} <- read_artifact(path) do
      if actual == expected, do: :ok, else: {:error, {:artifact_changed_during_export, path}}
    end
  end

  defp publish_state(destination, bytes) do
    path = Path.join(destination, ".container.boot.state")
    temporary = path <> ".tmp"

    with :ok <- write_artifact(temporary, bytes),
         :ok <- file_result(File.rename(temporary, path), path),
         :ok <- file_result(File.chmod(destination, 0o555), destination),
         :ok <- sync_directory(destination) do
      :ok
    else
      {:error, _reason} = error ->
        File.chmod(destination, 0o700)
        File.rm(path)
        File.rm(temporary)
        error
    end
  end

  defp seal_directories(path, seal?) do
    with {:ok, entries} <- list_artifact(path),
         :ok <-
           each(Enum.sort(entries), fn name ->
             child = Path.join(path, name)

             case File.lstat(child) do
               {:ok, %{type: :directory}} -> seal_directories(child, true)
               {:ok, %{type: :regular}} -> :ok
               {:ok, %{type: type}} -> {:error, {:unsafe_artifact, child, type}}
               {:error, reason} -> {:error, {:artifact, child, reason}}
             end
           end) do
      if seal? do
        with :ok <- file_result(File.chmod(path, 0o555), path),
             :ok <- sync_directory(path),
             do: :ok
      else
        :ok
      end
    end
  end

  defp sync_directory(path) do
    with {:ok, directory} <- :file.open(path, [:read, :directory]) do
      try do
        file_result(:file.sync(directory), path)
      after
        :file.close(directory)
      end
    end
  end

  defp directory(path), do: file_result(File.mkdir_p(path), path)

  defp write_artifact(path, bytes) do
    if Regex.match?(@private_key, bytes) do
      {:error, {:private_artifact, path}}
    else
      with :ok <- directory(Path.dirname(path)),
           {:ok, file} <- :file.open(path, [:write, :exclusive, :raw, :binary]) do
        result =
          try do
            with :ok <- :file.write(file, bytes), :ok <- :file.sync(file), do: :ok
          after
            :file.close(file)
          end

        with :ok <- file_result(result, path), do: seal_file(path, 0o444)
      end
    end
  end

  defp copy_artifact(source, destination, stat) do
    with :ok <- directory(Path.dirname(destination)),
         {:ok, input} <- :file.open(source, [:read, :raw, :binary]) do
      result =
        try do
          with {:ok, output} <- :file.open(destination, [:write, :exclusive, :raw, :binary]) do
            try do
              with :ok <- copy_chunks(input, output, source, <<>>),
                   :ok <- :file.sync(output),
                   do: :ok
            after
              :file.close(output)
            end
          end
        after
          :file.close(input)
        end

      with :ok <- file_result(result, source),
           {:ok, after_stat} <- artifact(source, :regular),
           true <-
             file_identity(stat) == file_identity(after_stat) ||
               {:error, {:artifact_changed_during_export, source}} do
        seal_file(destination, if(Bitwise.band(stat.mode, 0o111) == 0, do: 0o444, else: 0o555))
      end
    end
  end

  defp copy_chunks(input, output, source, carry) do
    case :file.read(input, @chunk_size) do
      :eof ->
        :ok

      {:ok, bytes} ->
        boundary = carry <> binary_part(bytes, 0, min(byte_size(bytes), 80))

        if Regex.match?(@private_key, bytes) or Regex.match?(@private_key, boundary) do
          {:error, {:private_artifact, source}}
        else
          case :file.write(output, bytes) do
            :ok ->
              tail = binary_part(bytes, max(byte_size(bytes) - 80, 0), min(byte_size(bytes), 80))
              copy_chunks(input, output, source, tail)

            {:error, _reason} = error ->
              error
          end
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp file_identity(stat),
    do:
      Map.take(stat, [
        :inode,
        :major_device,
        :minor_device,
        :size,
        :mtime,
        :ctime,
        :mode,
        :uid,
        :gid
      ])

  defp seal_file(path, mode), do: file_result(File.chmod(path, mode), path)

  defp read_artifact(path) do
    with {:ok, _stat} <- artifact(path, :regular) do
      case File.read(path) do
        {:ok, bytes} -> {:ok, bytes}
        {:error, reason} -> {:error, {:artifact, path, reason}}
      end
    end
  end

  defp artifact(path, expected \\ nil) do
    expanded = Path.expand(path)
    components = Path.split(expanded)

    result =
      Enum.reduce_while(components, {:ok, nil, nil}, fn component, {:ok, parent, _stat} ->
        current = if is_nil(parent), do: component, else: Path.join(parent, component)

        case File.lstat(current, time: :posix) do
          {:ok, %{type: type} = stat} when type in [:regular, :directory] ->
            if current != expanded and type != :directory do
              {:halt, {:error, {:unsafe_artifact, current, type}}}
            else
              {:cont, {:ok, current, stat}}
            end

          {:ok, %{type: type}} ->
            {:halt, {:error, {:unsafe_artifact, current, type}}}

          {:error, reason} ->
            {:halt, {:error, {:artifact, current, reason}}}
        end
      end)

    case result do
      {:ok, _path, stat} ->
        cond do
          expected != nil and stat.type != expected ->
            {:error, {:unsafe_artifact, path, stat.type}}

          stat.type == :regular and stat.links != 1 ->
            {:error, {:unsafe_artifact, path, :hardlink}}

          Bitwise.band(stat.mode, 0o444) == 0 ->
            {:error, {:artifact, path, :eacces}}

          stat.type == :directory and Bitwise.band(stat.mode, 0o111) == 0 ->
            {:error, {:artifact, path, :eacces}}

          true ->
            {:ok, stat}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp list_artifact(path) do
    case File.ls(path) do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, {:artifact, path, reason}}
    end
  end

  defp private_name?(name) do
    name in [".ssh", ".git", ".mix", ".erlang.cookie", "authorized_keys", "credentials"] or
      name == ".env" or String.starts_with?(name, ".env.") or
      Regex.match?(
        ~r/^(?:id_(?:rsa|dsa|ecdsa|ed25519)(?:\..*)?|ssh_host_.*_key|private_key(?:\..*)?)$/,
        name
      )
  end

  defp private_term?(bytes) when is_binary(bytes), do: Regex.match?(@private_key, bytes)

  defp private_term?(map) when is_map(map),
    do:
      map
      |> :maps.to_list()
      |> Enum.any?(fn {key, value} -> private_term?(key) or private_term?(value) end)

  defp private_term?(list) when is_list(list), do: Enum.any?(list, &private_term?/1)

  defp private_term?(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.any?(&private_term?/1)

  defp private_term?(_other), do: false

  defp versions(apps), do: Map.new(apps, fn {app, metadata} -> {app, metadata.version} end)

  defp file_result(:ok, _path), do: :ok
  defp file_result({:error, reason}, _path) when is_tuple(reason), do: {:error, reason}
  defp file_result({:error, reason}, path), do: {:error, {:artifact, path, reason}}

  defp each(items, function) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case function.(item) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end
end
