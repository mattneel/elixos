defmodule Elixos.GUI.Dialog do
  @moduledoc """
  The framebuffer view of one Oh-My-Jido approval or question (M27, ADR-093).

  Selection and editing are pure Elixir. `Elixos.Approvals` remains the
  authority for accepting an answer; a default only pre-fills this view and
  never resolves it. Escape and F12 hand the screen back and decide nothing;
  denying an effect is an explicit No. Emerge draws the same tree for
  off-screen capture and the live framebuffer.
  """

  import Emerge.UI, only: [el: 2, row: 2, column: 2, paragraph: 2, text: 1]
  import Emerge.UI.Size, only: [width: 1, height: 1, px: 1, fill: 0]
  import Emerge.UI.Space, only: [padding: 1, padding_xy: 2, spacing: 1]
  import Emerge.UI.Align, only: [center_x: 0]

  alias Emerge.UI.{Align, Background, Border, Font, Nearby, Transform}
  alias Elixos.Approvals.Request

  @outer 24
  @padding 20
  @gap 12
  @row_height 40
  @row_gap 8
  @header_height 128
  @footer_height 64
  @background {:color_rgb, {14, 18, 27}}
  @surface {:color_rgb, {23, 30, 43}}
  @foreground {:color_rgb, {233, 239, 247}}
  @muted {:color_rgb, {155, 169, 190}}
  @accent {:color_rgb, {94, 177, 235}}
  @selected {:color_rgb, {35, 65, 90}}
  @border {:color_rgb, {61, 77, 98}}
  @error {:color_rgb, {244, 157, 140}}

  defstruct [
    :question,
    cursor: 0,
    selected: MapSet.new(),
    text: "",
    error: nil,
    pointer: {0, 0},
    pointer_visible: false
  ]

  @type t :: %__MODULE__{}

  @spec new(Request.t() | nil) :: t()
  def new(nil), do: %__MODULE__{}

  def new(%Request{} = question) do
    cursor =
      case question.kind do
        :confirm -> if question.default == true, do: 0, else: 1
        :choice -> Enum.find_index(question.options, &(&1 == question.default)) || 0
        _ -> 0
      end

    selected =
      if question.kind == :multi and is_list(question.default) do
        MapSet.new(Enum.filter(question.default, &(&1 in question.options)))
      else
        MapSet.new()
      end

    initial_text =
      cond do
        question.kind == :text and is_binary(question.default) ->
          question.default

        question.kind == :choice and question.allow_other and is_binary(question.default) and
            question.default not in question.options ->
          question.default

        true ->
          ""
      end

    cursor =
      if question.kind == :choice and question.allow_other and is_binary(question.default) and
           question.default not in question.options,
         do: length(question.options),
         else: cursor

    %__MODULE__{question: question, cursor: cursor, selected: selected, text: initial_text}
  end

  @doc "Changes the displayed request without losing edits or the physical pointer."
  @spec show(t(), Request.t() | nil) :: t()
  def show(dialog, question) do
    case {dialog.question, question} do
      {%{id: id}, %{id: id}} -> dialog
      {nil, nil} -> dialog
      _ -> %{new(question) | pointer: dialog.pointer, pointer_visible: dialog.pointer_visible}
    end
  end

  @spec input(t(), term(), {pos_integer(), pos_integer()}) ::
          {:continue, t()} | {:answer, term(), t()} | {:stop, t()}
  def input(dialog, event, size \\ {640, 480})

  def input(dialog, {:pointer, x, y}, _size) when is_number(x) and is_number(y),
    do: {:continue, %{dialog | pointer: {x, y}, pointer_visible: true}}

  def input(dialog, {:button, :left, :press}, size), do: click(dialog, size)

  def input(dialog, {:key, key, :repeat}, _size) when key in ["Enter", "Escape"],
    do: {:continue, dialog}

  def input(%{question: %{kind: :confirm}} = dialog, {:key, key, :repeat}, _size)
      when key in ["y", "Y", "n", "N"],
      do: {:continue, dialog}

  def input(%{question: %{kind: :multi}} = dialog, {:key, " ", :repeat}, _size),
    do: {:continue, dialog}

  def input(dialog, {:key, key, :repeat}, size),
    do: input(dialog, {:key, key, :press}, size)

  def input(dialog, {:key, _key, :release}, _size), do: {:continue, dialog}

  def input(dialog, {:key, key, :press}, _size) when key in ["F12", "Escape"],
    do: {:stop, dialog}

  def input(%{question: nil} = dialog, _event, _size), do: {:continue, dialog}
  def input(dialog, {:key, "Enter", :press}, _size), do: submit(dialog)

  def input(%{question: %{kind: :confirm}} = dialog, {:key, key, :press}, _size)
      when key in ["y", "Y", "n", "N"],
      do: {:answer, key in ["y", "Y"], dialog}

  def input(dialog, {:key, key, :press}, _size) when key in ["ArrowDown", "ArrowRight", "Tab"],
    do: move(dialog, 1)

  def input(dialog, {:key, key, :press}, _size) when key in ["ArrowUp", "ArrowLeft"],
    do: move(dialog, -1)

  def input(%{question: %{kind: :multi}} = dialog, {:key, " ", :press}, _size),
    do: {:continue, toggle(dialog)}

  def input(dialog, {:key, "Backspace", :press}, _size) do
    if editing?(dialog) do
      {:continue, %{dialog | text: String.slice(dialog.text, 0..-2//1), error: nil}}
    else
      {:continue, dialog}
    end
  end

  def input(dialog, {:key, key, :press}, _size) when is_binary(key) do
    if editing?(dialog) and String.length(key) == 1 and String.printable?(key) do
      {:continue, %{dialog | text: dialog.text <> key, error: nil}}
    else
      {:continue, dialog}
    end
  end

  def input(dialog, _event, _size), do: {:continue, dialog}

  defp editing?(%{question: %{kind: :text}}), do: true

  defp editing?(%{
         question: %{kind: :choice, allow_other: true, options: options},
         cursor: cursor
       }),
       do: cursor == length(options)

  defp editing?(_dialog), do: false

  defp option_count(%{question: %{kind: :confirm}}), do: 2
  defp option_count(%{question: %{kind: :text}}), do: 1

  defp option_count(%{question: question}),
    do:
      length(question.options) +
        if(question.kind == :choice and question.allow_other, do: 1, else: 0)

  defp move(dialog, delta) do
    count = option_count(dialog)
    {:continue, %{dialog | cursor: Integer.mod(dialog.cursor + delta, count), error: nil}}
  end

  defp toggle(dialog) do
    option = Enum.at(dialog.question.options, dialog.cursor)

    selected =
      if MapSet.member?(dialog.selected, option),
        do: MapSet.delete(dialog.selected, option),
        else: MapSet.put(dialog.selected, option)

    %{dialog | selected: selected, error: nil}
  end

  defp submit(%{question: %{kind: :text}} = dialog), do: {:answer, dialog.text, dialog}
  defp submit(%{question: %{kind: :confirm}} = dialog), do: {:answer, dialog.cursor == 0, dialog}

  defp submit(%{question: %{kind: :choice, options: options}} = dialog) do
    value =
      if dialog.cursor == length(options), do: dialog.text, else: Enum.at(options, dialog.cursor)

    {:answer, value, dialog}
  end

  defp submit(%{question: %{kind: :multi}} = dialog) do
    values = Enum.filter(dialog.question.options, &MapSet.member?(dialog.selected, &1))

    if values == [] do
      {:continue, %{dialog | error: "Select at least one option."}}
    else
      {:answer, values, dialog}
    end
  end

  @spec tree(t(), {pos_integer(), pos_integer()}) :: Emerge.UI.t()
  def tree(dialog, {w, h} = size) do
    geometry = geometry(size)
    {prompt, caption, hint} = labels(dialog)

    card =
      column(
        [
          width(px(geometry.panel_width)),
          padding(@padding),
          spacing(@gap),
          center_x(),
          Background.color(@surface),
          Border.rounded(12),
          Font.color(@foreground)
        ],
        [
          el(
            [height(px(16)), Font.size(12), Font.family("monospace"), Font.color(@accent)],
            text("ELIXOS / APPROVALS")
          ),
          paragraph([width(fill()), height(px(56)), Font.size(24), Font.weight(600)], [
            text(prompt)
          ]),
          el([height(px(20)), Font.size(13), Font.color(@muted)], text(caption)),
          body(dialog, size),
          el([height(px(20)), Font.size(13), Font.color(@error)], text(dialog.error || " ")),
          el([height(px(20)), Font.size(12), Font.color(@muted)], text(hint))
        ]
      )

    attrs = [width(px(w)), height(px(h)), padding(@outer), Background.color(@background)]

    attrs =
      if dialog.pointer_visible,
        do: [Nearby.in_front(cursor(dialog.pointer)) | attrs],
        else: attrs

    column(attrs, [card])
  end

  defp cursor({x, y}) do
    horizontal =
      el(
        [width(px(12)), height(px(2)), Align.center_y(), Background.color(@foreground)],
        text("")
      )

    vertical =
      el(
        [width(px(2)), height(px(12)), center_x(), Background.color(@foreground)],
        text("")
      )

    el(
      [
        width(px(12)),
        height(px(12)),
        Align.align_left(),
        Align.align_top(),
        Transform.move_x(x - 6),
        Transform.move_y(y - 6),
        Nearby.in_front(horizontal)
      ],
      vertical
    )
  end

  defp labels(%{question: nil}) do
    {"Ready for the next approval", "Agents ask; you decide.",
     "Escape or F12 returns to the console."}
  end

  defp labels(%{question: question}) do
    case question.kind do
      :text ->
        {question.prompt, "TEXT ANSWER", "Type an answer. Enter sends; Escape returns to IEx."}

      :confirm ->
        {question.prompt, "APPROVE",
         "Y approves; N denies. Enter accepts; Escape returns to IEx."}

      :choice ->
        {question.prompt, "SELECT ONE", "Up / Down select. Enter accepts; Escape returns to IEx."}

      :multi ->
        {question.prompt, "SELECT ONE OR MORE",
         "Up / Down select; Space toggles; Enter sends; Escape returns to IEx."}
    end
  end

  defp body(%{question: nil}, _size) do
    el(
      [height(px(@row_height)), Font.size(16)],
      text("Waiting for an Oh-My-Jido approval or question.")
    )
  end

  defp body(%{question: %{kind: :confirm}} = dialog, _size) do
    row([width(fill()), height(px(@row_height)), spacing(@row_gap)], [
      control("Yes", dialog.cursor == 0),
      control("No", dialog.cursor == 1)
    ])
  end

  defp body(%{question: %{kind: :text}} = dialog, _size) do
    column([width(fill()), spacing(@row_gap)], [
      control(display_text(dialog.text) <> "|", true, "monospace"),
      control("Send answer", false)
    ])
  end

  defp body(dialog, size) do
    {first, count} = visible_rows(dialog, size)

    options =
      for index <- first..(first + count - 1) do
        label = option_label(dialog, index)
        control(label, dialog.cursor == index)
      end

    column([width(fill()), spacing(@row_gap)], options ++ [control("Send answer", false)])
  end

  defp option_label(%{question: %{kind: :choice, options: options}} = dialog, index) do
    if index == length(options),
      do: "Other: " <> display_text(dialog.text) <> if(dialog.cursor == index, do: "|", else: ""),
      else: Enum.at(options, index)
  end

  defp option_label(dialog, index) do
    option = Enum.at(dialog.question.options, index)
    marker = if MapSet.member?(dialog.selected, option), do: "[x] ", else: "[ ] "
    marker <> option
  end

  defp display_text(text), do: String.slice(text, -72, 72)

  defp control(label, selected, family \\ "default") do
    el(
      [
        width(fill()),
        height(px(@row_height)),
        padding_xy(12, 8),
        Border.width(1),
        Border.rounded(6),
        Border.color(if(selected, do: @accent, else: @border)),
        Background.color(if(selected, do: @selected, else: @surface)),
        Font.size(16),
        Font.family(family),
        Font.color(@foreground)
      ],
      text(label)
    )
  end

  defp geometry({w, _h}) do
    panel_width = min(720, max(w - 2 * @outer, 1))

    %{
      panel_width: panel_width,
      x: div(w - panel_width, 2) + @padding,
      y: @outer + @padding + @header_height,
      width: max(panel_width - 2 * @padding, 1)
    }
  end

  defp visible_rows(dialog, {_w, h}) do
    available =
      h - 2 * @outer - 2 * @padding - @header_height - @footer_height - @row_height - @row_gap

    capacity = max(div(available + @row_gap, @row_height + @row_gap), 1)
    count = min(capacity, option_count(dialog))
    first = min(max(dialog.cursor - count + 1, 0), option_count(dialog) - count)
    {first, count}
  end

  defp click(%{question: nil} = dialog, _size), do: {:continue, dialog}

  defp click(dialog, size) do
    {x, y} = dialog.pointer
    geometry = geometry(size)

    if x < geometry.x or x >= geometry.x + geometry.width or y < geometry.y do
      {:continue, dialog}
    else
      click_body(dialog, x - geometry.x, y - geometry.y, geometry, size)
    end
  end

  defp click_body(%{question: %{kind: :confirm}} = dialog, x, y, geometry, _size) do
    half = div(geometry.width - @row_gap, 2)

    cond do
      y >= @row_height -> {:continue, dialog}
      x < half -> {:answer, true, %{dialog | cursor: 0}}
      x >= half + @row_gap -> {:answer, false, %{dialog | cursor: 1}}
      true -> {:continue, dialog}
    end
  end

  defp click_body(%{question: %{kind: :text}} = dialog, _x, y, _geometry, _size) do
    if y >= @row_height + @row_gap and y < 2 * @row_height + @row_gap,
      do: submit(dialog),
      else: {:continue, dialog}
  end

  defp click_body(dialog, _x, y, _geometry, size) do
    {first, count} = visible_rows(dialog, size)
    slot = div(trunc(y), @row_height + @row_gap)
    within_row = rem(trunc(y), @row_height + @row_gap) < @row_height

    cond do
      not within_row or slot > count -> {:continue, dialog}
      slot == count -> submit(dialog)
      dialog.question.kind == :multi -> {:continue, toggle(%{dialog | cursor: first + slot})}
      true -> {:continue, %{dialog | cursor: first + slot, error: nil}}
    end
  end
end
