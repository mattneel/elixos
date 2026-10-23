defmodule Elixos.Image.Generation do
  @moduledoc """
  A generation: an immutable manifest of what to load at boot (docs/ARCHITECTURE.md §4.4).

  Generation 0 is the factory image in the initramfs and is never written to
  disk. Saved generations are numbered from 1, live in one directory as
  `<n>.gen`, and are never rewritten once saved.

  File format: `:erlang.term_to_binary({:elixos_generation, 1, map})`, where
  `map` holds the struct's fields. Anything else on read is `{:error, :corrupt}`.
  Writes are atomic (temporary file, fsync, rename, fsync of the directory).

  `coproc` is the store hash of the coprocessor bundle the generation carries
  (M29, ADR-099), or `nil`: an AtomVM archive, stored and sealed like a
  module's bytes but never loaded into this VM. Manifests written before M29
  have no such key and read as `nil`.
  """

  defstruct number: nil,
            parent: 0,
            modules: %{},
            boot: [],
            created_at: nil,
            provenance: nil,
            coproc: nil

  @type t :: %__MODULE__{
          number: pos_integer(),
          parent: non_neg_integer(),
          modules: %{module() => Elixos.Image.Store.hash()},
          boot: [{module(), atom(), list()}],
          created_at: DateTime.t() | nil,
          provenance: map() | nil,
          coproc: Elixos.Image.Store.hash() | nil
        }

  @spec write(Path.t(), t()) :: :ok | {:error, :reserved | :exists | term()}
  def write(_dir, %__MODULE__{number: 0}), do: {:error, :reserved}

  def write(dir, %__MODULE__{} = generation) do
    path = path(dir, generation.number)

    # Immutable once saved: a generation number is never reused, so recovery
    # can trust that what it reads is what booted.
    if File.exists?(path) do
      {:error, :exists}
    else
      with :ok <- File.mkdir_p(dir),
           :ok <- write_atomic(dir, path, generation) do
        :ok
      end
    end
  end

  @spec read(Path.t(), non_neg_integer()) :: {:ok, t()} | {:error, :not_found | :corrupt}
  def read(dir, number) do
    case File.read(path(dir, number)) do
      {:ok, bytes} -> decode(bytes)
      {:error, :enoent} -> {:error, :not_found}
      {:error, _reason} -> {:error, :corrupt}
    end
  end

  @doc "Saved generation numbers, ascending. The factory (0) is not listed."
  @spec list(Path.t()) :: [pos_integer()]
  def list(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.flat_map(fn entry ->
          case Integer.parse(entry) do
            {number, ".gen"} when number > 0 -> [number]
            _ -> []
          end
        end)
        |> Enum.sort()

      {:error, _reason} ->
        []
    end
  end

  @doc "One more than the highest saved generation, or 1."
  @spec next_number(Path.t()) :: pos_integer()
  def next_number(dir) do
    case list(dir) do
      [] -> 1
      numbers -> Enum.max(numbers) + 1
    end
  end

  @spec path(Path.t(), non_neg_integer()) :: Path.t()
  def path(dir, number), do: Path.join(dir, "#{number}.gen")

  @doc "Module-level differences between two generations, each list sorted."
  @spec diff(t(), t()) :: %{added: [module()], removed: [module()], changed: [module()]}
  def diff(%__MODULE__{} = old, %__MODULE__{} = new) do
    old_modules = Map.keys(old.modules)
    new_modules = Map.keys(new.modules)

    added = Enum.sort(new_modules -- old_modules)
    removed = Enum.sort(old_modules -- new_modules)

    changed =
      old_modules
      |> Enum.reject(&(&1 in removed))
      |> Enum.filter(&(old.modules[&1] != new.modules[&1]))
      |> Enum.sort()

    %{added: added, removed: removed, changed: changed}
  end

  defp decode(bytes) do
    case decode_term(bytes) do
      {:ok, {:elixos_generation, 1, map}} when is_map(map) -> {:ok, struct(__MODULE__, map)}
      _ -> {:error, :corrupt}
    end
  end

  # Not `binary_to_term/2` with `:safe`: these records name modules, and the
  # reader is a fresh boot, where those atoms do not exist yet — `:safe`
  # refuses to create atoms, so every module record would read as damage and a
  # saved generation could never be loaded by the boot that needs it (M6).
  # What guards the decoder is the CRC (journal) or the shape check
  # (generation), not the atom table; those bytes are ours.
  defp decode_term(bytes) do
    {:ok, :erlang.binary_to_term(bytes)}
  rescue
    ArgumentError -> :error
  end

  # Temporary file, fsync, rename, fsync of the directory: a reader either sees
  # the whole manifest or no manifest at all, and nothing is left behind.
  defp write_atomic(dir, path, generation) do
    bytes = :erlang.term_to_binary({:elixos_generation, 1, Map.from_struct(generation)})
    tmp = "#{path}.#{:erlang.unique_integer([:positive])}.tmp"

    with {:ok, file} <- :file.open(tmp, [:write, :raw, :binary]),
         :ok <- :file.write(file, bytes),
         :ok <- :file.sync(file),
         :ok <- :file.close(file),
         :ok <- File.rename(tmp, path),
         # The rename itself has to reach the disk, so the directory is
         # fsynced too: :file needs the :directory flag to open one at all.
         {:ok, dir_file} <- :file.open(dir, [:read, :directory]),
         :ok <- :file.sync(dir_file),
         :ok <- :file.close(dir_file) do
      :ok
    else
      error ->
        File.rm(tmp)
        error
    end
  end
end
