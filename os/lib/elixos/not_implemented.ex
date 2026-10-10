defmodule Elixos.NotImplemented do
  @moduledoc """
  Raised by roadmap stubs. The message names the milestone that implements it,
  so a red test points straight at the right section of docs/ROADMAP.md.
  """
  defexception [:message]

  @spec raise!(non_neg_integer(), String.t()) :: no_return()
  def raise!(milestone, what) do
    raise __MODULE__, message: "TODO(M#{milestone}): #{what} (see docs/ROADMAP.md)"
  end
end
