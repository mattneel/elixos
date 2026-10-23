defmodule ElixosDemoStats do
  @moduledoc """
  Portable one-pass summary statistics shared by ordinary Mix and Elixos apps.

  This is a separate ordinary Hex package, not an OS API or a copy of one.
  `elixos_demo` depends on `:elixos_demo_stats`; native Elixos installs resolve
  its modules from the single installed dependency rather than bundling them
  into each consuming application.
  """

  @type summary :: %{
          count: non_neg_integer(),
          min: number() | nil,
          max: number() | nil,
          mean: float() | nil
        }

  @doc "Summarizes a list of numeric observations; an empty sample has no extrema or mean."
  @spec summarize([number()]) :: summary()
  def summarize(values) when is_list(values) do
    {count, sum, minimum, maximum} =
      Enum.reduce(values, {0, 0, nil, nil}, fn value, {count, sum, minimum, maximum}
                                               when is_number(value) ->
        {count + 1, sum + value, smallest(minimum, value), largest(maximum, value)}
      end)

    %{
      count: count,
      min: minimum,
      max: maximum,
      mean: if(count == 0, do: nil, else: sum / count)
    }
  end

  defp smallest(nil, value), do: value
  defp smallest(minimum, value), do: min(minimum, value)
  defp largest(nil, value), do: value
  defp largest(maximum, value), do: max(maximum, value)
end
