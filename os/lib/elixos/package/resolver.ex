defmodule Elixos.Package.Resolver do
  @moduledoc """
  System-wide package resolution (ADR-015).

  One VM means one module namespace, so unlike releases, Elixos cannot give
  each app its own copy of a dependency. The resolver therefore keeps exactly
  one version of every package installed, Debian style, and refuses an install
  that would leave any installed package with an unsatisfied requirement.

  The `elixos` package is the OS itself: a dependency on it is checked against
  the running OS version and must never arrive bundled.

  `plan(installed, incoming, os_version)`:

    * the resulting set is `installed` with `incoming` replacing same-named apps
    * every requirement of every package in the resulting set must hold
    * on success: `{:ok, %{install: apps, upgrade: apps, unchanged: apps}}`,
      each a sorted list of app names (`upgrade` = version changed)
    * otherwise `{:error, conflicts}`, sorted, each one of
      * `{:unsatisfied, app, dep, requirement, found_version_or_nil}`
      * `{:os_version, app, requirement, os_version}`
      * `{:bundled_os, :elixos}`
  """

  @type pkg :: %{app: atom(), version: String.t(), deps: %{atom() => String.t()}}

  @spec plan([pkg()], [pkg()], String.t()) ::
          {:ok, %{install: [atom()], upgrade: [atom()], unchanged: [atom()]}}
          | {:error, [tuple()]}
  def plan(installed, incoming, os_version) do
    conflicts =
      bundled_os(incoming) ++ unsatisfied(installed, incoming, os_version)

    case Enum.sort(conflicts) do
      [] -> {:ok, classify(installed, incoming)}
      conflicts -> {:error, conflicts}
    end
  end

  # The OS itself must never arrive as a package to install.
  defp bundled_os(incoming) do
    for %{app: :elixos} <- incoming, do: {:bundled_os, :elixos}
  end

  # One version per package (ADR-015): installers arrive on top of what is
  # there, and then every requirement of every resulting package must hold.
  defp unsatisfied(installed, incoming, os_version) do
    result = merge(installed, incoming)

    for package <- Map.values(result),
        {dep, requirement} <- package.deps,
        conflict = requirement_conflict(result, package, dep, requirement, os_version),
        conflict != nil,
        do: conflict
  end

  defp merge(installed, incoming) do
    installed
    |> Map.new(&{&1.app, &1})
    |> Map.merge(Map.new(incoming, &{&1.app, &1}))
  end

  defp requirement_conflict(_result, package, :elixos, requirement, os_version) do
    unless Version.match?(os_version, requirement) do
      {:os_version, package.app, requirement, os_version}
    end
  end

  defp requirement_conflict(result, package, dep, requirement, _os_version) do
    found = result |> Map.get(dep, %{version: nil}) |> Map.get(:version)

    if found == nil or not Version.match?(found, requirement) do
      {:unsatisfied, package.app, dep, requirement, found}
    end
  end

  # The classification is over the resulting set: an installed package that
  # nothing replaces is unchanged, and so is one arriving at its own version.
  defp classify(installed, incoming) do
    before = Map.new(installed, &{&1.app, &1.version})
    arriving = Map.new(incoming, &{&1.app, &1.version})
    result = merge(installed, incoming)

    Enum.reduce(Map.keys(result), %{install: [], upgrade: [], unchanged: []}, fn app, acc ->
      case {Map.fetch(before, app), Map.fetch(arriving, app)} do
        {:error, {:ok, _version}} ->
          Map.update!(acc, :install, &[app | &1])

        {{:ok, version}, {:ok, version}} ->
          Map.update!(acc, :unchanged, &[app | &1])

        {{:ok, _old}, {:ok, _new}} ->
          Map.update!(acc, :upgrade, &[app | &1])

        {{:ok, _version}, :error} ->
          Map.update!(acc, :unchanged, &[app | &1])
      end
    end)
    |> Map.new(fn {kind, apps} -> {kind, Enum.sort(apps)} end)
  end
end
