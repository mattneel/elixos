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
  def read(path), do: Elixos.NotImplemented.raise!(9, "Elixos.User.read/1 #{path}")

  @spec put(Path.t(), :repl, atom()) :: :ok | {:error, term()}
  def put(path, key, value) do
    _ = {path, key, value}
    Elixos.NotImplemented.raise!(9, "Elixos.User.put/3")
  end
end
