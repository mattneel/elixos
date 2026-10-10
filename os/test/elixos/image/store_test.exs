defmodule Elixos.Image.StoreTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 6
  @moduletag :tmp_dir

  alias Elixos.Image.Store

  setup %{tmp_dir: tmp_dir} do
    {:ok, store} = Store.open(Path.join(tmp_dir, "store"))
    %{store: store}
  end

  test "hash/1 is lowercase hex SHA-256" do
    expected = :crypto.hash(:sha256, "hello") |> Base.encode16(case: :lower)
    assert Store.hash("hello") == expected
    assert byte_size(Store.hash(<<>>)) == 64
  end

  test "put/get round-trips and the address is the hash", %{store: store} do
    bytes = :crypto.strong_rand_bytes(4096)
    assert {:ok, hash} = Store.put(store, bytes)
    assert hash == Store.hash(bytes)
    assert Store.has?(store, hash)
    assert Store.get(store, hash) == {:ok, bytes}
  end

  test "put is idempotent", %{store: store} do
    assert {:ok, hash} = Store.put(store, "same")
    assert {:ok, ^hash} = Store.put(store, "same")
    assert Store.get(store, hash) == {:ok, "same"}
  end

  test "unknown and malformed hashes", %{store: store} do
    assert Store.get(store, Store.hash("never stored")) == {:error, :not_found}
    refute Store.has?(store, Store.hash("never stored"))

    for bad <- [
          "nothex",
          String.duplicate("A", 64),
          String.duplicate("a", 63),
          "../../etc/passwd"
        ] do
      assert Store.get(store, bad) == {:error, :invalid_hash}
      assert_raise ArgumentError, fn -> Store.path_for(store, bad) end
    end
  end

  test "blobs live at <root>/<2 hex>/<62 hex> and nothing else is left behind", %{store: store} do
    hashes = for i <- 1..20, do: elem(Store.put(store, "blob #{i}"), 1)

    files =
      store.root
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, store.root))
      |> Enum.sort()

    expected =
      hashes |> Enum.map(&(binary_part(&1, 0, 2) <> "/" <> binary_part(&1, 2, 62))) |> Enum.sort()

    assert files == expected

    [hash | _] = hashes

    assert Store.path_for(store, hash) ==
             Path.join([store.root, binary_part(hash, 0, 2), binary_part(hash, 2, 62)])
  end

  test "a tampered blob reads as corrupt", %{store: store} do
    {:ok, hash} = Store.put(store, "original bytes")
    File.write!(Store.path_for(store, hash), "tampered bytes")
    assert Store.get(store, hash) == {:error, :corrupt}
  end

  test "concurrent puts of the same bytes all agree", %{store: store} do
    bytes = :crypto.strong_rand_bytes(100_000)

    results =
      1..16
      |> Task.async_stream(fn _ -> Store.put(store, bytes) end, max_concurrency: 16)
      |> Enum.map(fn {:ok, result} -> result end)
      |> Enum.uniq()

    assert results == [{:ok, Store.hash(bytes)}]
    assert Store.get(store, Store.hash(bytes)) == {:ok, bytes}
  end

  test "reopening sees earlier blobs", %{store: store} do
    {:ok, hash} = Store.put(store, "durable")
    {:ok, again} = Store.open(store.root)
    assert Store.get(again, hash) == {:ok, "durable"}
  end
end
