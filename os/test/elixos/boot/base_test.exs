defmodule Elixos.Boot.BaseTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 7

  alias Elixos.Boot.Base

  # Sticking is per-VM, so this runs in a child VM: sticking this suite's own
  # code path would leave the rest of the suite unable to reload those modules.
  # That child VM is also exactly how boot uses it - once, early, before any
  # generation can load.
  test "every code-path directory is sticky, so no generation can reload the base" do
    script = """
    count = Elixos.Boot.Base.stick()
    beam = File.read!(:code.which(Enum) |> to_string())
    load = inspect(:code.load_binary(Enum, ~c"nofile", beam))

    compiled =
      try do
        Code.eval_string("defmodule Enum do\n  def map(_, _), do: :hijacked\nend")
        "defined"
      rescue
        e -> "raised " <> inspect(e.__struct__)
      end

    IO.puts("stuck=\#{count} load=\#{load} compiled=\#{compiled}")
    IO.puts("still =\#{inspect(Enum.map([1, 2], &(&1 * 2)))}")
    """

    {out, 0} =
      System.cmd(System.find_executable("elixir"), ["-pa", ebin_dir(), "-e", script],
        stderr_to_stdout: true
      )

    # The loader refuses a sticky module outright, with the message the M7
    # acceptance test looks for ("sticky" on the console).
    assert out =~ ~r/stuck=[1-9]\d*/
    assert out =~ "load={:error, :sticky_directory}"
    assert out =~ "that resides in sticky dir"
    # `Code.eval_string` does not raise: the compile succeeds and the *load*
    # is what fails, so Elixir reports it and carries on. Enum is untouched.
    assert out =~ "compiled=defined"
    assert out =~ "still =[2, 4]"
  end

  defp ebin_dir do
    Elixos.Boot.Base |> :code.which() |> to_string() |> Path.dirname()
  end
end
