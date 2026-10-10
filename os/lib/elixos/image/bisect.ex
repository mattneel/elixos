defmodule Elixos.Image.Bisect do
  @moduledoc """
  Finds the journal entry that broke the system (docs/ARCHITECTURE.md §4.5).

  Given the entries recorded after a known-good point and a predicate that
  says whether the system is good with the first `k` entries applied, find the
  first entry whose inclusion makes it bad. Assumes monotonicity: once bad,
  every longer prefix is bad too.

    * `good?.([])` must be true, otherwise `{:error, :base_bad}`
    * if every prefix is good: `:none`
    * otherwise `{:ok, index}`, 1-based
    * at most `ceil(log2(length(entries))) + 2` calls to `good?`
  """

  @spec first_bad([term()], ([term()] -> boolean())) ::
          {:ok, pos_integer()} | :none | {:error, :base_bad}
  def first_bad(entries, good?) when is_list(entries) and is_function(good?, 1) do
    Elixos.NotImplemented.raise!(7, "Elixos.Image.Bisect.first_bad/2")
  end
end
