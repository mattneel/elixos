defmodule Elixos.Image do
  @moduledoc """
  The live image: store + journal + generations (docs/ARCHITECTURE.md §4).

  There is no heap snapshot on the BEAM, so the image is code plus data plus a
  boot spec, rebuilt into a running system at boot (ADR-005). Layout under `root`:

      root/store/          Elixos.Image.Store blobs
      root/journal.log     Elixos.Image.Journal
      root/generations/    Elixos.Image.Generation manifests (<n>.gen)

  The *working set* is the latest recorded hash of every module that has not
  been forgotten, rebuilt by replaying the journal on `open/1`. `save/2` turns
  the working set into a new generation.
  """

  @type t :: pid()

  @spec open(Path.t()) :: {:ok, t()} | {:error, term()}
  def open(root), do: Elixos.NotImplemented.raise!(6, "Elixos.Image.open/1 #{root}")

  @doc "Stores `bytecode`, journals `{:module, module, hash}`, updates the working set."
  @spec record(t(), module(), binary()) :: {:ok, Elixos.Image.Store.hash()} | {:error, term()}
  def record(image, module, bytecode) do
    _ = {image, module, bytecode}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.record/3")
  end

  @doc "Journals `{:forget, module}` and drops it from the working set."
  @spec forget(t(), module()) :: :ok | {:error, term()}
  def forget(image, module) do
    _ = {image, module}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.forget/2")
  end

  @spec modules(t()) :: %{module() => Elixos.Image.Store.hash()}
  def modules(image) do
    _ = image
    Elixos.NotImplemented.raise!(6, "Elixos.Image.modules/1")
  end

  @doc """
  Writes the working set as generation `Generation.next_number/1`, with parent
  the previous highest generation (0 if none), and journals `{:generation, n}`.
  Options: `boot: [{module, function, args}]`.
  """
  @spec save(t(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def save(image, opts \\ []) do
    _ = {image, opts}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.save/2")
  end

  @doc "Loads every module of generation `n` into the VM."
  @spec restore(t(), non_neg_integer()) ::
          {:ok, [module()]} | {:error, :not_found | {:missing_blob, module()} | term()}
  def restore(image, n) do
    _ = {image, n}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.restore/2")
  end

  @doc """
  Modules in the working set that are absent from generation `n` or differ
  from it (unsaved changes), sorted. Generation 0, the factory, holds no user
  modules, so against it every recorded module is unsaved.
  """
  @spec unsaved(t(), non_neg_integer()) :: [module()]
  def unsaved(image, n) do
    _ = {image, n}
    Elixos.NotImplemented.raise!(7, "Elixos.Image.unsaved/2")
  end

  @doc "Loads the working-set versions of `modules` into the VM."
  @spec recover(t(), [module()]) :: {:ok, [module()]} | {:error, term()}
  def recover(image, modules) do
    _ = {image, modules}
    Elixos.NotImplemented.raise!(7, "Elixos.Image.recover/2")
  end

  @spec close(t()) :: :ok
  def close(image) do
    _ = image
    Elixos.NotImplemented.raise!(6, "Elixos.Image.close/1")
  end
end
