defmodule Elixos.Integration.M32CoprocFirmwareTest do
  @moduledoc """
  M32: the coprocessor firmware, AtomVM on bare metal (`coproc/`,
  docs/notes/coproc-firmware.md), runs the coprocessor runtime and joins over
  the §11 ring, with no OS on the little core.

  The board is stood in for by QEMU's virt machine (`-bios none`, the same
  sources built with virt's UART, CLINT and load address): its guest RAM is
  a shared file, the ring sits in it where the firmware expects it, and the
  host's `elixos-link --side big` bridges it to a TUN device in a private
  network namespace, as Elixos's would to the reserved region on the board.
  The runtime starts its simulated driver backends (the payload's
  configuration block says `ELIXOS_COPROC_DRIVERS=sim`).

  Reference limitation: QEMU is not the C908. The K230 build of the same
  sources (UART3, the little core's CLINT, uncached ring access) is only
  checked to build; the board checklist in docs/notes/k230.md covers it.
  """
  use ExUnit.Case, async: false

  alias Elixos.Test.{CoprocFirmware, RingLink}

  @moduletag :qemu
  @moduletag milestone: 32
  @moduletag timeout: 300_000
  @moduletag :tmp_dir

  test "the firmware boots the runtime, answers ping over the ring and serves a driver over distribution",
       ctx do
    cookie = :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    firmware = CoprocFirmware.boot(ctx.tmp_dir, cookie: cookie)

    # The little side waits for the big side to initialise the ring.
    CoprocFirmware.await(firmware, ~r/elixos coproc: waiting for the big core/)
    link = CoprocFirmware.link(firmware, address: "10.0.3.15/24")
    CoprocFirmware.await(firmware, ~r|elixos coproc: link up 10\.0\.3\.9/24 on the ring|)

    # (a) the runtime's up line on the firmware's UART
    CoprocFirmware.await(firmware, ~r/elixos_coproc: coproc@10\.0\.3\.9 up, bundle none\r?\n/, 60_000)

    # (b) IP over the ring
    out = RingLink.cmd(link, ["ping", "-c", "3", "-W", "5", "10.0.3.9"])
    assert out =~ "3 packets transmitted, 3 received"

    # (c) a stock Erlang node in the namespace finds coproc@10.0.3.9 through
    # the firmware's epmd, connects with the cookie and calls the display
    # driver. It neither listens nor starts an epmd of its own.
    script = ~S"""
    Node = list_to_atom("coproc@10.0.3.9"),
    io:format("ping ~p~n", [net_adm:ping(Node)]),
    io:format("status ~p~n", [erpc:call(Node, coproc_display, status, [<<"hello from the big core">>], 10000)]),
    #{status := Status, backend := Backend} = erpc:call(Node, coproc_display, info, [], 10000),
    io:format("info ~s ~p~n", [Status, Backend]),
    halt().
    """

    out =
      RingLink.cmd(
        link,
        ["erl", "-name", "elixos@10.0.3.15", "-setcookie", cookie, "-start_epmd", "false",
         "-dist_listen", "false", "-noshell", "-eval", script],
        60_000
      )

    assert out =~ "ping pong"
    assert out =~ "status ok"
    assert out =~ "info hello from the big core coproc_display_sim"
    # The simulated panel shows it on the firmware's console.
    CoprocFirmware.await(firmware, ~r/display: status hello from the big core/)
  end
end
