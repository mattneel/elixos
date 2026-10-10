defmodule Elixos.Image.Generation do
  @moduledoc """
  A generation: an immutable manifest of what to load at boot (docs/ARCHITECTURE.md §4.4).

  Generation 0 is the factory image in the initramfs and is never written to
  disk. Saved generations are numbered from 1, live in one directory as
  `<n>.gen`, and are never rewritten once saved.

  File format: `:erlang.term_to_binary({:elixos_generation, 1, map})`, where
  `map` holds the struct's fields. Anything else on read is `{:error, :corrupt}`.
  Writes are atomic (temporary file, fsync, rename, fsync of the directory).
  """

  defstruct number: nil, parent: 0, modules: %{}, boot: [], created_at: nil

  @type t :: %__MODULE__{
          number: pos_integer(),
          parent: non_neg_integer(),
          modules: %{module() => Elixos.Image.Store.hash()},
          boot: [{module(), atom(), list()}],
          created_at: DateTime.t() | nil
        }

  @spec write(Path.t(), t()) :: :ok | {:error, :reserved | :exists | term()}
  def write(dir, %__MODULE__{} = generation) do
    _ = {dir, generation}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Generation.write/2")
  end

  @spec read(Path.t(), non_neg_integer()) :: {:ok, t()} | {:error, :not_found | :corrupt}
  def read(dir, number) do
    _ = {dir, number}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Generation.read/2")
  end

  @doc "Saved generation numbers, ascending. The factory (0) is not listed."
  @spec list(Path.t()) :: [pos_integer()]
  def list(dir), do: Elixos.NotImplemented.raise!(6, "Elixos.Image.Generation.list/1 #{dir}")

  @doc "One more than the highest saved generation, or 1."
  @spec next_number(Path.t()) :: pos_integer()
  def next_number(dir),
    do: Elixos.NotImplemented.raise!(6, "Elixos.Image.Generation.next_number/1 #{dir}")

  @spec path(Path.t(), non_neg_integer()) :: Path.t()
  def path(dir, number), do: Path.join(dir, "#{number}.gen")

  @doc "Module-level differences between two generations, each list sorted."
  @spec diff(t(), t()) :: %{added: [module()], removed: [module()], changed: [module()]}
  def diff(%__MODULE__{} = old, %__MODULE__{} = new) do
    _ = {old, new}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Generation.diff/2")
  end
end
