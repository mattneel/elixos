defmodule Elixos.CoprocDisplayK230Test do
  @moduledoc """
  M33: the board's display backend (os/src/coproc_display_k230.erl), the
  coprocessor's half of the deck framebuffer (docs/PROTOCOL.md §12): it polls
  the header, pushes what changed with the status line laid over it, and
  stores `shown`.

  The hardware scan-out needs the board: there the K230's VO scans the region
  out itself and the status band is a VO layer of its own
  (coproc/src/panel_k230.c, checked on the build host against the vendor's
  register trace by coproc/test/panel_trace/run.sh). Here the region is a
  plain file and the panel a mirror file that receives every push with the
  status band composed in (`ELIXOS_COPROC_DECK_REGION`,
  `ELIXOS_COPROC_DECK_PANEL`), on AtomVM's Unix build with
  `ELIXOS_COPROC_DRIVERS=sim,display=k230`. The pure bookkeeping
  (`:coproc_deck_scanout`) and the coprocessor's font (`:coproc_font`,
  generated from Spleen) are also checked on the BEAM.
  """
  use ExUnit.Case, async: false

  alias Elixos.Coproc
  alias Elixos.Coproc.Display
  alias Elixos.Test.AtomVM

  @moduletag milestone: 33

  @width 568
  @height 1232
  @stride 1136
  @header 4096
  @pixels @stride * @height

  describe "the bookkeeping" do
    test "header/1 accepts exactly the protocol's header" do
      header = header(7, {1, 2, 3, 4}, 6)

      assert :coproc_deck_scanout.header(header) ==
               {:ok, %{seq: 7, damage: {1, 2, 3, 4}, shown: 6}}

      <<a::binary-size(16), _stride::32, rest::binary>> = header
      assert :coproc_deck_scanout.header(a <> <<1137::32-little>> <> rest) == :invalid
      assert :coproc_deck_scanout.header(<<0::size(48 * 8)>>) == :invalid
    end

    test "plan/2 pushes the damage, the whole panel, or nothing" do
      full = {0, 0, @width, @height}
      plan = &:coproc_deck_scanout.plan/2
      at = fn seq, shown, damage -> %{seq: seq, shown: shown, damage: damage} end
      # First poll after a start: the panel's contents are unknown.
      assert plan.(at.(5, 5, {1, 1, 1, 1}), true) == {:push, full, 5}
      assert plan.(at.(5, 5, {1, 1, 1, 1}), false) == :idle
      assert plan.(at.(6, 5, {10, 20, 30, 40}), false) == {:push, {10, 20, 30, 40}, 6}
      # Several commits missed: their union is unknown.
      assert plan.(at.(8, 5, {10, 20, 30, 40}), false) == {:push, full, 8}
      # A damage rectangle outside the panel is never trusted.
      assert plan.(at.(6, 5, {560, 0, 9, 1}), false) == {:push, full, 6}
      assert plan.(at.(6, 5, {0, 0, 0, 1}), false) == {:push, full, 6}
      # seq wraps at 2^32.
      assert plan.(at.(0, 0xFFFF_FFFF, {0, 0, 1, 1}), false) == {:push, {0, 0, 1, 1}, 0}
    end

    test "strips/1 and rows/1 address the region" do
      assert :coproc_deck_scanout.strips({0, 0, 568, 130}) ==
               [{0, 0, 568, 64}, {0, 64, 568, 64}, {0, 128, 568, 2}]

      assert :coproc_deck_scanout.rows({0, 3, 568, 2}) == [{@header + 3 * @stride, 2 * @stride}]

      assert :coproc_deck_scanout.rows({5, 3, 2, 2}) == [
               {@header + 3 * @stride + 10, 4},
               {@header + 4 * @stride + 10, 4}
             ]
    end

    test "the coprocessor's font is Elixos.Deck.Font for printable ASCII" do
      for c <- 32..126 do
        rows = for <<row::16 <- :coproc_font.glyph(c)>>, do: Bitwise.bsr(row, 4)
        assert List.to_tuple(rows) == Elixos.Deck.Font.glyph(c), "glyph #{c}"
      end

      assert :coproc_font.glyph(200) == :coproc_font.glyph(??)
    end

    test "the overlay draws the status line in the status band and compose/3 lays it over" do
      assert :coproc_deck_scanout.overlay("") == :none
      overlay = :coproc_deck_scanout.overlay("A")
      assert byte_size(overlay) == 28 * @stride
      # Row 2 + 24 rows of glyph from x = 4; elsewhere the background.
      background = <<0x7800::16-little>>
      assert binary_part(overlay, 0, 2) == background
      text = for y <- 0..23, x <- 0..11, into: %{}, do: {{x, y}, pixel(overlay, 4 + x, 2 + y)}
      glyph = Elixos.Deck.Font.glyph(?A)

      for {{x, y}, value} <- text do
        on = Bitwise.band(Bitwise.bsr(elem(glyph, y), 11 - x), 1) == 1
        assert value == if(on, do: 0xFFFF, else: 0x7800)
      end

      pixels = :binary.copy(<<0x1234::16-little>>, 10 * 30)
      composed = :coproc_deck_scanout.compose({100, 20, 10, 30}, pixels, overlay)
      # Rows 20-27 come from the overlay, 28-49 from the framebuffer.
      assert binary_part(composed, 0, 20) == binary_part(overlay, 20 * @stride + 200, 20)
      assert binary_part(composed, 8 * 20, 20) == :binary.copy(<<0x1234::16-little>>, 10)
      assert :coproc_deck_scanout.compose({0, 28, 10, 1}, "xx", overlay) == "xx"
      assert :coproc_deck_scanout.compose({0, 0, 10, 1}, "xx", :none) == "xx"
    end
  end

  describe "on AtomVM, with a file region and a mirror panel" do
    @describetag :tmp_dir

    setup ctx do
      region = Path.join(ctx.tmp_dir, "region")
      panel = Path.join(ctx.tmp_dir, "panel")
      # Elixos initialised the region and committed once (seq 1).
      File.write!(
        region,
        header(1, {0, 0, @width, @height}, 0) <> :binary.copy(<<0>>, @header - 48) <> pattern(0)
      )

      cookie = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

      vm =
        AtomVM.start(Path.join(ctx.tmp_dir, "atomvm"),
          cookie: cookie,
          drivers: "sim,display=k230",
          env: [{"ELIXOS_COPROC_DECK_REGION", region}, {"ELIXOS_COPROC_DECK_PANEL", panel}]
        )

      AtomVM.await_up(vm)

      start_supervised!(
        {Coproc,
         [
           node: vm.node,
           port: vm.port,
           listen: {{127, 0, 0, 1}, AtomVM.free_port()},
           cookie: cookie,
           reconnect_ms: 200
         ]}
      )

      assert eventually(fn -> Coproc.status().connected end)
      %{region: region, panel: panel, vm: vm}
    end

    test "the first poll pushes the whole frame under the starting status", ctx do
      assert %{backend: :coproc_display_k230} =
               Coproc.driver_call(:coproc_driver, :info, [:coproc_display])

      assert %{region: :file, panel: :file, status: "Elixos starting"} = Display.info()
      assert eventually(fn -> shown(ctx.region) == 1 end)
      assert eventually(fn -> panel(ctx.panel) == expected(ctx.region, "Elixos starting") end)
    end

    test "commits are pushed by their damage, missed ones whole, and shown follows seq", ctx do
      assert Display.lease(10_000, "gen 1 attempt 1") == :ok

      assert eventually(fn ->
               shown(ctx.region) == 1 and panel(ctx.panel) == expected(ctx.region, "")
             end)

      pushes = Display.info().pushes

      # One commit: a rectangle changes.
      commit(ctx.region, 2, {100, 200, 50, 70}, 0xF800)
      assert eventually(fn -> shown(ctx.region) == 2 end)
      assert panel(ctx.panel) == expected(ctx.region, "")
      assert %{last_region: {100, 200, 50, 70}} = Display.info()
      assert Display.info().pushes == pushes + 1

      # Two commits behind its back: seq jumps from 2 to 4, and the second
      # commit's damage is all the header still says, so the whole frame
      # goes out. (Commit 3's pixels are written, its seq never seen.)
      commit(ctx.region, 3, {0, 1000, 568, 10}, 0x07E0, write_only: true)
      commit(ctx.region, 4, {7, 7, 1, 1}, 0x001F)
      assert eventually(fn -> shown(ctx.region) == 4 end)
      assert panel(ctx.panel) == expected(ctx.region, "")
      assert %{last_region: {0, 0, 568, 1232}} = Display.info()
    end

    test "a lapsed lease draws the status band over the last frame; renewal restores it", ctx do
      assert Display.lease(300, "gen 2 attempt 1") == :ok
      assert eventually(fn -> panel(ctx.panel) == expected(ctx.region, "") end)
      status = "Elixos restarting, was gen 2 attempt 1"
      assert eventually(fn -> Display.info().status == status end)
      assert eventually(fn -> panel(ctx.panel) == expected(ctx.region, status) end)

      # The status stays over new frames until Elixos is back.
      commit(ctx.region, 2, {0, 10, 568, 40}, 0xFFE0)
      assert eventually(fn -> shown(ctx.region) == 2 end)
      assert panel(ctx.panel) == expected(ctx.region, status)

      assert Display.lease(10_000, "gen 2 attempt 2") == :ok
      assert eventually(fn -> panel(ctx.panel) == expected(ctx.region, "") end)
    end
  end

  ## Helpers

  defp header(seq, {x, y, w, h}, shown) do
    <<0x44584C45::32-little, 1::32-little, @width::32-little, @height::32-little,
      @stride::32-little, 1::32-little, seq::32-little, x::32-little, y::32-little, w::32-little,
      h::32-little, shown::32-little>>
  end

  # A frame whose every row differs.
  defp pattern(base) do
    for y <- 0..(@height - 1),
        into: <<>>,
        do: :binary.copy(<<rem(base + y * 37, 65_536)::16-little>>, @width)
  end

  # Elixos's side of §12: pixels, damage, then seq.
  defp commit(region, seq, {x, y, w, h}, colour, opts \\ []) do
    {:ok, fd} = :file.open(region, [:read, :write, :binary, :raw])

    for row <- y..(y + h - 1),
        do:
          :ok =
            :file.pwrite(
              fd,
              @header + row * @stride + 2 * x,
              :binary.copy(<<colour::16-little>>, w)
            )

    unless opts[:write_only] do
      :ok = :file.pwrite(fd, 28, <<x::32-little, y::32-little, w::32-little, h::32-little>>)
      :ok = :file.pwrite(fd, 24, <<seq::32-little>>)
    end

    :ok = :file.close(fd)
  end

  defp shown(region) do
    {:ok, fd} = :file.open(region, [:read, :binary, :raw])
    {:ok, <<shown::32-little>>} = :file.pread(fd, 44, 4)
    :ok = :file.close(fd)
    shown
  end

  defp panel(path) do
    case File.read(path) do
      {:ok, data} when byte_size(data) == @pixels -> data
      _ -> nil
    end
  end

  defp expected(region, status) do
    pixels = binary_part(File.read!(region), @header, @pixels)

    case :coproc_deck_scanout.overlay(status) do
      :none -> pixels
      overlay -> overlay <> binary_part(pixels, byte_size(overlay), @pixels - byte_size(overlay))
    end
  end

  defp pixel(overlay, x, y) do
    <<value::16-little>> = binary_part(overlay, y * @stride + 2 * x, 2)
    value
  end

  defp eventually(fun, deadline \\ System.monotonic_time(:millisecond) + 15_000) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) > deadline -> false
      true -> Process.sleep(50) && eventually(fun, deadline)
    end
  end
end
