defmodule @MODULE@Test do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  test "portable arithmetic has no OS dependency" do
    assert @MODULE@.advance(3, 4) == 7
    refute :elixos in Enum.map(Application.started_applications(), &elem(&1, 0))
  end

  test "the supervised counter restores a successful write", %{tmp_dir: directory} do
    options = [name: nil, state_dir: directory]
    counter = start_supervised!({@MODULE@.Counter, options})
    assert @MODULE@.Counter.value(counter) == 0
    assert @MODULE@.Counter.increment(counter, 7) == {:ok, 7}
    assert File.read!(Path.join(directory, "counter")) == "7"

    stop_supervised!(@MODULE@.Counter)
    restored = start_supervised!({@MODULE@.Counter, options})
    assert @MODULE@.Counter.value(restored) == 7
  end
end
