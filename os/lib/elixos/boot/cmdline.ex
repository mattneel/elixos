defmodule Elixos.Boot.Cmdline do
  @moduledoc """
  BEAM-side reading of the kernel command line (docs/PROTOCOL.md §5).

  The shim parses its own `elixos.*` settings in Zig. A few settings belong to
  the BEAM side, such as `elixos.commit_after=<seconds>`; this module reads
  those from `/proc/cmdline`.

  `parse/1` returns a map of `elixos.*` keys without the prefix. A bare flag
  maps to `true`, `key=value` maps to the string value, the last occurrence
  wins, and every token not starting with `elixos.` is ignored.
  """

  @default_commit_after_ms 30_000

  @spec parse(String.t()) :: %{optional(String.t()) => String.t() | true}
  def parse(text) when is_binary(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce(%{}, fn token, settings ->
      case String.split(token, "=", parts: 2) do
        ["elixos." <> key] -> put(settings, key, true)
        ["elixos." <> key, value] -> put(settings, key, value)
        # Everything else belongs to the kernel, and "elixos." alone is not a
        # key: both are ignored.
        _ -> settings
      end
    end)
  end

  defp put(settings, "", _value), do: settings
  defp put(settings, key, value), do: Map.put(settings, key, value)

  @doc """
  Milliseconds of healthy uptime before auto-commit. From `elixos.commit_after`
  (seconds, canonical decimal, at least 1); otherwise #{@default_commit_after_ms}.
  """
  @spec commit_after_ms(map()) :: pos_integer()
  def commit_after_ms(settings) when is_map(settings) do
    # A bare flag, a non-canonical number or a zero all mean "use the default":
    # this setting must never bring the commit deadline to zero.
    with value when is_binary(value) <- Map.get(settings, "commit_after"),
         {:ok, seconds} when seconds >= 1 <- Elixos.Decimal.parse_u32(value) do
      seconds * 1_000
    else
      _ -> @default_commit_after_ms
    end
  end

  @doc "Reads and parses `/proc/cmdline`; `%{}` when it does not exist (dev host)."
  @spec current() :: map()
  def current do
    case File.read("/proc/cmdline") do
      {:ok, text} -> parse(text)
      {:error, _} -> %{}
    end
  end
end
