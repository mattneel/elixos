defmodule Elixos.Candidate.Evidence do
  @moduledoc false

  alias Elixos.Image.Store

  def write(dir, name, term) do
    path = Path.join(dir, name <> ".term")
    bytes = :erlang.term_to_binary(term)
    tmp = path <> ".#{System.unique_integer([:positive])}.tmp"

    with :ok <- File.mkdir_p(dir),
         :ok <- sync_file(tmp, bytes),
         :ok <- File.rename(tmp, path),
         :ok <- sync_directory(dir) do
      :ok
    else
      error ->
        File.rm(tmp)
        error
    end
  end

  def record(dir, name, term) do
    id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    history = name <> "-" <> id
    path = Path.join(dir, name <> ".term")
    tmp = path <> "." <> id <> ".tmp"

    # One fsynced receipt inode with an atomic latest link. Service rechecks
    # retain a failure's bytes without duplicating its serialization.
    with :ok <- write(dir, history, term),
         :ok <- File.ln(Path.join(dir, history <> ".term"), tmp),
         :ok <- File.rename(tmp, path),
         :ok <- sync_directory(dir) do
      :ok
    else
      error ->
        File.rm(tmp)
        error
    end
  end

  def read(dir, name) do
    with {:ok, bytes} <- File.read(Path.join(dir, name <> ".term")) do
      {:ok, :erlang.binary_to_term(bytes)}
    end
  rescue
    ArgumentError -> {:error, :corrupt}
  end

  def copy_source(source, destination) do
    with :ok <- separate_destination(source, destination),
         true <- File.regular?(Path.join(source, "mix.exs")),
         :ok <- copy_tree(source, destination) do
      :ok
    else
      false -> {:error, {:source_missing, source}}
      error -> error
    end
  end

  # Directories copy_tree never descends into: generated output and scratch.
  @skipped ["_build", "deps", ".git", "tmp", "erl_crash.dump"]

  def separate_destination(source, destination) do
    source = Path.expand(source)
    destination = Path.expand(destination)

    cond do
      destination == source -> {:error, :nested_source_destination}
      not String.starts_with?(destination, source <> "/") -> :ok
      # A destination under a skipped directory (a host checkout's `tmp/`) is
      # never read by the copy, so it cannot copy itself.
      hd(Path.split(Path.relative_to(destination, source))) in @skipped -> :ok
      true -> {:error, :nested_source_destination}
    end
  end

  def copy_inputs(source, destination) do
    Enum.reduce_while(["spec", "MILESTONE"], :ok, fn name, :ok ->
      from = Path.join(Path.dirname(source), name)
      to = Path.join(destination, name)

      if File.exists?(from) do
        case copy_tree(from, to) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  def fingerprint(directory) do
    with {:ok, files} <- files(directory) do
      Enum.reduce_while(files, [], fn path, hashes ->
        case File.read(path) do
          {:ok, bytes} ->
            {:cont, [{Path.relative_to(path, directory), Store.hash(bytes)} | hashes]}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:error, _} = error -> error
        hashes -> {:ok, Store.hash(:erlang.term_to_binary(Enum.sort(hashes)))}
      end
    end
  end

  # The same names copy_tree skips: a snapshot never contains them, so whatever
  # a suite writes there (ExUnit's `tmp/`) is output, not a candidate input.
  def files(directory) do
    with {:ok, names} <- File.ls(directory) do
      names
      |> Enum.reject(&(&1 in @skipped))
      |> Enum.sort()
      |> Enum.reduce_while([], fn name, paths ->
        path = Path.join(directory, name)

        case File.lstat(path) do
          {:ok, %{type: :regular}} ->
            {:cont, [path | paths]}

          {:ok, %{type: :directory}} ->
            case files(path) do
              {:ok, nested} -> {:cont, nested ++ paths}
              error -> {:halt, error}
            end

          {:ok, %{type: type}} ->
            {:halt, {:error, {:unsupported_input, path, type}}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:error, _} = error -> error
        paths -> {:ok, Enum.sort(paths)}
      end
    end
  end

  defp copy_tree(source, destination) do
    case File.lstat(source) do
      {:ok, %{type: :directory}} ->
        with :ok <- File.mkdir_p(destination), {:ok, names} <- File.ls(source) do
          result =
            names
            |> Enum.reject(&(&1 in @skipped))
            |> Enum.reduce_while(:ok, fn name, :ok ->
              case copy_tree(Path.join(source, name), Path.join(destination, name)) do
                :ok -> {:cont, :ok}
                error -> {:halt, error}
              end
            end)

          if result == :ok, do: sync_directory(destination), else: result
        end

      {:ok, %{type: :regular}} ->
        with {:ok, bytes} <- File.read(source), do: sync_file(destination, bytes)

      {:ok, %{type: type}} ->
        {:error, {:unsupported_input, source, type}}

      error ->
        error
    end
  end

  defp sync_file(path, bytes) do
    with {:ok, file} <- :file.open(path, [:write, :raw, :binary]) do
      result = with :ok <- :file.write(file, bytes), do: :file.sync(file)
      close = :file.close(file)
      if result == :ok, do: close, else: result
    end
  end

  defp sync_directory(dir) do
    with {:ok, file} <- :file.open(dir, [:read, :directory]) do
      result = :file.sync(file)
      close = :file.close(file)
      if result == :ok, do: close, else: result
    end
  end
end
