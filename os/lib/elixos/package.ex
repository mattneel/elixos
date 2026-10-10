defmodule Elixos.Package do
  @moduledoc """
  Installing regular Elixir apps onto the running system (M11, self-hosting).

  `install/1` takes a Mix project directory on the box, builds it in place with
  `MIX_TARGET=elixos` (so its `config/elixos.exs` applies and `targets: :elixos`
  deps are included), resolves its dependencies system-wide
  (`Elixos.Package.Resolver`), loads it into the running VM, starts the
  services from its `elixos:` key (`Elixos.Package.Spec`), and records it in
  the image so the next `Elixos.save/1` includes it.

  NIFs compile with the bundled `zig cc` (ADR-009) against the running ERTS.
  """

  @spec install(Path.t()) :: {:ok, atom()} | {:error, term()}
  def install(dir), do: Elixos.NotImplemented.raise!(11, "Elixos.Package.install/1 #{dir}")

  @doc "Installed apps and versions."
  @spec installed() :: %{atom() => String.t()}
  def installed, do: Elixos.NotImplemented.raise!(11, "Elixos.Package.installed/0")
end
