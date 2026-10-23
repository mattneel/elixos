defmodule Mix.Tasks.Elixos.Package do
  use Mix.Task

  @shortdoc "Packages Elixos-effective source with standard Hex tooling, without compiling"
  @moduledoc """
  Builds a standard source Hex tarball for the Elixos production target,
  for native applications or portable libraries.

  Install `elixos_sdk` as a Mix archive and install Hex 2.5 or later with
  `mix local.hex`. Run this as a fresh command in the project's directory:

      MIX_ENV=prod MIX_TARGET=elixos mix elixos.package
      MIX_ENV=prod MIX_TARGET=elixos mix elixos.package --output /tmp/my_app-0.1.0.tar
      MIX_ENV=prod MIX_TARGET=elixos mix elixos.package --unpack --output /tmp/my_app-source

  Options are exactly Hex's `--output PATH` (`-o PATH`) and `--unpack`.
  Without `--unpack`, output defaults to `APP-VERSION.tar`. With `--unpack`,
  output is the destination directory, defaulting to `APP-VERSION`. Other
  options and positional arguments are rejected. Parent output directories
  must already exist, as with `mix hex.build`.

  `MIX_ENV=prod` and `MIX_TARGET=elixos` must be selected before Mix loads the
  project, so conditional project configuration is evaluated correctly. The
  task deliberately does not change the VM's environment or working directory.
  It filters declared dependencies to prod/elixos before calling Hex's builder
  directly, bypassing project aliases that might compile or fetch. Thus
  host-only/test-only dependencies are excluded, while target-only and
  target-conditional requirements remain in standard Hex metadata.

  A native application declares an `:elixos` project contract. Whenever this
  key is present, even with an empty contract, its effective dependencies must
  include a versioned, non-optional `:elixos` Hex requirement for the running
  OS. Portable libraries without that key do not need an OS dependency.

  Hex performs its normal metadata, file and dependency validation. Set
  `package: [files: ...]` to include the project's source and `mix.exs`;
  native applications must also include `config` and any target-only source
  directories. This task never fetches dependencies, compiles source/native
  code, copies dependency code, bundles the OS or starts an OS application.
  Compilation and installation happen natively through
  `Elixos.Package.install/1` in a real Elixos guest/device.

  Publish the resulting tarball with existing Hex tooling. For a static signed
  repository use `mix hex.registry build`; authenticate repositories explicitly
  with their RSA public key via host `mix hex.repo add` or guest
  `Elixos.Package.add_repo/3`. Packaging does not publish, read signing keys,
  add repositories or implicitly trust URLs.
  """

  @impl true
  def run(arguments) do
    {_options, positional} =
      OptionParser.parse!(arguments,
        strict: [output: :string, unpack: :boolean],
        aliases: [o: :output]
      )

    if positional != [] do
      Mix.raise("Expected mix elixos.package [--output PATH] [--unpack]")
    end

    unless Mix.env() == :prod and Mix.target() == :elixos do
      Mix.raise("Run as a fresh command: MIX_ENV=prod MIX_TARGET=elixos mix elixos.package")
    end

    Mix.Project.get!()

    hex_builder =
      Mix.Task.get("hex.build") ||
        Mix.raise("Hex 2.5 or later is required; install it with mix local.hex")

    project = Mix.Project.config()
    original = project[:deps] || []
    dependencies = ElixosSDK.Package.dependencies(original)

    if Keyword.has_key?(project, :elixos) do
      ElixosSDK.Package.require_os!(dependencies)
    end

    # Hex filters :only but not :targets. Give its normal builder the effective
    # dependency list, then restore Mix's project configuration even on failure.
    # This touches only build-time Mix state, never cwd or System environment.
    Mix.ProjectStack.merge_config(deps: dependencies)

    try do
      hex_builder.run(arguments)
    after
      Mix.ProjectStack.merge_config(deps: original)
    end
  end
end
