defmodule ElixosSDK.Generator do
  @moduledoc false

  @templates [
    {"mix.exs", "mix.exs"},
    {"LICENSE", "LICENSE"},
    {"formatter.exs", ".formatter.exs"},
    {"gitignore", ".gitignore"},
    {"config.exs", "config/config.exs"},
    {"elixos.exs", "config/elixos.exs"},
    {"app.ex", "lib/@FILE@.ex"},
    {"application.ex", "lib/@FILE@/application.ex"},
    {"supervisor.ex", "lib/@FILE@/supervisor.ex"},
    {"counter.ex", "lib/@FILE@/counter.ex"},
    {"test_helper.exs", "test/test_helper.exs"},
    {"app_test.exs", "test/@FILE@_test.exs"}
  ]

  def generate(path, options \\ []) do
    app = Keyword.get(options, :app, Path.basename(Path.expand(path)))
    module = Keyword.get(options, :module, Macro.camelize(app))
    boot = Keyword.get(options, :boot, "auto")
    validate!(app, module, boot)

    if File.exists?(path) or match?({:ok, _}, File.lstat(path)) do
      Mix.raise("Refusing to overwrite existing path #{inspect(path)}")
    end

    replacements = [
      {"@APP@", app},
      {"@MODULE@", module},
      {"@FILE@", Macro.underscore(module)},
      {"@BOOT@", boot}
    ]

    templates = Application.app_dir(:elixos_sdk, "priv/templates")

    Enum.each(@templates, fn {source, destination} ->
      destination = Path.join(path, substitute(destination, replacements))
      contents = templates |> Path.join(source) |> File.read!() |> substitute(replacements)
      File.mkdir_p!(Path.dirname(destination))
      File.write!(destination, contents, [:exclusive])
      Mix.shell().info("* creating #{destination}")
    end)

    %{app: app, module: module, path: Path.expand(path)}
  end

  defp substitute(text, replacements) do
    Enum.reduce(replacements, text, fn {token, value}, text ->
      String.replace(text, token, value)
    end)
  end

  defp validate!(app, module, boot) do
    unless app =~ ~r/\A[a-z][a-z0-9_]*\z/ do
      Mix.raise("Expected --app to start with a lowercase letter and contain only a-z, 0-9 or _")
    end

    reserved = [
      "elixos",
      "elixos_sdk" | Enum.map(Mix.Tasks.New.reserved_application_names(), &Atom.to_string/1)
    ]

    if app in reserved do
      Mix.raise("Application name #{inspect(app)} is reserved")
    end

    unless module =~ ~r/\A[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*\z/ do
      Mix.raise("Expected --module to be an Elixir alias, for example MyApp or Example.MyApp")
    end

    if module == "Elixos" or String.starts_with?(module, "Elixos.") do
      Mix.raise("The Elixos module namespace belongs to the running OS")
    end

    unless boot in ["auto", "manual"] do
      Mix.raise("Expected --boot to be auto or manual")
    end
  end
end
