defmodule Elixos.Image.Capture do
  @moduledoc """
  Evaluates code the way a REPL does and captures every module it defines
  (docs/ARCHITECTURE.md §4.1).

  Capture must see modules defined anywhere in the evaluated code, including
  nested `defmodule`s and ones defined inside function calls, and must return
  the exact bytecode that was loaded. Compilation tracers receive
  `{:on_module, bytecode, _}` for each module.

  Verified on Elixir 1.20.4 while writing this scaffold:

    * `Code.eval_quoted_with_env/4` with `%{Code.env_for_eval(opts) | tracers: [Tracer]}`
      traces every module: nested ones before their parent, otherwise in
      definition order, including modules defined inside function calls.
    * `Code.eval_string/3` with that same env traces nothing, and neither does
      the global `:tracers` compiler option. Do not use them for capture.
    * IEx evaluates with `eval_quoted_with_env/4` and keeps the returned env,
      and `IEx.Server.run/1` accepts an `:env`, so the login IEx can carry the
      tracer too (see `Elixos.REPL`).

  Modules defined in *other* processes during the evaluation (for example
  inside `Task.async/1`) are not captured; that is documented, not a bug.
  """

  @doc """
  Evaluates `code` with `binding`, like a shell line.

  Returns `{value, new_binding, captured}`, where `captured` lists
  `{module, bytecode}` in definition order. Errors raised by the code
  propagate unchanged.
  """
  @spec eval(String.t(), keyword(), keyword()) :: {term(), keyword(), [{module(), binary()}]}
  def eval(code, binding \\ [], opts \\ []) when is_binary(code) do
    quoted = Code.string_to_quoted!(code, Keyword.take(opts, [:file, :line, :column, :existing_atoms_only]))
    # The tracer has to be in the env the evaluation uses: eval_string/3 and
    # the global :tracers option see nothing (verified on Elixir 1.20.4).
    env = %{Code.env_for_eval(opts) | tracers: [__MODULE__]}
    key = capture_key()

    Process.put(key, [])

    try do
      # /4 returns the updated env as well, so a shell can keep looping.
      {value, new_binding, _env} = Code.eval_quoted_with_env(quoted, binding, env, opts)
      {value, new_binding, Process.get(key) |> Enum.reverse()}
    after
      Process.delete(key)
    end
  end

  @doc false
  # A compilation tracer (Elixir calls back into this module). The event
  # carries the bytecode but not the module it defines, so the name comes from
  # the bytecode's attributes.
  def trace({:on_module, bytecode, _ignore}, _env) do
    case module_of(bytecode) do
      {:ok, module} -> Process.put(capture_key(), [{module, bytecode} | Process.get(capture_key(), [])])
      :error -> :ok
    end

    :ok
  end

  def trace(_event, _env), do: :ok

  # Modules defined in other processes are not captured (see the moduledoc):
  # the accumulator lives in the evaluating process.
  defp capture_key, do: {__MODULE__, :captured}

  defp module_of(bytecode) do
    case :beam_lib.chunks(bytecode, [:attributes]) do
      {:ok, {module, _chunks}} when is_atom(module) -> {:ok, module}
      _ -> :error
    end
  end
end
