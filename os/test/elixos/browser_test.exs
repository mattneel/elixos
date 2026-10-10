defmodule Elixos.BrowserTest do
  @moduledoc """
  How the adapter starts (M18): the pinned manifest decides the argv - a
  musl-clean binary is exec'd directly, a glibc one through its private
  loader, both directly as ports (ADR-012: no shell). The running adapter is
  the M18 QEMU acceptance's business.
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 18

  alias Elixos.Browser

  @binary "/system/browser/lightpanda"

  test "a musl-clean adapter runs as itself" do
    manifest = %{"binary" => @binary, "args" => ["serve", "--port", "9222"]}

    assert {:ok, [@binary, "serve", "--port", "9222"]} = Browser.command(manifest)
  end

  test "a glibc adapter runs through its private loader" do
    lib = "/system/browser/glibc"
    ld = lib <> "/ld-linux-x86-64.so.2"

    manifest = %{
      "binary" => @binary,
      "args" => ["serve", "--port", "9222"],
      "loader" => %{"ld" => ld, "lib" => lib}
    }

    assert {:ok, [^ld, "--library-path", ^lib, @binary, "serve", "--port", "9222"]} =
             Browser.command(manifest)
  end

  test "a manifest without a binary is refused" do
    assert {:error, _reason} = Browser.command(%{"args" => ["serve"]})
  end
end
