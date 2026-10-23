defmodule ElixosDemo.OS do
  @moduledoc """
  Real OS observations, compiled only for MIX_TARGET=elixos in real Elixos.

  There is deliberately no host implementation or shadow Elixos module. A host
  build omits this source directory; native target compilation uses the public
  APIs supplied by the guest's already-running `:elixos` application.
  """

  @doc "Observes the current boot and the OS-owned stable application data directory."
  def info do
    %{
      boot: Elixos.info(),
      data_dir: Elixos.Package.data_dir(:elixos_demo)
    }
  end
end
