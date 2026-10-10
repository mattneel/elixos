defmodule Elixos.Image.Store do
  @moduledoc """
  Content-addressed blob store for module bytecode (docs/ARCHITECTURE.md §4.2).

  A blob's address is the lowercase hex SHA-256 of its bytes. On disk:

      <root>/<first 2 hex chars>/<remaining 62 hex chars>

  Writes are atomic (temporary file, fsync, rename), so a crash leaves either
  the whole blob or nothing, and no temporary files survive a successful `put/2`.
  Reads verify the hash, so bit rot and tampering surface as `{:error, :corrupt}`.
  """

  defstruct [:root]

  @type t :: %__MODULE__{root: Path.t()}
  @type hash :: <<_::512>>

  @doc "Opens (creating if needed) the store rooted at `root`."
  @spec open(Path.t()) :: {:ok, t()} | {:error, term()}
  def open(root), do: Elixos.NotImplemented.raise!(6, "Elixos.Image.Store.open/1 #{root}")

  @doc "Lowercase hex SHA-256 of `bytes`. Pure."
  @spec hash(binary()) :: hash()
  def hash(bytes) when is_binary(bytes),
    do: Elixos.NotImplemented.raise!(6, "Elixos.Image.Store.hash/1")

  @doc "Stores `bytes`; idempotent. Returns its hash."
  @spec put(t(), binary()) :: {:ok, hash()} | {:error, term()}
  def put(%__MODULE__{} = store, bytes) when is_binary(bytes) do
    _ = store
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Store.put/2")
  end

  @spec get(t(), String.t()) :: {:ok, binary()} | {:error, :not_found | :corrupt | :invalid_hash}
  def get(%__MODULE__{} = store, hash) do
    _ = {store, hash}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Store.get/2")
  end

  @spec has?(t(), String.t()) :: boolean()
  def has?(%__MODULE__{} = store, hash) do
    _ = {store, hash}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Store.has?/2")
  end

  @doc "Where the blob for `hash` lives. Raises `ArgumentError` for a malformed hash."
  @spec path_for(t(), String.t()) :: Path.t()
  def path_for(%__MODULE__{} = store, hash) do
    _ = {store, hash}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Store.path_for/2")
  end
end
