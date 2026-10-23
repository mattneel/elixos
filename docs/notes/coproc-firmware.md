# The coprocessor firmware: AtomVM on bare metal (M32)

The little core of the T-Display K230 (C908, rv64gc, no vector, M-mode, no
OS) runs AtomVM directly: `coproc/` is the platform port, built by
`melange/coproc-firmware.yaml` (`scripts/build-coproc-firmware.sh`,
outputs in `build/coproc/`). The same sources build for QEMU's virt machine,
where `os/test/integration/m32_coproc_firmware_test.exs` checks it.

## Pieces

| File | Does |
|------|------|
| `coproc/src/start.S` | entry at the image's first byte: mtvec, FPU on, gp, stack, zero `.tbss`/`.bss` |
| `coproc/src/hw.c` | UART console (16550, polled, read and write), clock (`rdtime` or CLINT mtime), idle (`wfi` on a one-shot mtimecmp), `sbrk`, picolibc stdio, traps |
| `coproc/src/ramfs.c` | RAM file system behind `open/read/write/close/unlink/rename/fsync`, so `atomvm:posix_*` and the runtime work unchanged |
| `coproc/src/payload.c`, `coproc/tools/mkpayload.py` | the payload: environment block, AVM packs, files |
| `coproc/src/ring.c` | §11 ring, little side; `coproc/test/ring_vectors_test.c` runs `spec/ring.vectors` on the host |
| `coproc/src/net.c` | lwIP 2.2.1 (raw API, NO_SYS) netif over the ring: reads A, writes B, bare IPv4, no link layer |
| `coproc/src/sys.c`, `otp_socket_platform.c`, `otp_net_lwip_raw.c`, `platform_nifs.c` | AtomVM's `sys_*` contract; the lwIP event queue; `net:getaddrinfo`; `atomvm:platform/0` = `elixos_coproc`; Mbed TLS entropy |
| `coproc/src/platform_nifs.c` (M33) | `coproc_k230:fb_read/2`, `fb_write32/2` on the §12 region at `COPROC_FB_ADDR`; `panel_open/0`, `panel_status/1`; `touch_open/0`, `touch_read/0`; `lora_open/1`, `lora_send/1`, `lora_poll/0`; `power_open/0`, `power_poll/0`, `power_off/0`; `console_read/0`, `console_write/1` |
| `coproc/src/panel_k230.c`, `k230_mmio.c` (M33) | the RM69A10 bring-up (LilyGO's U-Boot register sequence) and the VO scan-out of the §12 region; the status band as a second VO layer. Register access goes through `k230_mmio.h`, so `coproc/test/panel_trace/run.sh` checks the port's register trace against the vendor code's on the build host (docs/notes/k230-panel.md). `COPROC_PANEL_K230=0` (QEMU virt): `{error, no_panel}` |
| `coproc/src/touch_k230.c`, `lora_k230.c`, `power_k230.c`, `uart_k230.c`, with `k230_io.c` (pads, GPIO, clocks), `k230_i2c.c` (DesignWare I2C), `k230_spi.c` (DesignWare SSI) (M33) | the GT9895 touch controller, the SX1262 LoRa module, the PMU's power key and power-off, UART3's set-up: "Board drivers" below. `COPROC_K230_DEVICES=0` (QEMU virt): `{error, no_device}` |
| `coproc/src/main.c` | boot, then runs the VM again whenever the start module returns (a deploy ends the VM, ADR-099) |

libc is picolibc (Alpine `picolibc-riscv-none-elf`, lp64d multilib, medany).
Mbed TLS 3.6.7 is built crypto-only (`mbedtls_coproc_config.h`): md5 for the
dist handshake, sha256 for bundle digests, CTR-DRBG for
`crypto:strong_rand_bytes/1`. atomvmlib.avm is built in the same recipe with
the same patches.

## Memory map

| Range (K230) | QEMU virt | Content |
|--------------|-----------|---------|
| `0x07000000 + [0, 4 MiB)` | `0x80000000 + …` | image (≈ 750 KiB loaded, 140 KiB `.bss`, 256 KiB stack) |
| `+ [4 MiB, 6 MiB)` | same | payload (≈ 500 KiB: runtime + atomvmlib + config) |
| `+ [6 MiB, 16 MiB)` | same | malloc arena (10 MiB) |
| `0x08000000`, `0x21000` bytes | `0x81000000` | §11 ring (2 × 64 KiB capacity), the board DT's no-map shared region |
| `0x08100000`, `0x180000` bytes | `0x81100000` | §12 deck framebuffer (M33), the board DT's `deck-fb` region |

Every address is a build parameter (`-DCOPROC_…`, `coproc/CMakeLists.txt`,
documented in `coproc/src/board.h`), defaulting per `COPROC_TARGET`.

On the board, U-Boot must load both files: `coproc-k230.bin` at
`0x7000000` and the payload at `0x7400000`, then
`boot_baremetal 0 0x7000000 <size>`.

## Payload

`mkpayload.py -o payload.bin --env K=V … --avm runtime.avm --avm atomvmlib.avm
--file cookie=<path>`; the first pack holds the start module. Configuration
(what the Unix build reads from the environment):

| Key | Example |
|-----|---------|
| `ELIXOS_COPROC_NODE` | `coproc@10.0.3.9` |
| `ELIXOS_COPROC_PORT` | `4370` |
| `ELIXOS_COPROC_COOKIE_FILE` | `cookie` (a ramfs file from `--file`) |
| `ELIXOS_COPROC_BUNDLE` | `bundle.avm` (absent: no bundle) |
| `ELIXOS_COPROC_DRIVERS` | `sim` (QEMU, host tests), `k230` (the deck image: the board backends of all five), or per subsystem `sim,display=k230` |
| `ELIXOS_COPROC_LORA_FREQUENCY` | Hz, default `915000000` (LilyGO's SX1262 build); the 433, 868 and 923 MHz SKUs need theirs (`coproc_lora_k230`) |
| `ELIXOS_COPROC_DECK_REGION` | unset on the board (the region at `COPROC_FB_ADDR`); a file path in host tests |
| `ELIXOS_COPROC_DECK_PANEL` | unset on the board (`panel_k230.c`); a mirror file path in host tests |
| `ELIXOS_COPROC_ADDRESS` | `10.0.3.9/24` (the firmware's own, read by C) |
| `ELIXOS_COPROC_SEED` | hex, mixed into the entropy pool |

`erlang:system_info(coproc_heap)` answers `{UsedBytes, ArenaBytes}`.

## What took time

- No `cc1plus` in Alpine's cross GCC: libAtomVM's `project()` enables C++;
  the toolchain file declares a forced, never-used C++ compiler.
- Alpine's riscv-none-elf **libgcc is medlow**: `__clzdi2` cannot reach its
  table above 2 GiB (QEMU loads at `0x80000000`); `hw.c` replaces it.
  picolibc itself is medany.
- picolibc has `ssize_t` as `long` but lwIP typedefs `int` unless
  `SSIZE_MAX` is visible: `arch/cc.h` defines it.
- otp_socket.c does not build with `LWIP_IGMP 0` (upstream bug); IGMP is on.
- `melange/atomvm-baremetal/0001`: lwIP err/recv callbacks for closed or
  not-yet-accepted pcbs (a crash at address -8; epmd never answered because
  the ALIVE2_REQ arrived before accept and was dropped; now refused and
  redelivered by lwIP within 250 ms), sends larger than one MSS, a full send
  buffer reported as `closed`, and `OTP_SOCKET_LWIP_NODELAY` (erpc round
  trips went from 44 ms to 1.2 ms).
- `melange/atomvm-baremetal/0002`: the dist controller dropped the rest of a
  partial send; a 10 kB reply never arrived.
- QEMU option values need commas doubled (ExUnit's `tmp_dir` has them).

## Measured (QEMU 8.2 TCG on the build host, 2026-10-23)

- Boot to the runtime's `up` line: ≈ 1.5 s after the ring appears.
- ping 10.0.3.9: 50/50, rtt avg 1.27 ms (min 1.09).
- erpc round trip: median 1.24 ms.
- Distribution: 1 MiB to the coprocessor in 87–99 ms, from it in 97–113 ms
  (≈ 10 MiB/s each way). 4 MiB in one message exhausts the 10 MiB arena.
- Heap: 190 KiB after connecting and one driver call; 3.3 MiB after the
  1 MiB transfers. ≈ 2.5 KiB leaks per VM restart.

## Board drivers (M33)

The deck image runs the board backends of all five drivers
(`ELIXOS_COPROC_DRIVERS=k230`, `scripts/build-deck.sh`); QEMU and the host
tests run `sim`. Each backend (`os/src/coproc_<x>_k230.erl`) is a thin poll
loop over the firmware's NIFs (`coproc/src/platform_nifs.c`); the protocols
are C, so they can be checked on the build host. Written 2026-10-23 without a
board: **none of it has run on hardware.**

| Device | Backend, poll | C driver | What it does |
|---|---|---|---|
| GT9895 touch, I2C3 @ 0x5D | `coproc_touch_k230`, 20 ms | `touch_k230.c` over `k230_i2c.c` | once per boot: pads (IO23 INT, IO24 RST, IO35, IO36/37 I2C3), I2C3 at 400 kHz, RST low, IO35 (IOVDD) high, 3 + 15 ms, RST high, 4 ms, the 0xAA device check at 0x10000, 100 ms. Each poll reads 26 bytes at 0x10308 (header + 2 points + sum), more past 2 fingers, clears the status byte, and turns the first finger into `{down \| move \| up, X, Y}` (raw 1060 x 2400 scaled to 568 x 1232) |
| SX1262 LoRa, QSPI0 | `coproc_lora_k230`, 20 ms | `lora_k230.c` over `k230_spi.c` | IO44 (module LDO) high, IO14-17 as QSPI0 (function 3), 5 MHz mode 0; RadioLib's `begin` as LilyGO configures the SX1262 SKU (TCXO 3.3 V on DIO3, DC-DC, DIO2 RF switch, 140 mA, SF10/125 kHz/4-6, sync 0x12, preamble 16, 22 dBm, CRC off) on `ELIXOS_COPROC_LORA_FREQUENCY`; continuous receive; DIO1 (IO20) polled, then IRQ status, packet, `GetPacketStatus` (RSSI = -SignalRssiPkt/2 dBm, SNR = SnrPkt/4 dB); a send goes out from standby and the radio receives again after TX_DONE |
| PMU power key and OUT0 | `coproc_power_k230`, 10 ms | `power_k230.c` | LilyGO's Linux power-key driver's set-up: PMU isolation off, OUT0/OUT1 driven by the software register, 96000/256-tick long-press/debounce, the key's edge event detected rising then falling; the event register polled (the PLIC line is never enabled); power-off: only an INT0 long press may wake, `PMU_STATUS` = normal power-down, software register 3 then 0, 1 s |
| UART3 | `coproc_console_k230`, 20 ms | `uart_k230.c` (at boot, from `hw_console_init`), `hw.c` | pads IO50/IO51 (function 1), UART3's leaf divider 1/1, clock read back from PLL0 and the CMU (1.6 GHz / 16 = 100 MHz nominal), divisor and fraction by Canaan's formula (100 MHz: DLL 54, DLF 4), 8N1, FIFO; lines in on `\r` or `\n` |

The touch controller, the LoRa radio and the PMU are opened when their
backend starts; the C side keeps their state across VM restarts (the touch
controller is set up once per boot, the radio again only for another
frequency), so a deploy does not reset them.

### Sources (pinned)

Tags as in docs/notes/k230-panel.md: **LT-RT**
Xinyuan-LilyGO/T-Display-K230_canmv_rt @ abb07090ad8a666ed7a5e097b3c714b918731645
(BSP = `canmv_k230/src/rtsmart/rtsmart/kernel/bsp/maix3/`, LORA =
`canmv_k230/src/rtsmart/mpp/userapps/sample/sample_display/ui_brookesia/src/app_examples/phone/lora/`);
**LT-BSP** Xinyuan-LilyGO/T-Display-K230 @ 0ad78192bab04585ae51bb847695fdc74658f134
(L = `k230_bsp/overlay/buildroot-overlay/linux/`); **CAN-SDK**
kendryte/k230_sdk @ 7e302f733311d284be255f0d81d3463b6ae6ee6d. Every file was
fetched from raw.githubusercontent.com at that commit; the line numbers in
the drivers' header comments are those files'.

| What | File (sha256, first and last 8 hex digits) |
|---|---|
| GT9895 bus, address, report address 0x10308 | LT-RT BSP `drivers/extdrv/touch/gt9895.c` (`fdfa7945…d0538e92`), `configs/k230_canmv_v3p0_defconfig` 241-243 (`8ad58705…b1bb761a`) |
| GT9895 power-on, device check, report layout, clear | LT-BSP L`0034-gt9895-touch.patch` (`871ba3ad…1356850d`) 1490-1491, 1530-1560, 1661-1699, 2544-2790, 11011-11024 |
| GT9895 raw range 1060 x 2400 | LT-BSP L`0031-riscv-dts-canaan-add-rm69a10-display.patch` (`a01a6888…68a12b13`) 86-87 |
| DesignWare I2C master | LT-RT BSP `drivers/interdrv/i2c/drv_i2c.c` (`68dca5b3…c62a1f16`) 117-137, 413-429, 462-695, 870-946, 1070-1107, 1196-1224; `drv_i2c.h` (`e96d5801…a1dce195`) 139-265 |
| Pads | LT-RT `canmv_k230/src/uboot/uboot/arch/riscv/dts/k230_canmv_v3p0.dts` (`51d63d8f…fbe27029`) 86-168; `canmv_k230/src/rtsmart/mpp/userapps/sample/sample_display/fpioa/rt_fpioa.c` (`d7d23684…e5cd33ed`) 16, 106-113, 155-219, 228-245, 266, 410 |
| GPIO | LT-RT BSP `board/board.h` (`4ac8f651…98ec4eb2`) 230-234, `drivers/interdrv/gpio/drv_gpio.h` (`d679fcbb…5b42765c`) 32-48 |
| Clocks | LT-RT BSP `drivers/interdrv/sysctl/sysctl_clock/sysctl_clk.c` (`bd5ffe63…9d027550`) 265-273, 530-575, 1162-1166, 1193-1194, 1234-1254, 2712-2724, 3210-3211, 3237-3238, 3279-3299; `sysctl_clk.h` (`58c8d4de…d3fc4aad`) 36-50, 109-112; `sysctl_boot/sysctl_boot.h` (`a66f2067…bf5e84f6`) 33-41 |
| SX1262 pins, power, SPI, configuration | LT-RT LORA`Lora.cpp` (`c8a5c8cc…a0eca03c`) 23-43, 117-130, 286-317, 669-676, 788-805; `lora_lib/k230Hal.cpp` (`feef4af5…a2cafc4f`) 187-207, 253 |
| SX1262 command sequence | LT-RT LORA`lora_lib/` RadioLib (MIT): `modules/SX126x/SX126x.cpp`, `SX1262.cpp`, `Module.cpp` and the headers they need, every one in `coproc/test/board_trace/vendor.lock` with its full sha256 |
| Continuous-receive read offset | LT-BSP `k230_launcher/k230_phone_ui/src/third_party/RadioLib/src/modules/SX126x/SX126x.cpp` (`ce262173…5fc26f85`) 556-565; licence `…/RadioLib/license.txt` (`02537811…92b8a3e8`) |
| DesignWare SSI master | LT-RT BSP `drivers/interdrv/spi/drv_spi.c` (`9531db21…9b79a313`) 42-110, 140-180, 184-347, 394-398, 429-437; CAN-SDK `src/little/linux/drivers/spi/spi-dw-core-k230.c` (`dc3012f0…263bc80d`) 113-140, 1371-1382, `spi-dw-mmio-k230.c` (`c13d17a5…151f98ef`) 58-61 |
| PMU power key and power-off | LT-BSP L`0064-input-k230-pmu-pwrkey.patch` (`28396fef…7c824f42`) 90-583; LT-BSP `k230_launcher/k230_phone_ui/src/ui_hardware.c` (`afbcb6e3…8a9c7311`, the polled variant) 9195-9420 |
| UART3 | LT-RT BSP `drivers/interdrv/uart_canaan/drv_uart.c` (`da018846…23927a54`) 47-63, 263-314; `uart_canaan/drv_uart.h` (`9fc31bd4…ab287ff8`) 97-103; `uart/drv_uart.c` (`e363ba5e…0678f05c`) 136-166 |

The files the tests compile are in `coproc/test/board_trace/vendor.lock` with
their full hashes and URLs.

### The tests

`coproc/test/board_trace/run.sh` (run by `melange/coproc-firmware.yaml`
before the cross builds, like the panel's; by hand
`sh coproc/test/board_trace/run.sh coproc build/coproc-dl build/board-trace`):

1. Fetches `vendor.lock`'s files (LilyGO's RadioLib build, its RT-Smart
   GT9895 driver, its Linux power-key patch), each checked by sha256.
2. Builds the device models of `coproc/test/models/` on the register mock
   (`coproc/test/k230_mmio_mock.c`, which now lets models attach to address
   ranges and keeps a virtual clock): the GPIO blocks, a DesignWare I2C
   master with a GT9895 behind it, a DesignWare SSI master with an SX1262
   (the command subset both drivers use, BUSY after every command, DIO1 by
   the IRQ mask, FIFOs of a chosen depth that drain one byte per few register
   reads, chip select dropped when the TX FIFO runs dry, so a command a
   driver lets run dry arrives split), the PMU's key events and outputs.
3. Compiles LilyGO's code against the same models: RadioLib through a host
   `RadioLibHal`, called as LilyGO's phone app calls it for the SX1262
   (`golden_lora.cc`); `gt9895.c` with RT-Thread stand-ins
   (`golden_touch.c`); lines 90-583 of the power-key patch with Linux
   stand-ins (`golden_power.c`).
4. Runs one scenario on each pair and compares: the SX1262's command
   stream (ours = vendor's + `elixos-lora.patch`: continuous receive, DIO1,
   standby before a send, receive again after it), the GT9895's I2C
   transfers (ours = vendor's + `elixos-touch.patch`: device check, 26-byte
   reads, clearing), the PMU's register trace (identical). Result
   (2026-10-23, host gcc): `board trace (lora): ours = vendor's +
   elixos-lora.patch: 105 lines, vendor's 93`; `(touch): 4 lines, vendor's
   1`; `(power): ours = vendor's: 56 lines, vendor's 56`.
5. Runs `coproc/test/board_k230_test.c` (17 tests, and the no-devices
   build's one): pads, clocks and bus set-up values; frequencies 433/490/868/
   915/923 MHz and an out-of-table one (image calibration, frf); reopening;
   a 255-byte packet both ways through an 8-entry FIFO; DIO1 low means no
   SPI; CRC errors; a missing module (1 s, `busy_timeout`); touch power/reset
   order and waits, down/move/up, clamping, three fingers, a corrupt header,
   a stylus, a missing controller; the power key both ways and power-off;
   UART3's divisor from a programmed and a bypassed PLL.

On the BEAM side `os/test/elixos/coproc_board_k230_test.exs` runs the four
backends on AtomVM's Unix build with a `coproc_k230` module of the test's
own in the bundle, playing the NIFs.

What the tests do not show: that the vendor's sequences are right for this
board, and anything the hardware does with them.

### Licences

As for the panel (docs/notes/k230-panel.md, "Licences"): the drivers are our
own implementations of the register and command sequences; the firmware
contains no vendor code. LilyGO's RadioLib build (MIT, Jan Gromeš; LilyGO's
copy has no header, LT-BSP's vendored RadioLib carries the MIT text),
Canaan's `gt9895.c` (BSD-2-Clause-style), the GPL-2.0-only Linux power-key
patch and Goodix's GPL-2.0+ Linux driver are compiled only into the host
test binaries in `build/` (or read as specifications), so the firmware's
licence is unchanged.

### Only the board can tell

1. UART3: that `uart_k230_init` reads a sane PLL0 (expected 1.6 GHz) and the
   console prints at 115200 on the CH342K's second port; that the UART3 and
   I2C3/QSPI0 clock gates (`ls_clken_cfg0` bits 4/19, `hs_clken_cfg` bits
   7/25/29) are on at reset (no vendor driver turns them on).
2. Touch: whether IO35 high is needed and enough for TP_VDDIO (the
   schematic's IO35_DISEN) and whether pulsing IO24 also resets the LT9611
   (HDMI_RSTN is the same net); the report address 0x10308 (LilyGO's
   RT-Smart value; the Linux driver reads it from the IC info at 0x10070);
   the raw range (1060, LilyGO's Linux DT and launcher, or 1024, their
   RT-Smart driver: touch the right edge); that a 20 ms poll with clearing
   gives reports (the INT line is not used); orientation (no swap or
   inversion expected).
3. LoRa: which of QSPI0 (LilyGO's RT-Smart, function 3) or OSPI (their Linux
   DT, function 1) actually reaches the module on IO14-17; the QSPI0 FIFO
   depth the probe finds and that the chip select stays asserted through a
   255-byte `WriteBuffer`; BUSY/DIO1 levels; the TCXO voltage (3.3 V,
   LilyGO's value); interoperability with another LilyGO device (same
   frequency, SF10, 125 kHz, CR 4/6, sync 0x12, no CRC); the RSSI/SNR fields
   (RadioLib reads SignalRssiPkt); continuous receive keeping packets at the
   start pointer GetRxBufferStatus reports.
4. PMU: that the power key raises the edge event in `INT_STATE` with the
   CPU route set but no interrupt enabled; that `power_off` cuts the supply
   (LilyGO's driver header says it mirrors an RT-Thread driver that is not
   published, and it was written with an AI assistant); that an INT0 long
   press then powers the board on; that a quick tap between two polls
   (10 ms) is not lost (only edges are latched).
5. Shared GPIO banks: our read-modify-writes of the GPIO data/direction
   registers are not atomic against the big core's Linux, if it drives other
   pins of the same banks.

## Open on the board

1. UART3: see "Board drivers", only the board can tell, 1.
2. The little core's CLINT: `mtimecmp` at `0xf04004000` is the big core's
   layout; `rdtime` in M-mode on the C908 is assumed.
3. Caches: the ring header puts writer and reader fields in one 64-byte
   line, so with non-coherent L2s the ring must be uncached on both sides
   (C908 PMA/sysmap, not cache maintenance). The image itself should run
   cached; neither is set up yet.
4. Entropy: no hardware RNG is used; the pool is counter jitter plus the
   payload seed. Weak; the K230 TRNG is the fix.
5. U-Boot environment: load the payload at `0x7400000` (done by the deck
   image, M33: `boards/t-display-k230/uboot-env-deck.txt`).
6. The panel (`coproc/src/panel_k230.c`) is ported but has never run; its
   board checks are in docs/notes/k230-panel.md. The framebuffer region must
   be uncached on the little core (it only reads the header and writes
   `shown`), and when the image runs cached, the status band's buffer
   (`status_pixels`, which the VO reads) must be uncached or cleaned to DDR
   after each `panel_k230_status`.
