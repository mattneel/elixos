defmodule Elixos.Ask do
  @moduledoc """
  Questions are data in the OS; front-ends are only views (M20,
  docs/ROADMAP.md).

  A front-end - the REPL, an ssh session, the GUI - asks through the same
  queue: `ask/2` blocks its caller until the question is answered, dismissed
  or timed out, and `pending/0`, `answer/2` and `dismiss/1` are how any other
  front-end resolves it. Answers are validated against the question that was
  asked, so a front-end cannot hand back something the question never allowed.

  The kinds are `:text` (free-form), `:choice` (one of the options), `:multi`
  (any of them) and `:confirm` (yes/no); a choice or multi question may allow
  an "other" free-text answer. A question still open when its session ends is
  dismissed, never guessed.
  """

  defmodule Question do
    @moduledoc "One open question."

    @type t :: %__MODULE__{
            id: String.t(),
            kind: :text | :choice | :multi | :confirm,
            prompt: String.t(),
            options: [String.t()],
            asker: pid(),
            default: term(),
            timeout: pos_integer() | nil,
            allow_other: boolean()
          }

    defstruct [:id, :kind, :prompt, :options, :asker, :default, :timeout, :allow_other]
  end

  @doc "Every open question, oldest first."
  @spec pending() :: [Question.t()]
  def pending, do: Elixos.NotImplemented.raise!(20, "Elixos.Ask.pending/0")

  @doc """
  Asks `kind` with `opts` (`:prompt`, `:options`, `:default`, `:timeout`,
  `:allow_other`) and blocks until the question is resolved.
  """
  @spec ask(:text | :choice | :multi | :confirm, keyword()) ::
          {:ok, term()} | {:error, :timeout | :dismissed | term()}
  def ask(_kind, _opts \\ []), do: Elixos.NotImplemented.raise!(20, "Elixos.Ask.ask/2")

  @doc "Answers the question `id` with an answer valid for it."
  @spec answer(String.t(), term()) :: :ok | {:error, term()}
  def answer(_id, _answer), do: Elixos.NotImplemented.raise!(20, "Elixos.Ask.answer/2")

  @doc "Dismisses the question `id`: its asker gets `{:error, :dismissed}`."
  @spec dismiss(String.t()) :: :ok | {:error, term()}
  def dismiss(_id), do: Elixos.NotImplemented.raise!(20, "Elixos.Ask.dismiss/1")
end
