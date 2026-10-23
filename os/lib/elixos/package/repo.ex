defmodule Elixos.Package.Repo do
  @moduledoc """
  Trusted Hex repositories: the configuration and the consent (ADR-019, M14).

  `/priv/hex/repos.exs` is the whole trust decision: a repository is trusted
  exactly when it appears there, with its public key. An install can therefore
  never trust a repository implicitly — adding it is the consent step, and on a
  single-user machine (ADR-013) that is the only one there is.

      iex> pem = File.read!("/priv/hex/keys/team.pub")
      iex> Elixos.Package.add_repo("team", "/priv/mirrors/team", key: pem)
      :ok
      iex> Elixos.Package.repos()
      [%Elixos.Package.Repo{name: :team, url: "/priv/mirrors/team"}]

  A repository is a static Hex repository (`mix hex.registry build`): `names`,
  `versions`, `packages/<name>` and `tarballs/<name>-<version>.tar`, each
  resource signed, and `public_key` serving the key above. `url` is `http(s)://`
  or a local path (PROTOCOL.md §8, Q8).

  The same key is written to `/priv/hex/keys/<name>.pub`, so trust survives a
  power cycle and can be inspected by hand. Both files are written atomically.
  """

  require Logger

  alias Elixos.Package.Proto

  defstruct [:name, :url, :key]

  @type t :: %__MODULE__{name: atom(), url: String.t(), key: String.t()}

  @type name :: atom()

  @doc "Every trusted repository, in the order they are configured."
  @spec list() :: [t()]
  def list do
    case read() do
      {:ok, repos} ->
        repos

      {:error, reason} ->
        Logger.error("hex: repositories unreadable (#{inspect(reason)}); none is trusted")
        []
    end
  end

  @doc "One repository, or `{:error, :unknown_repo}`."
  @spec get(name()) :: {:ok, t()} | {:error, :unknown_repo}
  def get(name) do
    case Enum.find(list(), &(&1.name == name)) do
      nil -> {:error, :unknown_repo}
      repo -> {:ok, repo}
    end
  end

  @doc """
  Adds `name` with `url` and its public key (`key:`, PEM), or refuses it.

  The key is used as given: `Repo` never fetches one from `url` on its own. A
  wrong key (not PEM, not RSA) is `{:error, :bad_key}`; an existing name is
  replaced only by `replace: true`.
  """
  @spec add(name(), String.t(), keyword()) :: :ok | {:error, term()}
  def add(name, url, opts \\ []) do
    key = Keyword.get(opts, :key)
    replace? = Keyword.get(opts, :replace, false)

    with {:ok, _record} <- decode_key(key),
         {:ok, pairs} <- read_pairs(),
         :ok <- check_configured(pairs, name, replace?),
         :ok <- write_key(name, key) do
      write_repos(Keyword.put(pairs, name, url: url, key: key))
    end
  end

  @doc "Removes `name` and its key file."
  @spec remove(name()) :: :ok | {:error, :unknown_repo}
  def remove(name) do
    with {:ok, pairs} <- read_pairs(),
         true <- Keyword.has_key?(pairs, name) || {:error, :unknown_repo} do
      with :ok <- write_repos(Keyword.delete(pairs, name)) do
        _ = File.rm(key_path(name))
        :ok
      end
    end
  end

  @doc "Whether `name` is configured (and therefore trusted)."
  @spec trusted?(name()) :: boolean()
  def trusted?(name), do: Enum.any?(list(), &(&1.name == name))

  @doc "The key file for `name` (`/priv/hex/keys/<name>.pub`)."
  @spec key_path(name()) :: Path.t()
  def key_path(name), do: Path.join([hex_dir(), "keys", "#{name}.pub"])

  @doc """
  Verifies that `resource` (the bytes a repository served) is signed by
  `repo`'s key. Hex resources carry their signature; nothing is installed from
  a resource that does not verify.
  """
  @spec verify(t(), binary()) :: {:ok, binary()} | {:error, :bad_signature}
  def verify(%__MODULE__{} = repo, resource) do
    with {:ok, payload, signature} <- signed(resource),
         {:ok, key} <- decode_key(repo.key),
         true <- :public_key.verify(payload, :sha512, signature, key) do
      {:ok, payload}
    else
      _ -> {:error, :bad_signature}
    end
  end

  @doc false
  # The official repository is trusted out of the box (PROTOCOL.md §8): on a
  # machine whose /priv/hex/ has no repos.exs yet, the factory's copy and keys
  # are what it starts from. After that the file is the machine owner's.
  def ensure_seeded do
    if not File.regular?(repos_file()) and File.regular?(factory_repos_file()) do
      File.mkdir_p(Path.dirname(repos_file()))
      File.mkdir_p(keys_dir())

      with :ok <- File.cp(factory_repos_file(), repos_file()) do
        for key <- Path.wildcard(Path.join(factory_keys_dir(), "*.pub")) do
          File.cp(key, Path.join(keys_dir(), Path.basename(key)))
        end

        :ok
      end
    else
      :ok
    end
  end

  ## The configuration file

  defp read do
    case read_pairs() do
      {:ok, pairs} ->
        repos =
          for {name, opts} <- pairs,
              is_atom(name),
              is_list(opts),
              is_binary(opts[:url]),
              is_binary(opts[:key]) do
            %__MODULE__{name: name, url: opts[:url], key: opts[:key]}
          end

        {:ok, repos}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The file is the one configuration Elixos evaluates (PROTOCOL.md §8): it
  # holds PEM keys, which no literal format reads kindly. Nothing is trusted
  # if it cannot be read - and `add/3` refuses rather than overwrite it.
  defp read_pairs do
    if File.regular?(repos_file()) do
      try do
        case Code.eval_file(repos_file()) do
          {pairs, _binding} when is_list(pairs) -> {:ok, pairs}
          _other -> {:error, :malformed}
        end
      rescue
        error -> {:error, {:malformed, Exception.message(error)}}
      end
    else
      {:ok, []}
    end
  end

  defp write_repos(pairs) do
    write_atomic(
      repos_file(),
      inspect(pairs, limit: :infinity, printable_limit: :infinity) <> "\n"
    )
  end

  defp write_key(name, key) do
    write_atomic(key_path(name), key)
  end

  # Temporary file, fsync, rename, fsync of the directory (PROTOCOL.md §8): a
  # reader sees the old trust or the new one, and a power loss cannot
  # resurrect a repository that was removed or lose one that was added.
  defp write_atomic(path, body) do
    tmp = path <> ".#{System.unique_integer([:positive])}.tmp"
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         {:ok, file} <- :file.open(tmp, [:write, :raw, :binary]),
         :ok <- :file.write(file, body),
         :ok <- :file.sync(file),
         :ok <- :file.close(file),
         :ok <- File.rename(tmp, path),
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

  defp check_configured(pairs, name, replace?) do
    if Keyword.has_key?(pairs, name) and not replace? do
      {:error, :already_configured}
    else
      :ok
    end
  end

  ## Keys

  # RSA, PEM, as served: `RSA PUBLIC KEY` or the SubjectPublicKeyInfo wrapper.
  defp decode_key(key) when is_binary(key) do
    try do
      case :public_key.pem_decode(key) do
        [entry = {type, _der, :not_encrypted}]
        when type in [:RSAPublicKey, :SubjectPublicKeyInfo] ->
          rsa(:public_key.pem_entry_decode(entry))

        _other ->
          {:error, :bad_key}
      end
    rescue
      _error -> {:error, :bad_key}
    end
  end

  defp decode_key(_key), do: {:error, :bad_key}

  defp rsa(key) when elem(key, 0) == :RSAPublicKey, do: {:ok, key}

  defp rsa(key) when elem(key, 0) == :SubjectPublicKeyInfo do
    # rsaEncryption, RFC 8017 A.1
    case key do
      {:SubjectPublicKeyInfo, {:AlgorithmIdentifier, {1, 2, 840, 113_549, 1, 1, 1}, _params},
       _bits, _attrs} ->
        {:ok, key}

      _other ->
        {:error, :bad_key}
    end
  end

  defp rsa(_key), do: {:error, :bad_key}

  ## Signed resources

  # A resource is gzip(protobuf{ payload = 1, signature = 2 }), the signature
  # over the payload bytes (SHA-512, RSA). Verified against the repository's
  # key before anything in it is read.
  defp signed(resource) do
    with {:ok, message} <- Proto.decode(decompress(resource)),
         payload when is_binary(payload) <- Proto.one(message, 1),
         signature when is_binary(signature) <- Proto.one(message, 2) do
      {:ok, payload, signature}
    else
      _ -> {:error, :bad_signature}
    end
  end

  defp decompress(<<0x1F, 0x8B, _rest::binary>> = resource), do: :zlib.gunzip(resource)
  defp decompress(resource), do: resource

  defp hex_dir, do: Application.get_env(:elixos, :hex_dir, "/priv/hex")
  defp keys_dir, do: Path.join(hex_dir(), "keys")
  defp repos_file, do: Path.join(hex_dir(), "repos.exs")
  defp factory_dir, do: Application.get_env(:elixos, :factory_dir, "/factory")
  defp factory_keys_dir, do: Path.join([factory_dir(), "hex", "keys"])
  defp factory_repos_file, do: Path.join([factory_dir(), "hex", "repos.exs"])
end
