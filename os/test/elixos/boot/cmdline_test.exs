defmodule Elixos.Boot.CmdlineTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 5

  alias Elixos.Boot.Cmdline

  test "keeps only elixos.* tokens, without the prefix" do
    assert Cmdline.parse("console=ttyS0 panic=-1 elixos.commit_after=5 elixos.safe quiet\n") ==
             %{"commit_after" => "5", "safe" => true}
  end

  test "the last occurrence wins" do
    assert Cmdline.parse("elixos.commit_after=5 elixos.commit_after=9") == %{
             "commit_after" => "9"
           }
  end

  test "tolerates repeated spaces and an empty line" do
    assert Cmdline.parse("  elixos.x=1   \n") == %{"x" => "1"}
    assert Cmdline.parse("") == %{}
  end

  test "commit_after_ms defaults to 30 s and honors valid elixos.commit_after" do
    assert Cmdline.commit_after_ms(%{}) == 30_000
    assert Cmdline.commit_after_ms(%{"commit_after" => "2"}) == 2_000

    for bad <- ["0", "-1", "07", "abc", "1.5", true] do
      assert Cmdline.commit_after_ms(%{"commit_after" => bad}) == 30_000
    end
  end
end
