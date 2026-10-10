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
    _ = {installed, incoming, os_version}
    Elixos.NotImplemented.raise!(10, "Elixos.Package.Resolver.plan/3")
  end
end
