defmodule Elixos.Image.GenerationTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 6
  @moduletag :tmp_dir

  alias Elixos.Image.Generation

  @hash_a String.duplicate("a", 64)
  @hash_b String.duplicate("b", 64)
  @hash_c String.duplicate("c", 64)

  setup %{tmp_dir: tmp_dir} do
    dir = Path.join(tmp_dir, "generations")
    File.mkdir_p!(dir)
    %{dir: dir}
  end

  defp gen(number, modules, opts \\ []) do
    %Generation{
      number: number,
      parent: Keyword.get(opts, :parent, number - 1),
      modules: modules,
      boot: Keyword.get(opts, :boot, []),
      created_at: ~U[2026-10-09 20:00:00Z]
    }
  end

  test "write/read round-trips", %{dir: dir} do
    g = gen(1, %{Foo => @hash_a, Bar => @hash_b}, boot: [{Foo, :start, []}])
    assert :ok = Generation.write(dir, g)
    assert Generation.read(dir, 1) == {:ok, g}
  end

  test "generation 0 is the factory and is never written", %{dir: dir} do
    assert Generation.write(dir, gen(0, %{}, parent: 0)) == {:error, :reserved}
    refute File.exists?(Generation.path(dir, 0))
  end

  test "generations are immutable once saved", %{dir: dir} do
    assert :ok = Generation.write(dir, gen(1, %{Foo => @hash_a}))
    assert Generation.write(dir, gen(1, %{Foo => @hash_b})) == {:error, :exists}
    assert {:ok, %Generation{modules: %{Foo => @hash_a}}} = Generation.read(dir, 1)
  end

  test "list and next_number", %{dir: dir} do
    assert Generation.list(dir) == []
    assert Generation.next_number(dir) == 1

    for n <- [1, 2, 10], do: :ok = Generation.write(dir, gen(n, %{}))
    File.write!(Path.join(dir, "notes.txt"), "not a generation")

    assert Generation.list(dir) == [1, 2, 10]
    assert Generation.next_number(dir) == 11
  end

  test "missing and corrupt generations", %{dir: dir} do
    assert Generation.read(dir, 7) == {:error, :not_found}

    File.write!(Generation.path(dir, 7), "garbage")
    assert Generation.read(dir, 7) == {:error, :corrupt}

    File.write!(Generation.path(dir, 8), :erlang.term_to_binary({:something_else, 1, %{}}))
    assert Generation.read(dir, 8) == {:error, :corrupt}
  end

  test "the on-disk envelope is versioned", %{dir: dir} do
    :ok = Generation.write(dir, gen(3, %{Foo => @hash_a}))

    assert {:elixos_generation, 1, %{number: 3, modules: %{Foo => @hash_a}}} =
             dir |> Generation.path(3) |> File.read!() |> :erlang.binary_to_term()
  end

  test "no temporary files are left behind", %{dir: dir} do
    for n <- 1..5, do: :ok = Generation.write(dir, gen(n, %{}))
    assert dir |> File.ls!() |> Enum.sort() == Enum.map(1..5, &"#{&1}.gen")
  end

  test "diff reports added, removed and changed modules, sorted" do
    old = gen(1, %{Keep => @hash_a, Gone => @hash_a, Edited => @hash_a})
    new = gen(2, %{Keep => @hash_a, Edited => @hash_b, NewB => @hash_c, NewA => @hash_c})

    assert Generation.diff(old, new) == %{added: [NewA, NewB], removed: [Gone], changed: [Edited]}
  end
end
