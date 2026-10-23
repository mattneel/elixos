defmodule Elixos.Integration.M33DeckTest do
  @moduledoc """
  M33: the Elixos side of the deck, in QEMU. Elixos renders into a
  shared-memory framebuffer the coprocessor scans out, a terminal view hosts
  the login REPL, and input arrives as messages from a simulated coprocessor.

  The framebuffer is an `ivshmem-plain` device backed by a host file
  (`QEMU.boot/2` `:deck`, `elixos.deck=pci:0x1af4:0x1110`); the test reads
  that file as the coprocessor would and decodes the panel's text with the
  renderer's own font (`Elixos.Test.DeckScreen`). The coprocessor is the host
  AtomVM with simulated drivers (M29/M32): `Elixos.Coproc.simulate(:touch,
  ...)` presses the panel there, and the event comes back over the link to
  the guest's deck.
  """
  use ExUnit.Case, async: false

  alias Elixos.Deck.{Keyboard, Layout}
  alias Elixos.Test.{AtomVM, DeckScreen, Disk, QEMU}

  @moduletag :qemu
  @moduletag milestone: 33
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  @peer ~s|:"coproc@10.0.3.9"|
  @deck_line ~r|elixos-shim: deck /sys/bus/pci/devices/[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]/resource2\n|

  setup ctx do
    %{disk: Disk.fresh!(ctx.tmp_dir), region: DeckScreen.region(ctx.tmp_dir)}
  end

  test "frames rendered by Elixos appear in the shared-memory framebuffer in the protocol's layout",
       ctx do
    vm = QEMU.boot_to_iex(ctx, disk: ctx.disk, deck: ctx.region)
    vm = QEMU.await_log(vm, @deck_line)

    first = await_screen(ctx.region, &prompt?/1)
    assert first.header.seq >= 1
    assert first.status == "Elixos  generation 0"
    assert first.header.shown == 0
    assert_damage_inside(first.header)

    # Anything written to the deck's IO server is drawn and committed: here
    # from the serial console, which names the deck as the device.
    {out, vm} = QEMU.iex(vm, ~s|IO.puts(Elixos.Deck, "hello from the serial console")|)
    assert out =~ ":ok"

    # The deck's prompt is waiting for input, so the text lands after it.
    # Pixels may be visible before their commit: wait for the commit.
    later =
      await_screen(
        ctx.region,
        &(&1.header.seq > first.header.seq and
            Enum.any?(&1.lines, fn l -> l =~ "hello from the serial console" end))
      )

    assert_damage_inside(later.header)
    # The commit's damage is the rows that changed, not the whole panel.
    assert later.header.damage_h < Layout.height()
    {_, ty, _, th} = Layout.terminal_rect()

    assert later.header.damage_y >= ty and
             later.header.damage_y + later.header.damage_h <= ty + th

    {out, vm} = QEMU.iex(vm, "Elixos.Deck.info().seq")
    [seq] = Regex.run(~r/^(\d+)$/m, out, capture: :all_but_first)
    assert String.to_integer(seq) >= later.header.seq

    power_off(vm)
  end

  test "boot lands in the terminal view hosting the login REPL while the serial console stays available",
       ctx do
    vm = QEMU.boot_to_iex(ctx, disk: ctx.disk, deck: ctx.region)
    screen = await_screen(ctx.region, &prompt?/1)
    text = DeckScreen.text(screen)
    assert text =~ "Interactive Elixir"
    assert Enum.any?(screen.lines, &(&1 == "iex(1)>"))

    # The serial console is its own session and still evaluates.
    {out, vm} = QEMU.iex(vm, "1 + 1")
    assert out =~ ~r/^2$/m

    # The deck's session is another one, still at its first prompt.
    {out, vm} =
      QEMU.iex(vm, "Elixos.Deck.lines() |> Enum.any?(&String.starts_with?(&1, \"iex(1)> \"))")

    assert out =~ "true"
    assert DeckScreen.read(ctx.region).lines == screen.lines

    power_off(vm)
  end

  test "simulated coprocessor touch events drive the on-screen keyboard into the REPL session",
       ctx do
    host_port = AtomVM.free_port()

    vm =
      QEMU.boot_to_iex(ctx,
        disk: ctx.disk,
        deck: ctx.region,
        coproc: {4370, host_port},
        append: ["ip=:::::eth0:dhcp", "elixos.coproc_link=eth1,10.0.3.15/24"]
      )

    await_screen(ctx.region, &prompt?/1)
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Coproc.configure(node: #{@peer}, port: 4370)|)
    assert out =~ ~r/\{:ok, "[0-9a-f]{48}"\}/
    {out, vm} = QEMU.iex(vm, ~s|File.read!("/priv/coproc/cookie")|)
    [cookie] = Regex.run(~r/"([0-9a-f]{48})\\n"/, out, capture: :all_but_first)

    atomvm =
      AtomVM.start(Path.join(ctx.tmp_dir, "atomvm"),
        node: :"coproc@10.0.3.9",
        port: host_port,
        cookie: cookie
      )

    AtomVM.await_up(atomvm)

    {out, vm} =
      QEMU.iex(
        vm,
        "Enum.find_value(1..600, fn _ -> if Elixos.Coproc.status().connected and Elixos.Deck.info().touch, " <>
          "do: :ready, else: (Process.sleep(100); nil) end)",
        90_000
      )

    assert out =~ ":ready"

    # The panel is pressed where the keys are drawn, on the coprocessor.
    taps =
      "1+1"
      |> String.graphemes()
      |> Enum.flat_map(&taps/1)
      |> Kernel.++([Keyboard.center(:lower, :enter)])

    {out, vm} =
      QEMU.iex(
        vm,
        "for {x, y} <- #{inspect(taps)}, a <- [:down, :up], do: Elixos.Coproc.simulate(:touch, {a, x, y})",
        60_000
      )

    refute out =~ "error"

    screen =
      await_screen(ctx.region, &(DeckScreen.text(&1) =~ ~r/> 1\+1\n2\niex\([^\n]*?2\)?>/), 60_000)

    assert DeckScreen.text(screen) =~ ~r/iex\(1\)> 1\+1\n2\n/
    assert AtomVM.output(atomvm) =~ "elixos_coproc"

    power_off(vm)
  end

  test "the terminal view shows rescue status when booted into rescue", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: ctx.disk, deck: ctx.region, append: ["elixos.safe"])
    vm = QEMU.await_log(vm, @deck_line)
    screen = await_screen(ctx.region, &prompt?/1)
    assert screen.status =~ "rescue"
    assert screen.status =~ "generation 0"

    assert DeckScreen.pixel(File.read!(ctx.region), {1, 1}) ==
             Elixos.Deck.Paint.status_background(:rescue)

    # Rescue stays reachable on the serial console as well.
    {out, vm} = QEMU.iex(vm, "Elixos.info().mode")
    assert out =~ ":rescue"
    power_off(vm)
  end

  ## Helpers

  # Taps typing one character: through shift or the symbol layer as needed.
  defp taps(char) do
    case Keyboard.locate(char) do
      {:lower, action} ->
        [Keyboard.center(:lower, action)]

      {:upper, action} ->
        [Keyboard.center(:lower, :shift), Keyboard.center(:upper, action)]

      {:symbols, action} ->
        [
          Keyboard.center(:lower, :symbols),
          Keyboard.center(:symbols, action),
          Keyboard.center(:symbols, :letters)
        ]
    end
  end

  defp prompt?(screen), do: Enum.any?(screen.lines, &(&1 =~ ~r/^iex\(\d+\)>$/))

  defp assert_damage_inside(%{damage_x: x, damage_y: y, damage_w: w, damage_h: h}) do
    assert w > 0 and h > 0
    assert x + w <= Layout.width() and y + h <= Layout.height()
  end

  # Polls the backing file until `fun` holds for the decoded panel.
  defp await_screen(region, fun, timeout \\ 120_000) do
    deadline =
      System.monotonic_time(:millisecond) +
        timeout * String.to_integer(System.get_env("ELIXOS_QEMU_SLOWDOWN", "1"))

    poll(region, fun, deadline)
  end

  defp poll(region, fun, deadline) do
    bytes = File.read!(region)
    screen = if DeckScreen.valid?(bytes), do: DeckScreen.decode(bytes)

    cond do
      screen && fun.(screen) ->
        screen

      System.monotonic_time(:millisecond) > deadline ->
        flunk(
          "the deck never showed it; it shows:\n" <>
            if(screen,
              do: screen.status <> "\n" <> DeckScreen.text(screen),
              else: "(no valid header)"
            )
        )

      true ->
        Process.sleep(100)
        poll(region, fun, deadline)
    end
  end

  defp power_off(vm) do
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end
end
