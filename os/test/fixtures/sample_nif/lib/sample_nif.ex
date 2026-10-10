defmodule SampleNif do
  @moduledoc "Fixture NIF: proves dlopen works on the dynamic musl ERTS (ADR-008)."
  @on_load :load

  def load do
    :code.priv_dir(:sample_nif)
    |> Path.join("sample_nif")
    |> String.to_charlist()
    |> :erlang.load_nif(0)
  end

  def add(_a, _b), do: :erlang.nif_error(:not_loaded)
end
