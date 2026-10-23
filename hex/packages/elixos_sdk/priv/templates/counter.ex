defmodule @MODULE@.Counter do
  @moduledoc "Serializes counter writes to a normal file, outside the installed code tree."
  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  def value(server), do: GenServer.call(server, :value)

  def increment(server, amount) when is_integer(amount) and amount > 0 do
    GenServer.call(server, {:increment, amount})
  end

  @impl true
  def init(options) do
    directory = Keyword.get_lazy(options, :state_dir, fn -> Application.fetch_env!(:@APP@, :state_dir) end)
    path = Path.join(directory, "counter")

    with :ok <- File.mkdir_p(directory),
         {:ok, value} <- read(path) do
      {:ok, %{path: path, value: value}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:value, _from, state), do: {:reply, state.value, state}

  def handle_call({:increment, amount}, _from, state) do
    value = @MODULE@.advance(state.value, amount)
    temporary = state.path <> ".tmp"

    with :ok <- File.write(temporary, Integer.to_string(value), [:write, :sync]),
         :ok <- File.rename(temporary, state.path) do
      {:reply, {:ok, value}, %{state | value: value}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Integer.parse(contents) do
          {value, ""} when value >= 0 -> {:ok, value}
          _ -> {:error, :invalid_counter_state}
        end

      {:error, :enoent} -> {:ok, 0}
      {:error, reason} -> {:error, reason}
    end
  end
end
