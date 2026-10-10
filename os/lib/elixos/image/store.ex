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
  def open(root) do
    case File.mkdir_p(root) do
      :ok -> {:ok, %__MODULE__{root: root}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Lowercase hex SHA-256 of `bytes`. Pure."
  @spec hash(binary()) :: hash()
  def hash(bytes) when is_binary(bytes),
    do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @doc "Stores `bytes`; idempotent. Returns its hash."
  @spec put(t(), binary()) :: {:ok, hash()} | {:error, term()}
  def put(%__MODULE__{} = store, bytes) when is_binary(bytes) do
    hash = hash(bytes)
    path = path_for(store, hash)

    # Content-addressed, so an existing blob is already these bytes: writing
    # again would only risk replacing good bytes with a partial file.
    if File.exists?(path) do
      {:ok, hash}
    else
      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- write_atomic(path, bytes) do
        {:ok, hash}
      end
    end
  end

  @spec get(t(), String.t()) :: {:ok, binary()} | {:error, :not_found | :corrupt | :invalid_hash}
  def get(%__MODULE__{} = store, hash) do
    case validate(hash) do
      :error ->
        {:error, :invalid_hash}

      :ok ->
        case File.read(path_for(store, hash)) do
          {:ok, bytes} -> if hash(bytes) == hash, do: {:ok, bytes}, else: {:error, :corrupt}
          {:error, :enoent} -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec has?(t(), String.t()) :: boolean()
  def has?(%__MODULE__{} = store, hash) do
    validate(hash) == :ok and File.regular?(path_for(store, hash))
  end

  @doc "Where the blob for `hash` lives. Raises `ArgumentError` for a malformed hash."
  @spec path_for(t(), String.t()) :: Path.t()
  def path_for(%__MODULE__{} = store, hash) do
    case validate(hash) do
      :ok -> Path.join([store.root, binary_part(hash, 0, 2), binary_part(hash, 2, 62)])
      :error -> raise ArgumentError, "not a blob hash: #{inspect(hash)}"
    end
  end

  # A hash is a lowercase hex SHA-256: hex digits ours, nothing to escape, no
  # path separators, so it can safely become a path.
  defp validate(hash)
       when is_binary(hash) and byte_size(hash) == 64 do
    if match?({:ok, _}, Base.decode16(hash, case: :lower)), do: :ok, else: :error
  end

  defp validate(_hash), do: :error

  # Temporary file, fsync, rename: a crash leaves the whole blob or nothing,
  # and a unique temporary name keeps concurrent puts of the same bytes from
  # writing over each other.
  defp write_atomic(path, bytes) do
    tmp = "#{path}.#{:erlang.unique_integer([:positive])}.tmp"

    with {:ok, file} <- :file.open(tmp, [:write, :raw, :binary]),
         :ok <- :file.write(file, bytes),
         :ok <- :file.sync(file),
         :ok <- :file.close(file),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      error ->
        File.rm(tmp)
        error
    end
  end
end
