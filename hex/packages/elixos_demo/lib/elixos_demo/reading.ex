defmodule ElixosDemo.Reading do
  @moduledoc "Portable measurement validation, independent of processes, files and the OS."

  @type t :: %{label: String.t(), value: number(), recorded_at: non_neg_integer()}

  @doc "Builds a labelled numeric observation with an explicit millisecond timestamp."
  @spec new(term(), term(), term()) :: {:ok, t()} | {:error, :invalid_reading}
  def new(label, value, recorded_at)
      when is_binary(label) and is_number(value) and is_integer(recorded_at) and recorded_at >= 0 do
    label = String.trim(label)

    if label == "" do
      {:error, :invalid_reading}
    else
      {:ok, %{label: label, value: value, recorded_at: recorded_at}}
    end
  end

  def new(_label, _value, _recorded_at), do: {:error, :invalid_reading}

  @doc false
  def valid?(%{label: label, value: value, recorded_at: recorded_at} = reading)
      when map_size(reading) == 3 do
    new(label, value, recorded_at) == {:ok, reading}
  end

  def valid?(_other), do: false
end
