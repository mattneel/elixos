defmodule ElixosDemo.Journal do
  @moduledoc """
  Serializes reading updates and writes a versioned file before acknowledging them.

  The file is in the configured stable state directory, never an installed
  `priv` directory. An unreadable or malformed existing file stops startup;
  it is not silently replaced by empty state. Write failures leave in-memory
  state unchanged and are returned to the caller.
  """
  use GenServer

  alias ElixosDemo.Reading

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  def record(server, label, value, recorded_at \\ System.system_time(:millisecond)) do
    with {:ok, reading} <- Reading.new(label, value, recorded_at) do
      GenServer.call(server, {:record, reading})
    end
  end

  def readings(server), do: GenServer.call(server, :readings)
  def summary(server, label \\ :all), do: GenServer.call(server, {:summary, label})

  @impl true
  def init(options) do
    directory =
      Keyword.get_lazy(options, :state_dir, fn ->
        Application.fetch_env!(:elixos_demo, :state_dir)
      end)

    path = Path.join(directory, "readings.etf")

    with :ok <- File.mkdir_p(directory),
         {:ok, readings} <- load(path) do
      {:ok, %{path: path, readings: readings}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:record, reading}, _from, state) do
    readings = [reading | state.readings]

    case persist(state.path, readings) do
      :ok -> {:reply, {:ok, reading}, %{state | readings: readings}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:readings, _from, state) do
    {:reply, Enum.reverse(state.readings), state}
  end

  def handle_call({:summary, label}, _from, state) do
    values =
      for reading <- state.readings, label == :all or reading.label == label, do: reading.value

    {:reply, ElixosDemoStats.summarize(values), state}
  end

  defp persist(path, readings) do
    temporary = path <> ".tmp"
    bytes = :erlang.term_to_binary({:elixos_demo_readings, 1, readings})

    with :ok <- File.write(temporary, bytes, [:write, :sync]),
         :ok <- File.rename(temporary, path) do
      :ok
    end
  end

  defp load(path) do
    case File.read(path) do
      {:ok, bytes} -> decode(bytes)
      {:error, :enoent} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(bytes) do
    # :safe rejects unknown schema atoms on a fresh VM before validation.
    Code.ensure_loaded!(Reading)

    case :erlang.binary_to_term(bytes, [:safe]) do
      {:elixos_demo_readings, 1, readings} when is_list(readings) ->
        if Enum.all?(readings, &Reading.valid?/1),
          do: {:ok, readings},
          else: {:error, :invalid_readings_state}

      _other ->
        {:error, :invalid_readings_state}
    end
  rescue
    ArgumentError -> {:error, :invalid_readings_state}
  end
end
