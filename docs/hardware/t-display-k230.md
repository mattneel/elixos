# LilyGO T-Display K230: the Elixos deck

The board Elixos's K230 track (M28-M33) targets: a Canaan K230 (two C908
cores), 1 GiB LPDDR4, microSD, a 4.1" 568×1232 RM69A10 AMOLED with GT9895
touch, an SX1262 LoRa module, USB-C serial and Ethernet over USB. The full
survey, the mainline support matrix and the sources are in
[docs/notes/k230.md](../notes/k230.md); this page is what you need to put
Elixos on one.

## Where to buy

- LilyGO's shop: <https://lilygo.cc/en-us/products/t-display-k230>
  (2026-10-23: US$98.79; 433, 868, 915 and 923 MHz LoRa versions - pick your
  region's band).
- The kit with the keyboard and battery accessory:
  <https://lilygo.cc/en-us/products/t-display-k230-kit>. Elixos does not use
  the keyboard or the battery yet.
- LilyGO's sources and schematic:
  <https://github.com/Xinyuan-LilyGO/T-Display-K230_canmv_rt> (RT-Smart, the
  schematic `schematic/T-Display K230_V1.0_NEW.pdf`) and
  <https://github.com/Xinyuan-LilyGO/T-Display-K230> (their Linux overlay).
  LilyGO's wiki page disagrees with the schematic (it lists an ESP32-S3 that
  is not on the board); the schematic wins.

You also need a microSD card (2 GiB or more) and a USB-C cable to a host with
a serial terminal.

## Building and flashing

```
make deck-image        # build/k230/elixos-deck.img, the deck (M33)
make k230-bringup      # build/k230/elixos-k230-bringup.img, the M30 gate image
```

`make deck-image` needs an x86_64 build host with the tools of
`make check-tools` (melange, the riscv64 image, the Canaan firmware and the
coprocessor firmware are built or taken from cache). Write the image to the
card - double-check the device, this overwrites it:

```
lsblk                                   # find the card, e.g. /dev/sdX
sudo dd if=build/k230/elixos-deck.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

The card: Canaan's SPL at 1 MiB (and 1.5 MiB), the U-Boot environment at
`0x1e0000`, U-Boot at 2 MiB, p1 `boot` (ext4) at 30 MiB with OpenSBI, the
kernel, the initramfs, the device tree, the coprocessor's firmware and
payload, and p2 `ELIXOS` (ext4), the persistent `/priv`. The deck boots from
p2's state (`elixos.data=/dev/mmcblk0p2`); the bring-up image boots live.

## Serial console

USB-C **J2** is power and a WCH **CH342K** dual USB-UART; the host sees two
ports (on Linux `/dev/ttyACM0` and `/dev/ttyACM1`, in that order):

| Port | K230 UART | Who | Use |
|------|-----------|-----|-----|
| first (channel 0) | UART0 (IO38/IO39) | Linux | U-Boot, OpenSBI, the kernel, the shim's lines and `iex(1)>` |
| second (channel 1) | UART3 (IO50/IO51) | the little core | the AtomVM firmware's console (ADR-104) |

Both at 115200 8N1:

```
picocom -b 115200 /dev/ttyACM0      # Linux and IEx
picocom -b 115200 /dev/ttyACM1      # the coprocessor
```

The serial console is always a login REPL, also while the panel works.
USB-C **J3** is the K230's USB0 OTG port, not a console.

## Buttons

| Button | Does |
|--------|------|
| SW1 | reset |
| SW2 | power: hold 3 s to power on (the K230 PMU's power key) |
| SW3 | BOOT0: held at reset, the BootROM skips the card and waits in USB download mode (there is no eMMC); release it to boot from the card |

## Known limits per mainline release

Our kernel is mainline 7.2.9, unmodified (ADR-001); the board device tree is
ours (ADR-101). Status per subsystem (details and sources: the support matrix
in [docs/notes/k230.md](../notes/k230.md#support-matrix)):

| Subsystem | Mainline | On the deck |
|-----------|----------|-------------|
| Big core, clocks, reset, pinctrl | clk v7.2, reset v6.17, pinctrl v6.13; the K230 DT lands in v7.3-rc1 | works (one-CPU DT, our own) |
| UART0 console | `8250_dw` | works |
| SD card | `sdhci-of-dwcmshc` since v7.1; no mainline DT node | works with our DT node |
| USB0, USB1 + RTL8152B Ethernet | K230 USB PHY v7.1, generic `dwc2`; no K230 DT node | via our DT |
| Display (VO, MIPI DSI), RM69A10, GT9895, LT9611 | absent | owned by the little core (ADR-106); the panel bring-up and VO scan-out are ported but unverified on the board (below); touch and HDMI not yet |
| LoRa (SX1262) | no SX126x driver | owned by the little core (ADR-107); simulated backend so far |
| Power key, power-off (K230 PMU) | absent | owned by the little core (ADR-109); simulated backend so far |
| Wi-Fi (RTL8189FTV) | absent (out of tree) | off (ADR-108) |
| Mailbox, remoteproc | absent | not needed: the inter-core link is a polled ring (ADR-112), the little core is started by U-Boot |
| Camera, audio, KPU, GPU, VPU | absent | out of scope (ADR-110) |

What works on the deck image today, from the M33 host and QEMU tests:
Elixos boots to IEx on the serial console; the shim starts the inter-core
link (`elixos-link` on the `coproc-ring` UIO region, PROTOCOL §5, §11); the
deck view renders into the framebuffer region (§12); the coprocessor's
display driver polls it, keeps `shown` and shows `Elixos restarting` while
the BEAM is away. The panel port (`coproc/src/panel_k230.c`) brings the
RM69A10 up as LilyGO's U-Boot does (its register trace is checked against
the vendor code's on the build host) and has the K230's VO scan the region
out by itself, RGB565 at 41.8 Hz, with the status band as a second VO layer;
it has never run on a board ([docs/notes/k230-panel.md](../notes/k230-panel.md)
lists what only the board can tell). Not yet: the board backends for touch,
LoRa, the power key and UART3 (they run their simulations). Everything below
"needs the board" was written without one; the checklists find out.

## Hardware checklists

Human-run, in order. The same lists, with results, are in
[docs/ROADMAP.md](../ROADMAP.md) (M30-M33) and
[docs/notes/k230.md](../notes/k230.md#hardware-checklists).

### M30: bring-up gate (`make k230-bringup`)

- [ ] Our image boots on the big core to the shim's banner and `iex(1)>` on
  the first serial port: U-Boot, OpenSBI, the kernel log with one CPU, the
  shim's lines (docs/PROTOCOL.md §6), `iex(1)>`.
- [ ] The little core runs a trivial image we loaded: between U-Boot's
  `boot_baremetal` and OpenSBI's banner,
  `elixos coproc: hello from the little core mhartid=0x... marchid=0x...`.
  Record both values in docs/notes/k230.md.

### M31: the inter-core link (`make deck-image`)

- [ ] `elixos-shim: coproc ring /dev/uioN` and
  `elixos-shim: coproc link coproc0 10.0.3.15/24` on the console;
  `elixos-link: up coproc0 region 135168 bytes`.
- [ ] Reach across the link: at the prompt,
  `:gen_tcp.connect({10, 0, 3, 9}, 4370, [], 2_000)` returns `{:ok, _}` (the
  image has no `ping`).
- [ ] Distribution comes up over it (`Node.list()`).
- [ ] Latency and throughput recorded in docs/ROADMAP.md.

### M32: AtomVM on the little core

- [ ] The little core boots AtomVM: on the second serial port,
  `elixos_coproc: coproc@10.0.3.9 up, bundle none`.
- [ ] It joins Elixos: `Node.list()` shows `:"coproc@10.0.3.9"`.
- [ ] It survives a BEAM crash on the big core (`:erlang.halt()` at the
  prompt; the shim relaunches, the coprocessor's node stays up).

### M33: the deck

- [ ] Boots to IEx on the AMOLED (needs the scan-out port).
- [ ] Touch and the on-screen keyboard work (needs the GT9895 backend).
- [ ] `Node.list()` shows the coprocessor.
- [ ] A LoRa message arrives as a message (needs the SX1262 backend).
- [ ] Killing the BEAM keeps the panel alive and the session comes back: the
  panel shows `Elixos restarting, was gen <g> attempt <a>` within 6 s.
- [ ] Save, reboot, still there (`/priv` is p2).
- [ ] Poweroff powers off (needs the PMU backend, ADR-109).
