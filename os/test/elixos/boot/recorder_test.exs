defmodule Elixos.Boot.RecorderTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 7
  @moduletag :tmp_dir

  alias Elixos.Boot.Recorder

  # The recorder is a process, and its tracer is a plain function, so this
  # test *is* the recorder: registering the test process under its name lets
  # a cast land in the mailbox where it can be inspected.
  setup do
    Process.register(self(), Elixos.Boot.Recorder)
    :ok
  end

  test "records a module definition" do
    {_, _, [{mod, bytecode}]} =
      Elixos.Image.Capture.eval("defmodule RecorderTest.Defined do\n  def hi, do: :ok\nend")

    assert :ok = Recorder.trace({:on_module, bytecode, :none}, %{})
    assert_receive {:"$gen_cast", {:record, ^mod, ^bytecode}}
  end

  # A REPL slip that tries to replace a base module still reaches the tracer:
  # the compiler traces it and only the *load* is refused, so without this
  # guard the base's replacement would be journaled and the next save would
  # write a generation that cannot boot.
  test "ignores bytecode for a sticky (base) module" do
    # Boot sticks the code path; this test does it for the directory Enum
    # lives in, and unsticks it again so the rest of the suite is unaffected.
    dir = :code.which(Enum) |> to_string() |> Path.dirname()
    :ok = :code.stick_dir(String.to_charlist(dir))

    try do
      beam = File.read!(:code.which(Enum) |> to_string())

      assert :ok = Recorder.trace({:on_module, beam, :none}, %{})
      refute_receive {:"$gen_cast", {:record, Enum, _bytecode}}, 50
    after
      :code.unstick_dir(String.to_charlist(dir))
    end
  end
end
