defmodule ElixosSDK.Image do
  @moduledoc false

  import Bitwise

  @owner_label "io.elixos.sdk.image.owner"
  @name ~r/\A[a-z][a-z0-9_]*\z/
  @image ~r/\A[A-Za-z0-9][A-Za-z0-9_.:\/@-]*\z/
  @public_key ~r/\A-----BEGIN (RSA PUBLIC KEY|PUBLIC KEY)-----\r?\n[A-Za-z0-9+\/=\r\n]+-----END \1-----\s*\z/

  def build(options) do
    settings = options!(options)
    Mix.Project.get!()
    docker = executable!("docker")
    elixir = executable!("elixir")
    shell = executable!("sh")
    settings = native_images!(docker, settings)
    work = temporary_directory!()
    System.at_exit(fn _status -> remove_work(work) end)

    try do
      Mix.shell().info("Packaging source in a fresh MIX_ENV=prod MIX_TARGET=elixos command")
      package_source!(elixir, work)
      prepare_inputs!(work, settings)
      launcher = Path.join(work, "image.sh")
      File.write!(launcher, launcher(work, docker, settings))

      {output, status} = System.cmd(shell, [launcher], stderr_to_stdout: true)

      if status != 0 do
        Mix.raise("Native Elixos image build failed (exit #{status}):\n#{output}")
      end

      Mix.shell().info(output)

      Mix.shell().info(
        "Built #{settings.tag} from a restored, healthy, committed native generation"
      )

      :ok
    after
      remove_work(work)
    end
  end

  def options!(options) do
    for key <- [:tag, :sdk_image, :runtime_image, :repo, :repo_url, :repo_key, :repo_dir] do
      if length(Keyword.get_values(options, key)) > 1 do
        Mix.raise("--#{option_name(key)} may only be supplied once")
      end
    end

    tag = Keyword.get(options, :tag) || Mix.raise("--tag IMAGE is required")
    sdk_image = Keyword.get(options, :sdk_image, "elixos:sdk")
    runtime_image = Keyword.get(options, :runtime_image, "elixos:runtime")

    for {key, value} <- [tag: tag, sdk_image: sdk_image, runtime_image: runtime_image] do
      unless Regex.match?(@image, value) and (key != :tag or not String.contains?(value, "@")) do
        Mix.raise("--#{option_name(key)} must be a Docker image reference, without whitespace")
      end
    end

    repo = Keyword.get(options, :repo)
    url = Keyword.get(options, :repo_url)
    key_path = Keyword.get(options, :repo_key)
    directory = Keyword.get(options, :repo_dir)
    installs = Keyword.get_values(options, :install)

    unless Enum.all?([repo, url, key_path], &is_nil/1) or
             Enum.all?([repo, url, key_path], &is_binary/1) do
      Mix.raise("--repo NAME, --repo-url URL and --repo-key PATH must be supplied together")
    end

    if directory && is_nil(repo) do
      Mix.raise("--repo-dir requires --repo, --repo-url and --repo-key")
    end

    for name <- installs do
      unless Regex.match?(@name, name) do
        Mix.raise("--install must name a Hex package (lowercase letters, digits and underscores)")
      end
    end

    repository =
      if repo do
        unless Regex.match?(@name, repo) do
          Mix.raise(
            "--repo must use lowercase letters, digits and underscores and start with a letter"
          )
        end

        validate_repository_url!(url, repo, directory)
        key = public_key!(Path.expand(key_path))

        if directory do
          root = Path.expand(directory)
          files = repository_files!(root)
          public_key!(Path.join(root, "public_key"))
          %{name: repo, url: url, key: key, directory: root, files: files}
        else
          %{name: repo, url: url, key: key, directory: nil, files: []}
        end
      end

    %{
      tag: tag,
      sdk_image: sdk_image,
      runtime_image: runtime_image,
      repository: repository,
      installs: installs
    }
  end

  def native_platform!(daemon, sdk, runtime) do
    platforms = Enum.map([daemon, sdk, runtime], &normalize_platform!/1)

    case Enum.uniq(platforms) do
      [platform] ->
        platform

      _ ->
        Mix.raise(
          "Native Elixos builds require matching Linux Docker daemon, SDK and runtime architectures; " <>
            "got daemon=#{daemon}, SDK=#{sdk}, runtime=#{runtime}. " <>
            "Cross-architecture execution through binfmt/QEMU is not supported"
        )
    end
  end

  def repository_files!(directory) do
    unless File.lstat!(directory).type == :directory do
      Mix.raise("--repo-dir must be a real directory, not a link")
    end

    required = ["names", "versions", "public_key", "packages", "tarballs"]
    entries = File.ls!(directory)

    unless Enum.sort(entries) == Enum.sort(required) do
      Mix.raise(
        "--repo-dir accepts only a public static Hex tree: names, versions, public_key, packages/ and tarballs/"
      )
    end

    for name <- ["names", "versions", "public_key"] do
      regular_file!(Path.join(directory, name), "public repository resource")
    end

    nested =
      for subdirectory <- ["packages", "tarballs"], reduce: [] do
        files ->
          path = Path.join(directory, subdirectory)

          unless File.lstat!(path).type == :directory do
            Mix.raise("Public repository #{subdirectory}/ must be a directory, not a link")
          end

          resources =
            for name <- Enum.sort(File.ls!(path)) do
              valid? =
                if subdirectory == "packages" do
                  Regex.match?(@name, name)
                else
                  Regex.match?(~r/\A[a-z][a-z0-9_]*-[0-9][0-9A-Za-z.+-]*\.tar\z/, name)
                end

              unless valid? do
                Mix.raise("Not a public static Hex resource: #{subdirectory}/#{name}")
              end

              relative = Path.join(subdirectory, name)
              regular_file!(Path.join(directory, relative), "public repository resource")
              relative
            end

          files ++ resources
      end

    ["names", "versions", "public_key" | nested]
  end

  defp validate_repository_url!(url, name, directory) when is_binary(directory) do
    unless url == "/priv/hex/mirrors/#{name}" do
      Mix.raise("With --repo-dir, --repo-url must be /priv/hex/mirrors/#{name}")
    end
  end

  defp validate_repository_url!(url, _name, nil) do
    uri = URI.parse(url)

    unless uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
             is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
             not Regex.match?(~r/[\s\x00-\x1f\x7f]/, url) do
      Mix.raise(
        "--repo-url must be a public http(s) URL without credentials, query or fragment; use --repo-dir for an offline mirror"
      )
    end
  end

  defp public_key!(path) do
    regular_file!(path, "repository RSA public key")
    key = File.read!(path)

    unless Regex.match?(@public_key, key) do
      Mix.raise(
        "--repo-key and repository public_key must contain only one PEM RSA public key, never a private key"
      )
    end

    # The real native Repo.add/3 decodes and validates RSA. This host-side
    # envelope check prevents accidentally passing a private key to Docker.
    key
  end

  defp regular_file!(path, description) do
    unless File.lstat!(path).type == :regular do
      Mix.raise("Expected a regular #{description}, not a link or special file: #{path}")
    end
  end

  defp native_images!(docker, settings) do
    daemon =
      docker_metadata!(
        docker,
        ["info", "--format", "{{.OSType}}/{{.Architecture}}"],
        "Docker daemon platform"
      )

    sdk =
      docker_metadata!(
        docker,
        ["image", "inspect", "--format", "{{.Os}}/{{.Architecture}}", settings.sdk_image],
        "SDK image #{settings.sdk_image}; build or pull the native image locally first"
      )

    runtime =
      docker_metadata!(
        docker,
        ["image", "inspect", "--format", "{{.Os}}/{{.Architecture}}", settings.runtime_image],
        "runtime image #{settings.runtime_image}; build or pull the native image locally first"
      )

    Map.put(settings, :platform, native_platform!(daemon, sdk, runtime))
  end

  defp docker_metadata!(docker, arguments, description) do
    # Docker diagnostics stay on stderr; only exact inspect metadata is parsed.
    case System.cmd(docker, arguments) do
      {output, 0} -> String.trim(output)
      {output, status} -> Mix.raise("Cannot inspect #{description} (exit #{status}):\n#{output}")
    end
  end

  defp normalize_platform!(platform) do
    case String.split(platform, "/") do
      ["linux", architecture] when architecture in ["amd64", "x86_64"] ->
        "linux/amd64"

      ["linux", architecture] when architecture in ["arm64", "aarch64"] ->
        "linux/arm64"

      _ ->
        Mix.raise(
          "Native Elixos builds require a Linux amd64/x86_64 or arm64/aarch64 platform, got #{inspect(platform)}; " <>
            "cross-architecture emulation is not supported"
        )
    end
  end

  defp executable!(name) do
    System.find_executable(name) || Mix.raise("#{name} must be available on PATH")
  end

  defp option_name(key), do: key |> Atom.to_string() |> String.replace("_", "-")

  defp temporary_directory! do
    identifier =
      "#{System.pid()}-#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive])}"

    work = Path.join(System.tmp_dir!(), "elixos-image-#{identifier}")
    File.mkdir!(work)
    File.chmod!(work, 0o700)
    work
  end

  defp package_source!(elixir, work) do
    arguments = [
      "--erl",
      "+S 2:2",
      "-pa",
      Application.app_dir(:elixos_sdk, "ebin"),
      "-S",
      "mix",
      "elixos.package",
      "--unpack",
      "--output",
      Path.join(work, "source")
    ]

    {output, status} =
      System.cmd(elixir, arguments,
        env: package_environment(),
        stderr_to_stdout: true
      )

    if status != 0 do
      Mix.raise("Source packaging failed (exit #{status}):\n#{output}")
    end

    regular_file!(Path.join([work, "source", "mix.exs"]), "packaged mix.exs")
    prepare_source!(Path.join(work, "source"))
  end

  defp package_environment do
    retained =
      for key <- ["PATH", "HOME", "MIX_HOME", "HEX_HOME", "SSL_CERT_FILE", "SSL_CERT_DIR"],
          value = System.get_env(key),
          not is_nil(value),
          into: %{} do
        {key, value}
      end

    System.get_env()
    |> Map.new(fn {key, _value} -> {key, nil} end)
    |> Map.merge(retained)
    |> Map.merge(%{"MIX_ENV" => "prod", "MIX_TARGET" => "elixos"})
    |> Map.to_list()
  end

  defp prepare_source!(path) do
    stat = File.lstat!(path)

    case stat.type do
      :directory ->
        File.chmod!(path, 0o755)
        for name <- File.ls!(path), do: prepare_source!(Path.join(path, name))

      :regular ->
        # The bind is read-only, but its native copy must be writable. Retain
        # executable source helpers without retaining arbitrary host modes.
        File.chmod!(path, 0o644 ||| (stat.mode &&& 0o111))

      _ ->
        Mix.raise("Source packages may not expose host links or special files: #{path}")
    end
  end

  defp prepare_inputs!(work, settings) do
    control = Path.join(work, "control")
    File.mkdir!(control)
    File.chmod!(control, 0o755)
    File.mkdir!(Path.join(work, "seed"))
    File.mkdir!(Path.join(work, "receipts"))

    if settings.repository do
      File.write!(Path.join(control, "repository.pub"), settings.repository.key)
      File.chmod!(Path.join(control, "repository.pub"), 0o444)

      if settings.repository.directory do
        repository = Path.join(work, "repository")
        File.mkdir!(repository)
        File.chmod!(repository, 0o755)

        for directory <- ["packages", "tarballs"] do
          File.mkdir!(Path.join(repository, directory))
          File.chmod!(Path.join(repository, directory), 0o755)
        end

        for relative <- settings.repository.files do
          source = Path.join(settings.repository.directory, relative)
          regular_file!(source, "public repository resource")
          destination = Path.join(repository, relative)
          File.cp!(source, destination)
          File.chmod!(destination, 0o444)
        end
      end
    end

    owner = Path.basename(work)

    for {name, script} <- [
          {"build.exs", build_script(owner, settings)},
          {"export.exs", export_script(owner)}
        ] do
      File.write!(Path.join(control, name), script)
      File.chmod!(Path.join(control, name), 0o444)
    end

    for phase <- ["build", "export"] do
      # Catch script loading/compilation errors as well as the script's own
      # native API failures; EOF alone is not a native shutdown request.
      input =
        "try do Code.eval_file(\"/elixos-image/control/#{phase}.exs\") " <>
          "catch kind, reason -> IO.puts(:stderr, Exception.format(kind, reason, __STACKTRACE__)); " <>
          "Elixos.Shim.Control.poweroff(); :init.stop() end\n"

      File.write!(Path.join(control, "#{phase}.stdin"), input)
    end

    File.write!(
      Path.join(work, "Dockerfile"),
      """
      # syntax=docker/dockerfile:1.7
      FROM #{settings.runtime_image}
      ADD --chown=0:0 seed.tar /usr/share/elixos/seed/
      ARG ELIXOS_SEED_GENERATION
      ARG ELIXOS_SEED_APP
      RUN root=/usr/share/elixos/seed && \\
          test -f "$root/.container.boot.state" && \\
          test ! -e "$root/boot.state" && \\
          test -f "$root/generations/$ELIXOS_SEED_GENERATION.gen" && \\
          test -f "$root/journal.log" && \\
          test -d "$root/store" && \\
          test -d "$root/apps/$ELIXOS_SEED_APP" && \\
          chmod 0555 "$root"
      """
    )
  end

  defp build_script(owner, settings) do
    repository =
      case settings.repository do
        nil ->
          ""

        repo ->
          mirror =
            if repo.directory do
              """
              File.mkdir_p!("/priv/hex/mirrors")
              {:ok, _} = File.cp_r("/elixos-image/repository", #{inspect(repo.url)})
              """
            else
              ""
            end

          """
          #{mirror}
          :ok = Elixos.Package.add_repo(String.to_atom(#{inspect(repo.name)}), #{inspect(repo.url)},
            key: File.read!("/elixos-image/control/repository.pub"))
          """
      end

    installs =
      Enum.map_join(settings.installs, "\n", fn name ->
        "{:ok, _} = Elixos.Package.install(String.to_atom(#{inspect(name)}))"
      end)

    native_script("saved", owner, """
    :container = Elixos.runtime()
    %{generation: 0, mode: :normal} = Elixos.info()
    {:ok, _} = File.cp_r("/elixos-image/source", "/priv/.elixos-image/source")
    #{repository}
    #{installs}
    {:ok, app} = Elixos.Package.install("/priv/.elixos-image/source")
    {:ok, generation} = Elixos.save()
    true = is_integer(generation) and generation > 0
    write_receipt.(generation, Atom.to_string(app))
    :ok = Elixos.reboot()
    """)
  end

  defp export_script(owner) do
    native_script("exported", owner, """
    :container = Elixos.runtime()
    ["elixos-native-image-saved-v1", #{inspect(owner)}, number, app, ""] =
      String.split(File.read!("/priv/.elixos-image/receipts/saved"), "\\n")
    generation = String.to_integer(number)
    true = generation > 0
    %{generation: ^generation, mode: :normal} = Elixos.info()
    application = String.to_existing_atom(app)
    true = Map.has_key?(Elixos.Package.installed(), application)
    # Never replace the real default health gate with a caller-provided check.
    :error = Application.fetch_env(:elixos, :health_checks)
    health = Elixos.Health.run()
    if health != :ok do
      for path <- Path.wildcard(Path.join(Elixos.Candidate.evidence_dir(generation), "health-*/suite.term")) do
        case Elixos.Candidate.Evidence.read(Path.dirname(path), "suite") do
          {:ok, %{result: {:error, _reason}, output: output}} -> IO.puts(:stderr, output)
          _other -> :ok
        end
      end
    end
    :ok = health
    :ok = Elixos.commit()
    {:ok, %{generation: ^generation, apps: apps}} =
      Elixos.Container.Image.export("/priv/container-export")
    true = Map.has_key?(apps, application)
    write_receipt.(generation, app)
    :ok = Elixos.poweroff()
    """)
  end

  defp native_script(phase, owner, body) do
    """
    receipt_directory = "/priv/.elixos-image/receipts"
    receipt = Path.join(receipt_directory, #{inspect(phase)})
    write_receipt = fn generation, app ->
      bytes = Enum.join(["elixos-native-image-#{phase}-v1", #{inspect(owner)},
        Integer.to_string(generation), app, ""], "\\n")
      file = File.open!(receipt, [:write, :binary, :exclusive])
      try do
        :ok = IO.binwrite(file, bytes)
        :ok = :file.sync(file)
      after
        :ok = File.close(file)
      end
    end
    try do
      File.mkdir_p!(receipt_directory)
      #{body}
    catch
      kind, reason ->
        diagnostic = Exception.format(kind, reason, __STACKTRACE__)
        IO.puts(:stderr, diagnostic)
        File.rm(receipt)
        File.write(Path.join(receipt_directory, "failure"), diagnostic)
        # A refused save or agent snapshot is still a failed build, but must
        # not leave the native supervisor waiting for another console command.
        case Elixos.poweroff() do
          :ok -> :ok
          _ ->
            :ok = Elixos.Shim.Control.poweroff()
            :init.stop()
        end
    end
    """
  end

  defp launcher(work, docker, settings) do
    owner = Path.basename(work)

    bindings =
      [
        "type=bind,#{csv("source=" <> Path.join(work, "source"))},target=/elixos-image/source,readonly",
        "type=bind,#{csv("source=" <> Path.join(work, "control"))},target=/elixos-image/control,readonly"
      ] ++
        if settings.repository && settings.repository.directory do
          [
            "type=bind,#{csv("source=" <> Path.join(work, "repository"))},target=/elixos-image/repository,readonly"
          ]
        else
          []
        end

    mounts = Enum.map_join(bindings, " \\\n          ", &("--mount " <> quote_shell(&1)))

    """
    #!/bin/sh
    set -eu
    umask 077
    work=#{quote_shell(work)}
    docker=#{quote_shell(docker)}
    owner=#{quote_shell(owner)}
    label=#{quote_shell(@owner_label)}
    first="$owner-build"
    second="$owner-export"
    volume="$owner-state"
    watchdog=
    active_client=
    cleanup() {
      status=$?
      trap - EXIT HUP INT TERM
      if [ -n "$watchdog" ]; then kill "$watchdog" 2>/dev/null || :; fi
      if [ -n "$active_client" ]; then kill "$active_client" 2>/dev/null || :; fi
      for container in "$first" "$second"; do
        actual=$("$docker" container inspect --format '{{index .Config.Labels "#{@owner_label}"}}' "$container" 2>/dev/null) || actual=
        if [ "$actual" = "$owner" ]; then
          if ! "$docker" container rm --force "$container" >/dev/null; then
            printf 'Could not clean owned container %s\\n' "$container" >&2
            status=1
          fi
        fi
      done
      actual=$("$docker" volume inspect --format '{{index .Labels "#{@owner_label}"}}' "$volume" 2>/dev/null) || actual=
      if [ "$actual" = "$owner" ]; then
        if ! "$docker" volume rm "$volume" >/dev/null; then
          printf 'Could not clean owned volume %s\\n' "$volume" >&2
          status=1
        fi
      fi
      chmod -R u+w "$work" 2>/dev/null || :
      rm -rf "$work" || status=1
      exit "$status"
    }
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    launcher=$$
    (
      while kill -0 #{quote_shell(System.pid())} 2>/dev/null; do sleep 1; done
      kill -TERM "$launcher" 2>/dev/null || :
    ) &
    watchdog=$!
    fail() {
      printf '%s\\n' "$*" >&2
      for log in "$work/build.log" "$work/export.log"; do
        if [ -f "$log" ]; then cat "$log" >&2; fi
      done
      exit 1
    }
    verify_receipt() {
      file=$1
      phase=$2
      [ -f "$file" ] && [ ! -L "$file" ] || fail "Missing native $phase receipt"
      {
        IFS= read -r magic && IFS= read -r receipt_owner &&
        IFS= read -r receipt_generation && IFS= read -r receipt_app &&
        if IFS= read -r extra || [ -n "$extra" ]; then false; else true; fi
      } < "$file" || fail "Malformed native $phase receipt"
      [ "$magic" = "elixos-native-image-$phase-v1" ] &&
        [ "$receipt_owner" = "$owner" ] || fail "Unowned native $phase receipt"
      case "$receipt_generation" in ''|*[!0-9]*) fail "Invalid saved generation";; esac
      [ "$receipt_generation" -gt 0 ] || fail "Native generation must be positive"
      case "$receipt_app" in ''|*[!a-z0-9_]*) fail "Invalid native application identity";; esac
    }
    create_native() {
      "$docker" container create --name "$1" --label "$label=$owner" --interactive \\
        --platform #{quote_shell(settings.platform)} \\
        --read-only --tmpfs /run:rw,nosuid,nodev,mode=0755 \\
        --tmpfs /tmp:rw,nosuid,nodev,mode=1777 \\
        --mount "type=volume,source=$volume,target=/priv" \\
        #{mounts} \\
        --env ELIXOS_CONSOLE=1 #{quote_shell(settings.sdk_image)} >/dev/null
    }
    run_native() {
      name=$1
      phase=$2
      expected=$3
      status=0
      "$docker" container start --attach --interactive "$name" \\
        < "$work/control/$phase.stdin" > "$work/$phase.log" 2>&1 &
      active_client=$!
      wait "$active_client" || status=$?
      active_client=
      state=$("$docker" container inspect --format '{{.State.Status}}:{{.State.ExitCode}}' "$name") || fail "Cannot inspect native $phase exit"
      [ "$state" = "exited:$expected" ] || fail "Native $phase must exit $expected, got $state (Docker exit $status)"
      [ "$status" -eq 0 ] || [ "$status" -eq "$expected" ] || fail "Docker failed attaching native $phase (exit $status)"
    }
    "$docker" volume create --label "$label=$owner" "$volume" >/dev/null
    actual=$("$docker" volume inspect --format '{{index .Labels "#{@owner_label}"}}' "$volume")
    [ "$actual" = "$owner" ] || fail "Refusing a volume not owned by this build"
    printf '%s\\n' 'Installing and saving source in the first real native SDK boot'
    create_native "$first"
    run_native "$first" build 75
    "$docker" cp "$first:/priv/.elixos-image/receipts/saved" "$work/receipts/saved" || fail "Native save produced no receipt"
    verify_receipt "$work/receipts/saved" saved
    saved_generation=$receipt_generation
    saved_app=$receipt_app
    printf '%s\\n' 'Restoring the saved generation and requiring default native health before commit/export'
    create_native "$second"
    run_native "$second" export 0
    "$docker" cp "$second:/priv/.elixos-image/receipts/." "$work/receipts/" || fail "Native export produced no receipts"
    [ ! -e "$work/receipts/failure" ] || fail "Native build recorded a failure"
    verify_receipt "$work/receipts/exported" exported
    [ "$receipt_generation" = "$saved_generation" ] &&
      [ "$receipt_app" = "$saved_app" ] || fail "Native export changed generation or application"
    # Keep the export as an archive: docker cp's host-side extractor restores
    # 0555 directories before their children and fails for an unprivileged user.
    # ADD extracts inside the build and retains the immutable modes/ownership.
    "$docker" cp "$second:/priv/container-export/." - > "$work/seed/seed.tar" || fail "Cannot retrieve native deployment seed"
    printf '%s\\n' 'Building the runtime image using only the immutable exported seed as context'
    "$docker" build --platform #{quote_shell(settings.platform)} --file "$work/Dockerfile" --tag #{quote_shell(settings.tag)} \\
      --build-arg "ELIXOS_SEED_GENERATION=$saved_generation" --build-arg "ELIXOS_SEED_APP=$saved_app" "$work/seed" &
    active_client=$!
    wait "$active_client"
    active_client=
    """
  end

  defp quote_shell(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
  defp csv(value), do: "\"" <> String.replace(value, "\"", "\"\"") <> "\""

  defp remove_work(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        File.chmod(path, 0o700)

        case File.ls(path) do
          {:ok, names} -> for name <- names, do: remove_work(Path.join(path, name))
          _ -> :ok
        end

        File.rmdir(path)

      {:ok, _} ->
        File.rm(path)

      _ ->
        :ok
    end
  end
end
