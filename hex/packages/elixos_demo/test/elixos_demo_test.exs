defmodule ElixosDemoTest do
  use ExUnit.Case, async: true

  alias ElixosDemo.{Journal, Reading}

  @moduletag :tmp_dir
  @moduletag milestone: 27

  test "portable reading validation normalizes labels without inventing values" do
    assert Reading.new(" room_celsius ", -2.5, 123) ==
             {:ok, %{label: "room_celsius", value: -2.5, recorded_at: 123}}

    assert Reading.new("  ", 1, 123) == {:error, :invalid_reading}
    assert Reading.new("room", "21", 123) == {:error, :invalid_reading}
    assert Reading.new("room", 21, -1) == {:error, :invalid_reading}
  end

  test "host build has no OS-only module, OS process or invented observation" do
    refute Code.ensure_loaded?(ElixosDemo.OS)
    refute :elixos in Enum.map(Application.started_applications(), &elem(&1, 0))
    assert ElixosDemo.os_info() == {:error, :elixos_target_required}
    assert Application.fetch_env!(:elixos_demo, :target) == :host
  end

  test "readings and shared summaries survive a supervised service restart", %{tmp_dir: directory} do
    options = [name: nil, state_dir: directory]
    journal = start_supervised!({Journal, options})
    assert Journal.summary(journal) == %{count: 0, min: nil, max: nil, mean: nil}
    assert {:ok, room} = Journal.record(journal, "room_celsius", 21.5, 100)
    assert {:ok, outside} = Journal.record(journal, "outside_celsius", 8, 101)
    assert {:ok, warmer} = Journal.record(journal, "room_celsius", 22, 102)
    assert Journal.readings(journal) == [room, outside, warmer]

    assert Journal.summary(journal, "room_celsius") == %{
             count: 2,
             min: 21.5,
             max: 22,
             mean: 21.75
           }

    assert File.regular?(Path.join(directory, "readings.etf"))
    stop_supervised!(Journal)
    restored = start_supervised!({Journal, options})
    assert Journal.readings(restored) == [room, outside, warmer]
    assert Journal.summary(restored) == ElixosDemoStats.summarize([21.5, 8, 22])
    assert Journal.record(restored, "room", :not_a_number, 103) == {:error, :invalid_reading}
    assert Journal.readings(restored) == [room, outside, warmer]
  end

  test "durable readings survive a fresh VM, not only a service restart", %{tmp_dir: directory} do
    journal = start_supervised!({Journal, name: nil, state_dir: directory})
    assert {:ok, reading} = Journal.record(journal, "room_celsius", 21.5, 123)
    stop_supervised!(Journal)

    program = """
    {:ok, journal} = ElixosDemo.Journal.start_link(state_dir: hd(System.argv()), name: nil)
    journal |> ElixosDemo.Journal.readings() |> :erlang.term_to_binary() |> Base.encode64() |> IO.write()
    """

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map([Journal, ElixosDemoStats], fn module ->
          ["-pa", module |> :code.which() |> to_string() |> Path.dirname()]
        end) ++ ["-e", program, directory]

    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output |> Base.decode64!() |> :erlang.binary_to_term([:safe]) == [reading]
  end

  test "a failed filesystem write does not acknowledge or change the journal", %{
    tmp_dir: directory
  } do
    journal = start_supervised!({Journal, name: nil, state_dir: directory})
    assert {:ok, reading} = Journal.record(journal, "room", 20, 100)
    File.mkdir!(Path.join(directory, "readings.etf.tmp"))

    assert {:error, :eisdir} = Journal.record(journal, "room", 21, 101)
    assert Journal.readings(journal) == [reading]
    assert Journal.summary(journal) == ElixosDemoStats.summarize([20])
  end

  test "corrupt or structurally invalid state is rejected instead of discarded", %{
    tmp_dir: directory
  } do
    path = Path.join(directory, "readings.etf")
    File.write!(path, "not an Erlang term")
    assert GenServer.start(Journal, state_dir: directory) == {:error, :invalid_readings_state}

    File.write!(path, :erlang.term_to_binary({:elixos_demo_readings, 1, [%{label: "bad"}]}))
    assert GenServer.start(Journal, state_dir: directory) == {:error, :invalid_readings_state}
  end
end
