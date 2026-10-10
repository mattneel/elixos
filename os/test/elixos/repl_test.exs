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

  test "a language's shell is listed only when its modules are installed" do
    # gsh (Gleam), LFE and Clojerl arrive as packages; until one is installed,
    # the registry does not offer it, and an offered REPL always has a
    # callable entry point.
    assert :gsh in REPL.available() ==
             (Code.ensure_loaded?(:gsh) and function_exported?(:gsh, :start, 0))

    assert :lfe in REPL.available() ==
             (Code.ensure_loaded?(:lfe_shell) and function_exported?(:lfe_shell, :start, 0))

    assert :clojerl in REPL.available() ==
             (Code.ensure_loaded?(:clojerl) and function_exported?(:clojerl, :start, 0))

    for name <- REPL.available(), name not in [:iex, :erl] do
      assert {:ok, {m, f, a}} = REPL.mfa(name)
      assert function_exported?(m, f, length(a)), "offered #{name} without a callable entry"
    end
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
