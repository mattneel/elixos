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
    Elixos.NotImplemented.raise!(5, "Elixos.Boot.Cmdline.parse/1")
  end

  @doc """
  Milliseconds of healthy uptime before auto-commit. From `elixos.commit_after`
  (seconds, canonical decimal, at least 1); otherwise #{@default_commit_after_ms}.
  """
  @spec commit_after_ms(map()) :: pos_integer()
  def commit_after_ms(settings) when is_map(settings) do
    Elixos.NotImplemented.raise!(5, "Elixos.Boot.Cmdline.commit_after_ms/1")
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
