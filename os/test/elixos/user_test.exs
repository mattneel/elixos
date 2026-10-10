defmodule Elixos.UserTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 9
  @moduletag :tmp_dir

  alias Elixos.User

  setup %{tmp_dir: tmp_dir}, do: %{path: Path.join(tmp_dir, "user.exs")}

  test "no file means the defaults", %{path: path} do
    assert User.read(path) == {:ok, %{repl: :iex}}
  end

  test "put then read", %{path: path} do
    assert :ok = User.put(path, :repl, :erl)
    assert User.read(path) == {:ok, %{repl: :erl}}
  end

  test "put refuses REPLs that do not exist and leaves the file alone", %{path: path} do
    :ok = User.put(path, :repl, :erl)
    assert User.put(path, :repl, :bash) == {:error, :unknown_repl}
    assert User.read(path) == {:ok, %{repl: :erl}}
  end

  test "unknown keys are ignored on read and preserved by put", %{path: path} do
    File.write!(path, "[repl: :erl, theme: :amber]\n")
    assert User.read(path) == {:ok, %{repl: :erl}}

    :ok = User.put(path, :repl, :iex)
    assert {:ok, saved} = path |> File.read!() |> Code.string_to_quoted()
    assert Keyword.get(saved, :theme) == :amber
    assert Keyword.get(saved, :repl) == :iex
  end

  test "an unknown REPL in the file", %{path: path} do
    File.write!(path, "[repl: :bash]\n")
    assert User.read(path) == {:error, {:invalid, :repl}}
  end

  test "the file is parsed, never evaluated", %{path: path} do
    marker = Path.join(Path.dirname(path), "evaluated")
    File.write!(path, ~s|[repl: (File.write!(#{inspect(marker)}, "x"); :erl)]\n|)
    assert User.read(path) == {:error, :malformed}
    refute File.exists?(marker)

    File.write!(path, "this is not a keyword list")
    assert User.read(path) == {:error, :malformed}
  end
end
