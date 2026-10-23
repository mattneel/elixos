defmodule ElixosDemoStatsTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 27

  test "an empty sample does not invent a zero measurement" do
    assert ElixosDemoStats.summarize([]) == %{count: 0, min: nil, max: nil, mean: nil}
  end

  test "mixed negative, integer and floating samples retain extrema and an arithmetic mean" do
    assert ElixosDemoStats.summarize([-4, 1.5, 5.5]) == %{
             count: 3,
             min: -4,
             max: 5.5,
             mean: 1.0
           }
  end

  test "a singleton and a reordered sample have the expected summary" do
    assert ElixosDemoStats.summarize([12]) == %{count: 1, min: 12, max: 12, mean: 12.0}
    assert ElixosDemoStats.summarize([1, 3, 2]) == ElixosDemoStats.summarize([3, 2, 1])
  end
end
