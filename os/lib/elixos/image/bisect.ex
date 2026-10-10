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
    cond do
      not good?.([]) -> {:error, :base_bad}
      good?.(entries) -> :none
      true -> search(entries, good?, 0, length(entries))
    end
  end

  # `good` counts entries known to leave the system good, `bad` entries known
  # to break it (monotonic, so the whole list is already known bad). The first
  # breaking entry is the one where the two meet.
  defp search(_entries, _good?, good, bad) when bad - good == 1, do: {:ok, bad}

  defp search(entries, good?, good, bad) do
    middle = div(good + bad, 2)

    if good?.(Enum.take(entries, middle)) do
      search(entries, good?, middle, bad)
    else
      search(entries, good?, good, middle)
    end
  end
end
