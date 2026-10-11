defmodule Elixos.Oban.Declaration do
  @moduledoc """
  One app's `oban:` declaration from its `elixos:` key (M19, ADR-057).

  The shape is the same one `Elixos.Package.Spec` documents:

      oban: [
        queues: [jobs: 3, mail: 1],
        cron: [{"0 3 * * *", MyApp.Worker}]
      ]

  Queue names are atoms with a positive integer limit; names under the
  `elixos_` prefix belong to the system and are refused. Cron entries are
  five-field expressions (or a supported `@special`) and a worker module.
  `[]` declares nothing, and anything else is `{:error, :invalid}`.

  Two apps may share a queue when they agree on its limit; `merge_queues/1`
  refuses the pair that disagrees instead of silently overwriting one of them.
  """

  @system_queue_prefix "elixos_"
  # Oban's Cron refuses `@reboot` (it has no boot to hang it on); the other
  # specials the parser knows are ordinary schedules.
  @unsupported_specials ~w(@reboot)
  @keys [:queues, :cron]

  @doc "Validates one declaration: `:ok` or `{:error, :invalid}`."
  @spec validate(term()) :: :ok | {:error, :invalid}
  def validate(declaration) do
    if is_list(declaration) and Keyword.keyword?(declaration) and
         Keyword.keys(declaration) -- @keys == [] and
         valid_queues?(Keyword.get(declaration, :queues, [])) and
         valid_cron?(Keyword.get(declaration, :cron, [])) do
      :ok
    else
      {:error, :invalid}
    end
  end

  @doc "The queues a declaration asks for, `name: limit`."
  @spec queues(keyword()) :: keyword(non_neg_integer())
  def queues(declaration), do: Keyword.get(declaration, :queues, [])

  @doc "The cron entries a declaration asks for, `{expression, worker}`."
  @spec cron(keyword()) :: [{String.t(), module()}]
  def cron(declaration), do: Keyword.get(declaration, :cron, [])

  @doc """
  The queues every declaration asks for, merged: `{:ok, %{name => limit}}`,
  or `{:error, {:conflict, name}}` when two apps disagree on a limit.
  """
  @spec merge_queues([keyword()]) ::
          {:ok, %{atom() => pos_integer()}} | {:error, {:conflict, atom()}}
  def merge_queues(declarations) do
    Enum.reduce_while(declarations, {:ok, %{}}, fn declaration, {:ok, merged} ->
      case put_queues(merged, queues(declaration)) do
        {:ok, merged} -> {:cont, {:ok, merged}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Every declaration's cron entries, without duplicates."
  @spec merge_cron([keyword()]) :: [{String.t(), module()}]
  def merge_cron(declarations) do
    declarations
    |> Enum.flat_map(&cron/1)
    |> Enum.uniq()
  end

  @doc "Whether `name` is a queue the apps may declare."
  @spec declarable_queue?(term()) :: boolean()
  def declarable_queue?(name) when is_atom(name) and not is_nil(name) do
    not String.starts_with?(Atom.to_string(name), @system_queue_prefix)
  end

  def declarable_queue?(_name), do: false

  defp put_queues(merged, queues) do
    Enum.reduce_while(queues, {:ok, merged}, fn {name, limit}, {:ok, merged} ->
      case merged do
        %{^name => ^limit} -> {:cont, {:ok, merged}}
        %{^name => _existing} -> {:halt, {:error, {:conflict, name}}}
        _missing -> {:cont, {:ok, Map.put(merged, name, limit)}}
      end
    end)
  end

  defp valid_queues?(queues) when is_list(queues) do
    Keyword.keyword?(queues) and
      Enum.all?(queues, fn
        {name, limit} ->
          declarable_queue?(name) and is_integer(limit) and limit > 0

        _other ->
          false
      end)
  end

  defp valid_queues?(_other), do: false

  defp valid_cron?(cron) when is_list(cron) do
    Enum.all?(cron, fn
      {expression, worker} when is_binary(expression) and is_atom(worker) and not is_nil(worker) ->
        expression not in @unsupported_specials and parseable?(expression)

      _other ->
        false
    end)
  end

  defp valid_cron?(_other), do: false

  # Five fields, the shape Oban's Cron accepts: the parser is lenient about the
  # field count, so the count is checked here. A `@special` is one token.
  defp parseable?("@" <> _special = expression) do
    match?({:ok, _}, Crontab.CronExpression.Parser.parse(expression))
  end

  defp parseable?(expression) do
    length(String.split(expression)) == 5 and
      match?({:ok, _}, Crontab.CronExpression.Parser.parse(expression))
  end
end
