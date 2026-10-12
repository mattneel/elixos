defmodule Elixos.Package.SCM do
  @moduledoc """
  Resolves a dependency to the installed package that provides it (M26).

  A project built on Elixos declares its dependencies the ordinary way -
  `{:hello_dep, "~> 0.1"}` - and this box has no network and keeps one version
  per package (M10). `Elixos.Package.build/1` prepends this SCM inside the
  child ERTS that runs Mix, so it is asked before any SCM that would fetch:
  when the dependency is installed under `/priv/apps`, it is answered there
  and `checked_out?/1` is true because it is already on the disk, so Mix never
  reaches for a repository.

  `accepts_options/2` declines - returning `nil`, so the ordinary SCMs decide -
  when the dependency names its own source (`:path`, `:git`, ...), when nothing
  by that name is installed, and when what is installed does not satisfy the
  requirement in the `mix.exs`. A dependency this box did not install resolves
  the ordinary way, where a repository is the only place it could come from.
  """
  @behaviour Mix.SCM

  @own_source [:path, :git, :github, :gitlab, :bitbucket]

  @impl true
  def fetchable?, do: false

  @impl true
  def accepts_options(app, opts) do
    with nil <- named_source(opts),
         dir when is_binary(dir) <- installed_dir(app),
         true <- satisfies?(app, opts) do
      Keyword.put(opts, :dest, dir)
    else
      _other -> nil
    end
  end

  @impl true
  def checked_out?(opts), do: File.dir?(opts[:dest])

  @impl true
  def lock_status(_opts), do: :ok

  @impl true
  def format(opts), do: "the installed package at #{opts[:dest]}"

  @impl true
  def format_lock(_opts), do: nil

  @impl true
  def equal?(one, two), do: one[:dest] == two[:dest]

  @impl true
  def managers(_opts), do: []

  # Only reachable if something removed the directory between the check and
  # here: accepting a dependency means it is already on the disk.
  @impl true
  def checkout(opts) do
    if checked_out?(opts) do
      :ok
    else
      raise "the installed package at #{opts[:dest]} disappeared during the build"
    end
  end

  @impl true
  def update(opts), do: opts[:lock]

  defp named_source(opts), do: Enum.find(@own_source, &opts[&1])

  defp installed_dir(app) do
    dir = Elixos.Package.installed_dir(app)

    if File.dir?(Path.join(dir, "ebin")), do: dir
  end

  defp satisfies?(app, opts) do
    case {Elixos.Package.installed_version(app), opts[:requirement]} do
      {nil, _requirement} -> false
      {_version, nil} -> true
      {version, requirement} -> Version.match?(version, requirement)
    end
  end
end
