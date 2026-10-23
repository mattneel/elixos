defmodule Mix.Tasks.Elixos.New do
  use Mix.Task

  @shortdoc "Creates an ordinary Mix app that also builds natively on Elixos"
  @moduledoc """
  Creates a supervised, host-testable Mix application at a new path.

      mix elixos.new PATH [--app APP] [--module MODULE] [--boot auto|manual]

  The application and module names default to the path basename and its
  CamelCase form. `--app` and `--module` override them. Existing paths are never
  overwritten. `--boot` defaults to `auto`; `manual` still permits services at
  explicit installation, but does not start them from a saved generation.

  The generated counter has portable logic, a normal OTP application callback,
  and host tests. Its private `os/0` helper supplies the existing `elixos:`
  declaration with `services`, `persist`, `min_os` and `boot`. Its state lives
  under `var/state` on the host and `/priv/data/APP/state` on Elixos. `persist`
  describes ordinary filesystem durability: a Live system's RAM is lost on a
  kernel reboot; this declaration does not create USB snapshots or mounts.

  After generation, run `mix test` in the new directory. Host dev/test neither
  fetches nor starts `:elixos`. `config_target()` selects target settings while
  `MIX_ENV` remains dev, test or prod. The only dependency is the target-only
  OS requirement `{:elixos, "~> 0.1", targets: :elixos}`. For any subsequent
  host dependency fetching use `mix deps.get --target host --only test` (or
  `--only dev`): plain `mix deps.get` fetches across all targets.

  Install this build-time tooling as an archive, not as a runtime dependency:

      # In the elixos_sdk source directory, with an isolated MIX_HOME if desired:
      mix archive.build -o /tmp/elixos_sdk-0.1.0.ez
      mix archive.install /tmp/elixos_sdk-0.1.0.ez --force

  Package source with `MIX_ENV=prod MIX_TARGET=elixos mix elixos.package` on
  the host. Do not run `mix deps.get` or compile this target on the host:
  Elixos supplies its own OS application, compiler and native runtime. Transfer
  source or publish a standard signed Hex repository, then use
  `Elixos.Package.install/1` in real Elixos to build/install natively.

  Repository publication remains `mix hex.registry build` (or ordinary Hex
  publication). Trust a repository explicitly using its verified RSA public
  key: host `mix hex.repo add NAME URL --public-key /path/to/public_key`, and
  guest `Elixos.Package.add_repo(:name, url, key: public_key_pem)`. No command
  here reads signing keys, adds repositories or trusts a URL automatically.
  """

  @impl true
  def run(arguments) do
    {options, paths} =
      OptionParser.parse!(arguments, strict: [app: :string, module: :string, boot: :string])

    case paths do
      [path] ->
        project = ElixosSDK.Generator.generate(path, options)

        Mix.shell().info("""

        Created #{project.app}. Run `mix test` in #{project.path} for host development.
        Package source: MIX_ENV=prod MIX_TARGET=elixos mix elixos.package
        Compile/install the target only inside real Elixos with Elixos.Package.install/1.
        """)

      _ ->
        Mix.raise(
          "Expected mix elixos.new PATH [--app APP] [--module MODULE] [--boot auto|manual]"
        )
    end
  end
end
