defmodule Elixos.Deck.Terminal do
  @moduledoc """
  The deck's text grid (M33): a fixed `columns x rows` screen of codepoints
  with a cursor, written to as a terminal would be, and the damage those
  writes caused, so the renderer redraws only what changed.

  Enough of a VT to show IEx sanely, and no more:

    * printable characters overwrite the cell under the cursor and advance
      it; the line wraps when a character is written past the last column
      (the cursor rests on the margin until then, as on a VT100);
    * `\\n` is a newline (carriage return included: there is no tty to add
      it), `\\r` returns, `\\b` steps back (to the end of the previous row
      from column 0, so line editing can erase across a wrap), `\\t` jumps
      to the next multiple of 8; BEL and other C0 controls are ignored;
    * CSI sequences: SGR (`m`) is accepted and ignored (one colour scheme),
      `K` and `J` erase, `A` `B` `C` `D` `G` `H` `f` move the cursor; other
      CSI, OSC and two-byte escapes are consumed without effect;
    * writing below the last row scrolls the grid up.

  Damage is per row, as a column range, plus how many rows the grid scrolled
  since the last `take_damage/1`.
  """

  defstruct [
    :columns,
    :rows,
    :cells,
    row: 0,
    column: 0,
    state: :ground,
    params: "",
    dirty: %{},
    scrolled: 0
  ]

  @type t :: %__MODULE__{}

  @blank ?\s

  @spec new(pos_integer(), pos_integer()) :: t()
  def new(columns, rows) do
    %__MODULE__{columns: columns, rows: rows, cells: blank_grid(columns, rows)}
  end

  defp blank_row(columns), do: Tuple.duplicate(@blank, columns)
  defp blank_grid(columns, rows), do: Tuple.duplicate(blank_row(columns), rows)

  @doc "Writes UTF-8 text (bytes that are not UTF-8 show as `?`)."
  @spec write(t(), binary()) :: t()
  def write(term, <<>>), do: term
  def write(term, <<c::utf8, rest::binary>>), do: term |> input(c) |> write(rest)
  def write(term, <<_byte, rest::binary>>), do: term |> input(??) |> write(rest)

  @doc "The cursor as `{row, column}`, on the grid (a cursor resting on the right margin shows on the last column)."
  @spec cursor(t()) :: {non_neg_integer(), non_neg_integer()}
  def cursor(term), do: {term.row, min(term.column, term.columns - 1)}

  @doc "The codepoint at `{row, column}`."
  @spec at(t(), {non_neg_integer(), non_neg_integer()}) :: non_neg_integer()
  def at(term, {row, column}), do: term.cells |> elem(row) |> elem(column)

  @doc "Every row as a string, trailing blanks kept."
  @spec lines(t()) :: [String.t()]
  def lines(term) do
    for row <- Tuple.to_list(term.cells), do: row |> Tuple.to_list() |> List.to_string()
  end

  @doc """
  The damage since the last call: `%{scrolled: n, dirty: [{row, first, last}]}`
  (columns inclusive, rows ascending), and the terminal with none left.
  """
  @spec take_damage(t()) :: {%{scrolled: non_neg_integer(), dirty: list()}, t()}
  def take_damage(term) do
    dirty =
      term.dirty |> Enum.sort() |> Enum.map(fn {row, {first, last}} -> {row, first, last} end)

    {%{scrolled: term.scrolled, dirty: dirty}, %{term | dirty: %{}, scrolled: 0}}
  end

  @doc "Marks a cell dirty (the renderer's cursor moved off or onto it)."
  @spec touch(t(), {non_neg_integer(), non_neg_integer()}) :: t()
  def touch(term, {row, column}), do: mark(term, row, column, column)

  ## The parser

  defp input(%{state: :ground} = term, c), do: ground(term, c)

  defp input(%{state: :escape} = term, ?[), do: %{term | state: :csi, params: ""}
  defp input(%{state: :escape} = term, ?]), do: %{term | state: :osc}

  defp input(%{state: :escape} = term, c) when c in [?(, ?), ?*, ?+, ?#, ?%],
    do: %{term | state: :charset}

  defp input(%{state: :escape} = term, _c), do: %{term | state: :ground}
  defp input(%{state: :charset} = term, _c), do: %{term | state: :ground}

  defp input(%{state: :osc} = term, 7), do: %{term | state: :ground}
  defp input(%{state: :osc} = term, 27), do: %{term | state: :osc_escape}
  defp input(%{state: :osc} = term, _c), do: term
  defp input(%{state: :osc_escape} = term, _c), do: %{term | state: :ground}

  defp input(%{state: :csi} = term, c) when c in 0x20..0x3F,
    do: %{term | params: term.params <> <<c>>}

  defp input(%{state: :csi} = term, c) when c in 0x40..0x7E,
    do: csi(%{term | state: :ground}, c, params(term.params))

  defp input(%{state: :csi} = term, _c), do: %{term | state: :ground}

  defp ground(term, 27), do: %{term | state: :escape}
  defp ground(term, ?\n), do: term |> carriage_return() |> line_feed()
  defp ground(term, ?\r), do: carriage_return(term)

  defp ground(term, ?\t),
    do: %{
      term
      | column: min(div(min(term.column, term.columns - 1), 8) * 8 + 8, term.columns - 1)
    }

  defp ground(term, ?\b), do: back(term)
  defp ground(term, c) when c < 0x20 or c == 0x7F or c in 0x80..0x9F, do: term
  defp ground(term, c), do: put(term, c)

  defp put(term, c) do
    term =
      if term.column >= term.columns, do: term |> carriage_return() |> line_feed(), else: term

    row = term.cells |> elem(term.row) |> put_elem(term.column, c)
    term = %{term | cells: put_elem(term.cells, term.row, row)}
    term |> mark(term.row, term.column, term.column) |> Map.put(:column, term.column + 1)
  end

  defp back(%{column: 0, row: 0} = term), do: term
  defp back(%{column: 0} = term), do: %{term | row: term.row - 1, column: term.columns - 1}
  defp back(term), do: %{term | column: min(term.column, term.columns) - 1}

  defp carriage_return(term), do: %{term | column: 0}

  defp line_feed(%{row: row, rows: rows} = term) when row < rows - 1, do: %{term | row: row + 1}

  defp line_feed(term) do
    [_gone | kept] = Tuple.to_list(term.cells)
    cells = List.to_tuple(kept ++ [blank_row(term.columns)])

    dirty =
      for {row, range} <- term.dirty, row > 0, into: %{}, do: {row - 1, range}

    %{term | cells: cells, dirty: dirty, scrolled: term.scrolled + 1}
    |> mark(term.rows - 1, 0, term.columns - 1)
  end

  defp params(""), do: []

  defp params(text) do
    text
    |> String.trim_leading("?")
    |> String.split(";")
    |> Enum.map(fn part ->
      case Integer.parse(part) do
        {n, ""} -> n
        _ -> nil
      end
    end)
  end

  defp param(params, index, default) do
    case Enum.at(params, index) do
      n when is_integer(n) and n > 0 -> n
      _ -> default
    end
  end

  defp csi(term, ?m, _params), do: term

  defp csi(term, ?K, params) do
    column = min(term.column, term.columns - 1)

    case Enum.at(params, 0) || 0 do
      0 -> erase(term, term.row, column, term.columns - 1)
      1 -> erase(term, term.row, 0, column)
      2 -> erase(term, term.row, 0, term.columns - 1)
      _ -> term
    end
  end

  defp csi(term, ?J, params) do
    column = min(term.column, term.columns - 1)
    last = term.columns - 1

    case Enum.at(params, 0) || 0 do
      0 ->
        Enum.reduce(
          (term.row + 1)..(term.rows - 1)//1,
          erase(term, term.row, column, last),
          &erase(&2, &1, 0, last)
        )

      1 ->
        Enum.reduce(
          0..(term.row - 1)//1,
          erase(term, term.row, 0, column),
          &erase(&2, &1, 0, last)
        )

      n when n in [2, 3] ->
        Enum.reduce(0..(term.rows - 1), term, &erase(&2, &1, 0, last))

      _ ->
        term
    end
  end

  defp csi(term, ?A, p), do: %{term | row: max(term.row - param(p, 0, 1), 0)}
  defp csi(term, ?B, p), do: %{term | row: min(term.row + param(p, 0, 1), term.rows - 1)}

  defp csi(term, ?C, p),
    do: %{
      term
      | column: min(min(term.column, term.columns - 1) + param(p, 0, 1), term.columns - 1)
    }

  defp csi(term, ?D, p),
    do: %{term | column: max(min(term.column, term.columns - 1) - param(p, 0, 1), 0)}

  defp csi(term, ?G, p), do: %{term | column: min(param(p, 0, 1), term.columns) - 1}

  defp csi(term, c, p) when c in [?H, ?f] do
    %{
      term
      | row: min(param(p, 0, 1), term.rows) - 1,
        column: min(param(p, 1, 1), term.columns) - 1
    }
  end

  defp csi(term, _c, _params), do: term

  defp erase(term, row, first, last) do
    cells =
      Enum.reduce(first..last//1, elem(term.cells, row), fn column, acc ->
        put_elem(acc, column, @blank)
      end)

    %{term | cells: put_elem(term.cells, row, cells)} |> mark(row, first, last)
  end

  defp mark(term, row, first, last) do
    dirty =
      Map.update(term.dirty, row, {first, last}, fn {a, b} -> {min(a, first), max(b, last)} end)

    %{term | dirty: dirty}
  end
end
