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
| `coproc/src/hw.c` | UART console (16550, polled), clock (`rdtime` or CLINT mtime), idle (`wfi` on a one-shot mtimecmp), `sbrk`, picolibc stdio, traps |
| `coproc/src/ramfs.c` | RAM file system behind `open/read/write/close/unlink/rename/fsync`, so `atomvm:posix_*` and the runtime work unchanged |
| `coproc/src/payload.c`, `coproc/tools/mkpayload.py` | the payload: environment block, AVM packs, files |
| `coproc/src/ring.c` | §11 ring, little side; `coproc/test/ring_vectors_test.c` runs `spec/ring.vectors` on the host |
| `coproc/src/net.c` | lwIP 2.2.1 (raw API, NO_SYS) netif over the ring: reads A, writes B, bare IPv4, no link layer |
| `coproc/src/sys.c`, `otp_socket_platform.c`, `otp_net_lwip_raw.c`, `platform_nifs.c` | AtomVM's `sys_*` contract; the lwIP event queue; `net:getaddrinfo`; `atomvm:platform/0` = `elixos_coproc`; Mbed TLS entropy |
| `coproc/src/platform_nifs.c` (M33) | `coproc_k230:fb_read/2`, `fb_write32/2` on the §12 region at `COPROC_FB_ADDR`; `panel_open/0`, `panel_status/1` |
| `coproc/src/panel_k230.c`, `k230_mmio.c` (M33) | the RM69A10 bring-up (LilyGO's U-Boot register sequence) and the VO scan-out of the §12 region; the status band as a second VO layer. Register access goes through `k230_mmio.h`, so `coproc/test/panel_trace/run.sh` checks the port's register trace against the vendor code's on the build host (docs/notes/k230-panel.md). `COPROC_PANEL_K230=0` (QEMU virt): `{error, no_panel}` |
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
| `ELIXOS_COPROC_DRIVERS` | `sim`, or per subsystem `sim,display=k230` (the deck image) |
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

## Open on the board

1. UART3 clock and divisor (27 assumes 50 MHz), pinmux of IO50/IO51.
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
