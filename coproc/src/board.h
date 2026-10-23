/*
 * Elixos coprocessor firmware: build-time board parameters (docs/notes/coproc-firmware.md).
 *
 * Every hardware address is a compile definition set by coproc/CMakeLists.txt
 * from the COPROC_* cache variables, so the same sources build for the K230's
 * little core and for QEMU's virt machine (the test stand-in). Nothing here
 * has a default: a build that forgets one does not compile.
 *
 *   COPROC_LOAD_ADDR       the image's first byte, the entry point
 *   COPROC_PAYLOAD_OFFSET  the payload (docs/notes/coproc-firmware.md) from LOAD_ADDR
 *   COPROC_HEAP_OFFSET     the malloc arena, up to COPROC_REGION_SIZE
 *   COPROC_REGION_SIZE     the little core's region (K230: 16 MiB)
 *   COPROC_RING_ADDR       the §11 ring region, shared with the big core
 *                          (K230: 0x08000000, the board DT's no-map region)
 *   COPROC_RING_SIZE       its size S (K230: 0x21000, 2 x 64 KiB + 4096)
 *   COPROC_FB_ADDR         the §12 deck framebuffer region (K230: 0x08100000,
 *                          the board DT's `deck-fb`)
 *   COPROC_FB_SIZE         its size (K230: 0x180000, 1.5 MiB)
 *   COPROC_UART_BASE       16550-compatible UART register base
 *   COPROC_UART_SHIFT      register stride shift (DesignWare: 2, virt: 0)
 *   COPROC_UART_WORD       1: 32-bit register accesses, 0: byte accesses
 *   COPROC_UART_DIVISOR    baud divisor to program, 0: keep the loader's setup
 *   COPROC_MTIME_ADDR      CLINT mtime register, 0: read the time CSR
 *   COPROC_MTIMECMP_ADDR   this hart's CLINT mtimecmp, 0: poll without wfi
 *   COPROC_TIMEBASE_HZ     mtime frequency
 *   COPROC_BOARD           a name for the banner
 */
#ifndef COPROC_BOARD_H
#define COPROC_BOARD_H

#include <stdint.h>

#define COPROC_ADDR(offset) ((uintptr_t) COPROC_LOAD_ADDR + (uintptr_t) (offset))

#endif
