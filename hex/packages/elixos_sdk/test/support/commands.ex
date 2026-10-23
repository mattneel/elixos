defmodule ElixosSDK.TestCommands do
  @moduledoc false

  def mix(path, arguments, environment \\ []) do
    executable = System.find_executable("elixir") || raise "elixir must be on PATH"
    sdk_ebin = Application.app_dir(:elixos_sdk, "ebin")

    env =
      Keyword.merge(
        [
          MIX_ENV: "prod",
          MIX_TARGET: "elixos",
          MIX_BUILD_PATH: Path.join(path, "_build"),
          MIX_DEPS_PATH: Path.join(path, "deps"),
          HEX_OFFLINE: "1"
        ],
        environment
      )
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)

    System.cmd(executable, ["--erl", "+S 2:2", "-pa", sdk_ebin, "-S", "mix" | arguments],
      cd: path,
      env: env,
      stderr_to_stdout: true
    )
  end
end
