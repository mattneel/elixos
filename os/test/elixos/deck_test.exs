defmodule Elixos.DeckTest do
  @moduledoc """
  M33: the deck's pieces on the host - the font, the terminal grid, the
  on-screen keyboard - and `Elixos.Deck` itself driving the real
  `elixos-deck-fb` on a plain region file, read back with the tests' screen
  reader (`Elixos.Test.DeckScreen`). Building the helper is host
  orchestration, so a candidate's portable suite (`Elixos.Candidate`)
  excludes those tests, as it does the ring's.
  """
  use ExUnit.Case, async: false

  alias Elixos.Deck
  alias Elixos.Deck.{Font, Keyboard, Layout, Terminal}
  alias Elixos.Test.DeckScreen

  @moduletag milestone: 33

  describe "font" do
    test "every printable ASCII character has its own glyph" do
      ascii = for c <- 0x20..0x7E, do: c
      assert Enum.all?(ascii, &Font.has?/1)
      glyphs = Enum.map(ascii, &Font.glyph/1)
      assert length(Enum.uniq(glyphs)) == length(ascii)
      assert {12, 24} == {Font.width(), Font.height()}
      assert tuple_size(Font.glyph(?A)) == 24
      assert Enum.all?(Tuple.to_list(Font.glyph(?A)), &(&1 in 0..0xFFF))
      # Anything else draws as a question mark.
      assert Font.glyph(0x1F600) == Font.glyph(??)
    end
  end

  describe "terminal" do
    test "prints, wraps at the margin and scrolls" do
      term = Terminal.new(5, 3) |> Terminal.write("abcde")
      assert Terminal.lines(term) == ["abcde", "     ", "     "]
      # The cursor rests on the margin until the next character.
      assert Terminal.cursor(term) == {0, 4}
      term = Terminal.write(term, "fg\nh\ni")
      assert Terminal.lines(term) == ["fg   ", "h    ", "i    "]
      assert {%{scrolled: 1}, _} = Terminal.take_damage(term)
    end

    test "carriage return, backspace, tab and controls" do
      term = Terminal.new(20, 2) |> Terminal.write("abc\rX\tY\b\bZ\a")
      assert hd(Terminal.lines(term)) == "Xbc    ZY           "
      # Backspace from column 0 goes to the end of the previous row.
      term = Terminal.new(4, 2) |> Terminal.write("abcde\b\b\b")
      assert Terminal.cursor(term) == {0, 2}
    end

    test "SGR is dropped, erase and cursor movement work" do
      term = Terminal.new(10, 3) |> Terminal.write("\e[1;33miex\e[0m(1)> \e]0;title\a")
      assert hd(Terminal.lines(term)) == "iex(1)>   "
      term = Terminal.write(term, "\e[1;4Hzz\e[K")
      assert hd(Terminal.lines(term)) == "iexzz     "
      term = Terminal.write(term, "\e[2J")
      assert Enum.all?(Terminal.lines(term), &(&1 == "          "))
      term = Terminal.write(term, "\e[3;2Hq\e[Ar\e[2Ds")
      assert Terminal.lines(term) == ["          ", " sr       ", " q        "]
    end

    test "damage is the changed cells, per row" do
      term = Terminal.new(10, 3)
      {_, term} = Terminal.take_damage(Terminal.write(term, "x"))
      term = Terminal.write(term, "\nab")
      assert {%{scrolled: 0, dirty: [{1, 0, 1}]}, term} = Terminal.take_damage(term)
      assert {%{scrolled: 0, dirty: []}, _} = Terminal.take_damage(term)
    end

    test "invalid UTF-8 shows as a question mark" do
      assert Terminal.new(3, 1) |> Terminal.write(<<?a, 0xFF, ?b>>) |> Terminal.lines() == ["a?b"]
    end
  end

  describe "keyboard" do
    test "lies below the terminal, inside the panel" do
      {_, ty, _, th} = Layout.terminal_rect()
      assert ty + th <= Layout.keyboard_top()
      assert Layout.columns() == 46 and Layout.rows() == 33

      for layer <- [:lower, :upper, :symbols], %{rect: {x, y, w, h}} <- Keyboard.keys(layer) do
        assert x >= 0 and x + w <= Layout.width()
        assert y >= Layout.keyboard_top() and y + h <= Layout.height()
      end
    end

    test "a tap types the key under it, on release" do
      {x, y} = Keyboard.center(:lower, {:char, "1"})
      kb = Keyboard.new()
      assert {kb, nil, false} = Keyboard.touch(kb, {:touch, :down, x, y})
      assert {kb, {:char, "1"}, false} = Keyboard.touch(kb, {:touch, :up, x, y})
      assert {_, nil, false} = Keyboard.touch(kb, {:touch, :up, x, y})
      assert Keyboard.hit(:lower, 0, 0) == nil
    end

    test "shift lasts one letter; the symbol layer stays until abc" do
      tap = fn kb, layer, action ->
        {x, y} = Keyboard.center(layer, action)
        {kb, nil, _} = Keyboard.touch(kb, {:touch, :down, x, y})
        Keyboard.touch(kb, {:touch, :up, x, y})
      end

      kb = Keyboard.new()
      assert {kb, nil, true} = tap.(kb, :lower, :shift)
      assert kb.layer == :upper
      assert {kb, {:char, "Q"}, true} = tap.(kb, :upper, {:char, "Q"})
      assert kb.layer == :lower
      {kb, nil, true} = tap.(kb, :lower, :symbols)
      assert {kb, {:char, "+"}, false} = tap.(kb, :symbols, {:char, "+"})
      assert {kb, :backspace, false} = tap.(kb, :symbols, :backspace)
      assert {%{layer: :lower}, nil, true} = tap.(kb, :symbols, :letters)
    end

    test "every printable ASCII character can be typed" do
      for c <- 0x20..0x7E do
        char = <<c>>
        {layer, action} = Keyboard.locate(char)

        assert %{action: ^action} =
                 Keyboard.hit(
                   layer,
                   elem(Keyboard.center(layer, action), 0),
                   elem(Keyboard.center(layer, action), 1)
                 )
      end
    end
  end

  describe "the deck on a region file" do
    @describetag :tmp_dir
    @describetag :host_orchestration

    setup ctx do
      region = DeckScreen.region(ctx.tmp_dir)
      %{region: region}
    end

    test "draws its first frame in the protocol's layout", ctx do
      deck =
        start_deck(ctx.region,
          shell: {__MODULE__, :echo_shell, [self(), "say> "]},
          status: "Elixos  rescue  generation 0",
          mode: :rescue
        )

      assert_receive {:shell, _pid}, 5_000
      await_screen(ctx.region, &(&1.lines |> hd() == "say>"))

      screen = DeckScreen.read(ctx.region)
      assert screen.status == "Elixos  rescue  generation 0"
      assert screen.header.seq >= 1
      assert screen.header.shown == 0
      # The status bar is the rescue red; the keyboard's keys are drawn.
      bytes = File.read!(ctx.region)
      assert DeckScreen.pixel(bytes, {1, 1}) == Elixos.Deck.Paint.status_background(:rescue)
      {kx, ky} = Keyboard.center(:lower, {:char, "q"})
      assert DeckScreen.pixel(bytes, {kx - 20, ky - 30}) == Elixos.Deck.Paint.key()
      assert Deck.lines(deck) |> hd() |> String.trim_trailing() == "say>"
    end

    test "touch types into the session; a keystroke commits only its cells", ctx do
      deck = start_deck(ctx.region, shell: {__MODULE__, :echo_shell, [self(), "say> "]})
      assert_receive {:shell, _pid}, 5_000
      # Settled: the prompt is drawn and every commit acknowledged.
      before =
        await_screen(
          ctx.region,
          &(hd(&1.lines) == "say>" and &1.header.seq == Deck.info(deck).seq)
        ).header

      tap(deck, :lower, {:char, "h"})
      # Pixels may be visible before their commit: wait for the commit.
      after_h =
        await_screen(ctx.region, &(&1.header.seq > before.seq and hd(&1.lines) == "say> h")).header

      assert after_h.seq > before.seq
      # One character and the cursor: a rectangle one cell high, not the frame.
      assert after_h.damage_h == Font.height()
      assert after_h.damage_w <= 3 * Font.width()
      {_, ty} = Layout.terminal_origin()
      assert after_h.damage_y == ty

      for char <- String.graphemes("i(1+1)"), do: type(deck, char)

      tap(deck, :lower, :backspace)
      tap(deck, :lower, :enter)
      assert_receive {:line, "hi(1+1\n"}, 5_000
      screen = await_screen(ctx.region, &("got hi(1+1" in &1.lines))
      assert Enum.take(screen.lines, 3) == ["say> hi(1+1", "got hi(1+1", "say>"]
    end

    test "hosts an IEx session as its group leader", ctx do
      deck = start_deck(ctx.region, shell: {Elixos.Boot.Login, :start_iex, [{:host, nil}]})
      await_screen(ctx.region, &Enum.any?(&1.lines, fn l -> l =~ ~r/^iex\(\d+\)>$/ end))

      for char <- String.graphemes("1+1"), do: type(deck, char)
      tap(deck, :lower, :enter)
      screen = await_screen(ctx.region, &Enum.any?(&1.lines, fn l -> l =~ ~r/^iex\(2\)>$/ end))
      text = DeckScreen.text(screen)
      assert text =~ "iex(1)> 1+1\n2\n"
      assert text =~ "Interactive Elixir"
    end

    test "long output scrolls the grid", ctx do
      deck = start_deck(ctx.region, shell: {__MODULE__, :echo_shell, [self(), "> "]})
      assert_receive {:shell, shell}, 5_000
      send(shell, {:print, Enum.map_join(1..40, "", &"line #{&1}\n")})
      screen = await_screen(ctx.region, &("line 40" in &1.lines))
      assert screen.header.damage_y <= elem(Layout.terminal_origin(), 1)
      assert hd(screen.lines) == "line 9"
      assert Enum.at(screen.lines, 31) == "line 40"
      # The deck learns of a commit from the helper's acknowledgement.
      assert Enum.find_value(1..100, fn _ ->
               %{seq: seq, touch: false} = Deck.info(deck)
               seq == DeckScreen.read(ctx.region).header.seq || (Process.sleep(10) && nil)
             end)
    end

    test "without a region the deck does not start" do
      assert Deck.start_link(region: nil, name: :no_deck) == :ignore
    end

    test "a helper that fails stops the deck alone", ctx do
      Process.flag(:trap_exit, true)
      File.write!(ctx.region, "short")

      {:ok, pid} =
        Deck.start_link(
          region: ctx.region,
          helper: DeckScreen.helper(),
          name: :failing_deck,
          shell: {__MODULE__, :echo_shell, [self(), "> "]}
        )

      assert_receive {:EXIT, ^pid, :normal}, 5_000
    end
  end

  ## Helpers

  defp start_deck(region, opts) do
    name = :"deck_#{System.unique_integer([:positive])}"
    start_supervised!({Deck, [region: region, helper: DeckScreen.helper(), name: name] ++ opts})
  end

  defp tap(deck, layer, action) do
    {x, y} = Keyboard.center(layer, action)
    Deck.touch(deck, {:touch, :down, x, y})
    Deck.touch(deck, {:touch, :up, x, y})
  end

  defp type(deck, char) do
    {layer, action} = Keyboard.locate(char)
    if layer == :upper, do: tap(deck, :lower, :shift)
    if layer == :symbols, do: tap(deck, :lower, :symbols)
    tap(deck, layer, action)
    if layer == :symbols, do: tap(deck, :symbols, :letters)
  end

  # Polls the region until `fun` holds for what it shows (the helper may not
  # even have initialised the header yet).
  defp await_screen(region, fun, deadline \\ System.monotonic_time(:millisecond) + 10_000) do
    bytes = File.read!(region)
    screen = if DeckScreen.valid?(bytes), do: DeckScreen.decode(bytes)

    cond do
      screen && fun.(screen) ->
        screen

      System.monotonic_time(:millisecond) > deadline ->
        flunk(
          "the deck never showed it; it shows:\n#{inspect(screen && DeckScreen.text(screen))}"
        )

      true ->
        Process.sleep(20)
        await_screen(region, fun, deadline)
    end
  end

  @doc false
  # A minimal shell: prompts, reports each line to the test and echoes it.
  def echo_shell(test, prompt) do
    spawn_link(fn ->
      send(test, {:shell, self()})
      echo_loop(test, prompt)
    end)
  end

  defp echo_loop(test, prompt) do
    receive do
      {:print, text} -> IO.write(text)
    after
      0 -> :ok
    end

    task = Task.async(fn -> IO.gets(prompt) end)

    line =
      receive_line(task)

    send(test, {:line, line})
    IO.write("got " <> line)
    echo_loop(test, prompt)
  end

  defp receive_line(task) do
    receive do
      {ref, line} when ref == task.ref ->
        Process.demonitor(ref, [:flush])
        line

      {:print, text} ->
        IO.write(text)
        receive_line(task)
    end
  end
end
