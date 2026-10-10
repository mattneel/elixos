defmodule Elixos.REPLTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 9

  alias Elixos.REPL

  test "IEx and erl are always available; the list is sorted" do
    available = REPL.available()
    assert :iex in available
    assert :erl in available
    assert available == Enum.sort(available)
  end

  test "gsh is listed only when it is installed" do
    assert :gsh in REPL.available() == Code.ensure_loaded?(:gsh)
  end

  test "each REPL is an MFA that starts a shell and returns its pid (OTP's contract)" do
    assert REPL.mfa(:erl) == {:ok, {:shell, :start, []}}

    assert {:ok, {module, function, args}} = REPL.mfa(:iex)
    assert Code.ensure_loaded?(module)

    assert function_exported?(module, function, length(args)),
           "#{inspect(module)}.#{function}/#{length(args)}"
  end

  test "unknown and missing REPLs" do
    assert REPL.mfa(:bash) == {:error, :unknown_repl}
    assert REPL.mfa(:sh) == {:error, :unknown_repl}

    unless Code.ensure_loaded?(:gsh) do
      assert REPL.mfa(:gsh) == {:error, :unavailable}
    end
  end

  test "the default login REPL is IEx" do
    assert REPL.default() == :iex
  end
end
