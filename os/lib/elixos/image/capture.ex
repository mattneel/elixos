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
    _ = {binding, opts}
    Elixos.NotImplemented.raise!(6, "Elixos.Image.Capture.eval/3")
  end
end
