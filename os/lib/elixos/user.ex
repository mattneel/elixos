defmodule Elixos.User do
  @moduledoc """
  The single user's settings (ADR-013), kept in one human-editable file
  (`/priv/user.exs` on a running system).

  The file holds one keyword list literal, e.g. `[repl: :erl, theme: :amber]`.
  It is parsed, never evaluated: only literal terms are accepted.

    * `read/1` returns `%{repl: name}`; a missing file means the defaults
      (`repl: Elixos.REPL.default()`); unknown keys are ignored
    * an unknown REPL in the file is `{:error, {:invalid, :repl}}`
    * a file that is not a keyword list literal is `{:error, :malformed}`
    * `put/3` validates first (`{:error, :unknown_repl}`), preserves keys it
      does not know, and writes atomically
  """

  @spec read(Path.t()) :: {:ok, %{repl: Elixos.REPL.name()}} | {:error, term()}
  def read(path) do
    with {:ok, pairs} <- pairs(path),
         :ok <- validate(pairs, :repl) do
      {:ok, %{repl: Keyword.get(pairs, :repl, Elixos.REPL.default())}}
    end
  end

  @spec put(Path.t(), :repl, atom()) :: :ok | {:error, term()}
  def put(path, key, value) do
    unless key == :repl, do: throw({:error, {:unknown, key}})

    with :ok <- validate([{key, value}], key),
         {:ok, pairs} <- pairs(path) do
      write_atomic(path, Keyword.put(pairs, key, value))
    else
      # `read/1` reports a bad REPL in the file as `{:invalid, :repl}`; a
      # caller asking to *set* one gets the reason. Put validates first and
      # leaves the file alone.
      {:error, {:invalid, :repl}} -> {:error, :unknown_repl}
      {:error, reason} -> {:error, reason}
    end
  end

  # The literal keyword list in the file, or the empty one when it is missing.
  # Parsing never evaluates: a call anywhere in the literal is malformed, so a
  # file cannot do anything by being read.
  defp pairs(path) do
    case File.read(path) do
      {:ok, text} ->
        with {:ok, quoted} <- Code.string_to_quoted(text),
             {:ok, pairs} <- literals(quoted) do
          {:ok, pairs}
        else
          _other -> {:error, :malformed}
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  # A keyword list of literal terms, or nothing. Atoms, numbers, strings and
  # booleans are what a settings file needs; anything else is a program.
  def literals(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn
      {key, value}, {:ok, acc} when is_atom(key) ->
        case literal(value) do
          {:ok, value} -> {:cont, {:ok, [{key, value} | acc]}}
          :error -> {:halt, :error}
        end

      _other, _acc ->
        {:halt, :error}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
    end
  end

  def literals(_other), do: :error

  defp literal(value)
       when is_atom(value) or is_number(value) or is_binary(value) or is_boolean(value),
       do: {:ok, value}

  # `inspect/1` writes an atom like `:"Elixir.Amber"` as `Amber`, which parses
  # as an alias: the same atom, spelled the way a file would spell it.
  defp literal({:__aliases__, _meta, parts}) when is_list(parts) and parts != [] do
    {:ok, Module.concat([:"Elixir" | parts])}
  end

  defp literal(_other), do: :error

  defp validate(pairs, key) do
    case Keyword.fetch(pairs, key) do
      {:ok, value} ->
        if value in Elixos.REPL.available(), do: :ok, else: {:error, {:invalid, key}}

      :error ->
        :ok
    end
  end

  # Parse first, then replace, then rename: a reader sees the old file or the
  # new one, and a failed write leaves the settings alone.
  defp write_atomic(path, pairs) do
    # One temporary file per update: two writers sharing a name can publish
    # each other's settings, or fail renaming a file the other already moved.
    tmp = path <> ".#{System.unique_integer([:positive])}.tmp"
    body = inspect(pairs, limit: :infinity, printable_limit: :infinity) <> "\n"

    with :ok <- File.write(tmp, body),
         :ok <- File.rename(tmp, path) do
      :ok
    end
  end
end
