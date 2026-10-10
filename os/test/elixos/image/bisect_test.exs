defmodule Elixos.Image.BisectTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 7

  alias Elixos.Image.Bisect

  # good?.(prefix) is false as soon as the prefix contains entry number `bad_from`.
  defp counting(bad_from) do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    good? = fn prefix ->
      Agent.update(calls, &(&1 + 1))
      bad_from == nil or length(prefix) < bad_from
    end

    {good?, fn -> Agent.get(calls, & &1) end}
  end

  test "finds the first entry that breaks the system" do
    {good?, _} = counting(5)
    assert Bisect.first_bad(Enum.to_list(1..8), good?) == {:ok, 5}
  end

  test "the very first entry can be the culprit" do
    {good?, _} = counting(1)
    assert Bisect.first_bad([:a, :b, :c], good?) == {:ok, 1}
  end

  test "so can the last" do
    {good?, _} = counting(3)
    assert Bisect.first_bad([:a, :b, :c], good?) == {:ok, 3}
  end

  test "all good" do
    {good?, _} = counting(nil)
    assert Bisect.first_bad([:a, :b, :c], good?) == :none
    assert Bisect.first_bad([], good?) == :none
  end

  test "a bad base is reported, not bisected" do
    assert Bisect.first_bad([:a, :b], fn _ -> false end) == {:error, :base_bad}
  end

  test "uses a logarithmic number of checks" do
    for n <- [1, 2, 3, 10, 1000], bad <- Enum.uniq([1, div(n, 2) + 1, n]) do
      {good?, calls} = counting(bad)
      assert Bisect.first_bad(Enum.to_list(1..n), good?) == {:ok, bad}
      limit = ceil(:math.log2(max(n, 2))) + 2
      assert calls.() <= limit, "n=#{n} bad=#{bad}: #{calls.()} checks > #{limit}"
    end
  end
end
