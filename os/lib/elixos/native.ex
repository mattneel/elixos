defmodule Elixos.Native do
  @moduledoc """
  Evidence-based native tool hot paths (M24, docs/ROADMAP.md, ADR-050).

  Only pure Zigler work is eligible. Promotion requires identical recorded
  OMP differential results and strictly lower concurrent dispatcher p99,
  including conversion overhead. Synchronous NIF work must be bounded well
  below 1 ms; longer work needs dirty/threaded execution with admission limits.
  Unproven NIFs run only in the supervised peer, never the main VM.

  `Elixos.Image.save/2` persists the exact `library_pins/0` values in its
  generation manifest's `native_libraries` field; `Elixos.Image.restore/2`
  verifies those files and restores the pins. Each byte-distinct library has
  a distinct content-addressed filename, with its actual SHA-256, target and
  toolchain recorded. Dispatcher reversion changes neither environment nor
  pins.

  Reference-validation limit: M21 has not recorded the per-tool OMP 18.8.7
  fixtures yet, and no M24 implementation has validated these contracts.
  All functions remain loud milestone stubs, not native implementations.
  """

  @type implementation :: :quickbeam | :native
  @type benchmark :: %{
          implementation: implementation(),
          p50: number(),
          p99: number(),
          runs: pos_integer()
        }
  @type library_pin :: %{
          file: String.t(),
          sha256: String.t(),
          target: String.t(),
          toolchain: String.t()
        }

  @doc "The measured pure tool functions eligible for native promotion."
  @spec candidates() :: [%{tool: String.t(), function: atom()}]
  def candidates, do: Elixos.NotImplemented.raise!(24, "Elixos.Native.candidates/0")

  @doc """
  Measures a tool through `Elixos.Toolset.call/3`, including conversion and
  dispatch overhead. Options select `:implementation`, sixteen concurrent
  `:sessions` and the number of measured `:runs`; p50 and p99 use the same
  latency unit. Promotion compares paired rounds on the same recorded
  workload after discarded warmup, never only the native function's runtime.
  """
  @spec benchmark(String.t(), keyword()) :: benchmark()
  def benchmark(_tool, _opts), do: Elixos.NotImplemented.raise!(24, "Elixos.Native.benchmark/2")

  @doc "Promotes a pure Zigler hot path only after exact differential results and a strict p99 win."
  @spec promote(String.t()) :: :ok | {:error, term()}
  def promote(_tool), do: Elixos.NotImplemented.raise!(24, "Elixos.Native.promote/1")

  @doc "Reverts the next tool call to QuickBEAM without changing the generation's library pins."
  @spec revert(String.t()) :: :ok
  def revert(_tool), do: Elixos.NotImplemented.raise!(24, "Elixos.Native.revert/1")

  @doc "Runs an unproven native function in the peer, reporting peer failure to its caller."
  @spec run_in_peer(module(), atom(), list()) :: {:ok, term()} | {:error, :tool_host_down}
  def run_in_peer(_module, _fun, _args),
    do: Elixos.NotImplemented.raise!(24, "Elixos.Native.run_in_peer/3")

  @doc """
  The generation's exact native library pins, including libraries retained
  after dispatcher reversion. Every lowercase SHA-256 follows the
  `Elixos.Image.Store` convention and hashes actual library bytes; distinct
  hashes cannot share or overwrite a filename.
  """
  @spec library_pins() :: [library_pin()]
  def library_pins, do: Elixos.NotImplemented.raise!(24, "Elixos.Native.library_pins/0")

  @doc """
  Stages an already-built native library under its content-addressed filename
  and retains its pin in the image working set for the next
  `Elixos.Image.save/2`, using the existing image persistence conventions.
  Required options are `:target` and `:toolchain`. The SHA-256 is computed from
  the actual file, not supplied by the caller. Byte-distinct versions coexist
  without replacing a previously pinned file. This is artifact packaging,
  not proof of a valid NIF ABI or promotion evidence, and it never loads code
  into the main VM.
  """
  @spec pin_library(Path.t(), keyword()) :: {:ok, library_pin()} | {:error, term()}
  def pin_library(_source, _opts),
    do: Elixos.NotImplemented.raise!(24, "Elixos.Native.pin_library/2")
end
