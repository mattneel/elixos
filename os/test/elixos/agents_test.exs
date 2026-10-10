defmodule Elixos.AgentsTest do
  @moduledoc """
  Agents as ordinary Elixos code (M15): start one, it is recorded; what it
  remembers is written on `/priv`; a boot starts it again with that memory;
  stopping it forgets it. This is the plain-module half of the contract - the
  Jido half runs in the M15 QEMU acceptance, where the packages are installed.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 15
  @moduletag :tmp_dir

  alias Elixos.Agents

  defmodule Counter do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, Keyword.get(opts, :snapshot) || 0)
    def bump(pid), do: GenServer.call(pid, :bump)
    def value(pid), do: GenServer.call(pid, :value)
    def snapshot(pid), do: GenServer.call(pid, :value)

    @impl true
    def init(count), do: {:ok, count}

    @impl true
    def handle_call(:bump, _from, count), do: {:reply, count + 1, count + 1}
    def handle_call(:value, _from, count), do: {:reply, count, count}
  end

  defmodule Quiet do
    use GenServer
    def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok)
    @impl true
    def init(:ok), do: {:ok, :ok}
  end

  setup %{tmp_dir: tmp_dir} do
    priv = Path.join(tmp_dir, "priv")

    previous =
      {Application.get_env(:elixos, :agents_dir), Application.get_env(:elixos, :priv_dir)}

    Application.put_env(:elixos, :agents_dir, Path.join(priv, "agents"))
    Application.put_env(:elixos, :priv_dir, priv)

    {:ok, image} = Elixos.Image.open(priv)
    Process.register(image, Elixos.Image)

    start_supervised!({DynamicSupervisor, name: Elixos.Agents.Supervisor, strategy: :one_for_one})
    start_supervised!({Elixos.Agents, image})

    on_exit(fn ->
      {agents_dir, priv_dir} = previous

      if agents_dir,
        do: Application.put_env(:elixos, :agents_dir, agents_dir),
        else: Application.delete_env(:elixos, :agents_dir)

      if priv_dir,
        do: Application.put_env(:elixos, :priv_dir, priv_dir),
        else: Application.delete_env(:elixos, :priv_dir)
    end)

    %{image: image, priv: priv}
  end

  test "an agent starts, is listed, and is recorded in the image", %{image: image} do
    assert {:ok, pid} = Agents.start(Counter)

    assert Agents.list() == %{"counter" => pid}
    assert Agents.whereis("counter") == pid

    assert Elixos.Image.agents(image) == %{"counter" => %{module: Counter, opts: []}}
  end

  test "what it remembers comes back when it is started again", %{priv: priv} do
    assert {:ok, pid} = Agents.start(Counter)
    assert Counter.bump(pid) == 1
    assert Counter.bump(pid) == 2

    assert :ok = Agents.snapshot("counter")
    assert File.exists?(Path.join([priv, "agents", "counter.term"]))

    # A crash or a power cycle: the record stands, the process is gone, and a
    # restore brings it back with what it remembered.
    assert :ok = DynamicSupervisor.terminate_child(Elixos.Agents.Supervisor, pid)
    assert Agents.whereis("counter") == nil

    assert :ok = Agents.restore()
    assert Counter.value(Agents.whereis("counter")) == 2
  end

  test "snapshot_all writes every running agent", %{priv: priv} do
    assert {:ok, pid} = Agents.start(Counter)
    assert {:ok, quiet} = Agents.start(Quiet, id: "quiet")
    assert Counter.bump(pid) == 1

    assert :ok = Agents.snapshot_all()

    term = File.read!(Path.join([priv, "agents", "counter.term"])) |> :erlang.binary_to_term()
    assert term == 1
    refute File.exists?(Path.join([priv, "agents", "quiet.term"]))
    assert Process.alive?(quiet)
  end

  test "stopping writes the state, stops the agent and forgets it", %{image: image, priv: priv} do
    assert {:ok, pid} = Agents.start(Counter)
    assert Counter.bump(pid) == 1

    assert :ok = Agents.stop("counter")

    refute Process.alive?(pid)
    assert Agents.list() == %{}
    assert Elixos.Image.agents(image) == %{}
    assert File.exists?(Path.join([priv, "agents", "counter.term"]))

    assert :ok = Agents.restore()
    assert Agents.list() == %{}
  end

  test "an agent that is not recorded cannot be stopped" do
    assert Agents.stop("nothing") == {:error, :unknown_agent}
    assert Agents.snapshot("nothing") == {:error, :unknown_agent}
  end
end
