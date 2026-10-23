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

  @doc """
  The image profile (ADR-111) from `elixos.profile`: `:deck` for exactly
  `deck`, otherwise `:full`. The shim refuses any other value; a bare flag or
  garbage that reaches the BEAM anyway is the default, the full machine.
  Defaults to the running kernel's command line.
  """
  @spec profile(map()) :: :full | :deck
  def profile(settings \\ current()) when is_map(settings) do
    case Map.get(settings, "profile") do
      "deck" -> :deck
      _full_or_invalid -> :full
    end
  end

  @doc """
  Whether the shim selected RAM-backed Live storage. Like its boolean parser,
  the last valid bare/1/0 flag wins; malformed values do not reset the choice.
  Defaults to the running kernel's command line.
  """
  @spec live?(String.t()) :: boolean()
  def live?(text \\ cmdline()) when is_binary(text) do
    text
    |> String.split()
    |> Enum.reduce(false, fn
      flag, _ when flag in ["elixos.live", "elixos.live=1"] -> true
      "elixos.live=0", _ -> false
      _, enabled -> enabled
    end)
  end

  @doc "Reads `/proc/cmdline`; containers ignore their host's boot configuration."
  @spec current() :: map()
  def current, do: parse(cmdline())

  defp cmdline do
    if Elixos.Boot.runtime() == :container do
      ""
    else
      case File.read("/proc/cmdline") do
        {:ok, text} -> text
        {:error, _} -> ""
      end
    end
  end
end
