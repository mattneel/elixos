#!/usr/bin/env bash
# The LilyGO T-Display K230 bring-up SD card (M30): build/k230/elixos-k230-bringup.img.
#
#   raw, before the partitions   Canaan's SPL (twice), U-Boot environment and
#                                U-Boot (ADR-102), at the BootROM's offsets
#   p1  ext4 "boot" at 30 MiB    OpenSBI fw_jump, the riscv64 Image, our DTB
#                                (ADR-101), the initramfs, coproc.bin
#   p2  ext4 "ELIXOS"            the data disk for /priv, without the guest
#                                toolchain (ADR-111)
#
# coproc.bin is the little core's trivial image (boards/t-display-k230/
# coproc-hello); U-Boot loads it and releases the little core into it before
# booting Linux (boards/t-display-k230/uboot-env.txt). The card layout is
# shared with the deck card (scripts/k230-sd.sh, scripts/build-deck.sh).
#
# Inputs: scripts/build-image.sh riscv64 (Image, initramfs, DTBs, system image)
# and scripts/build-k230-firmware.sh (run from here). Writes nothing outside
# build/k230/.
set -euo pipefail

K230_NAME=k230
# shellcheck source=scripts/k230-sd.sh
. "$(dirname "$0")/k230-sd.sh"
IMG="$OUT/elixos-k230-bringup.img"

k230_require_image
k230_firmware

mkdir -p "$OUT"
WORK="$(mktemp -d "$OUT/.work.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# The little core's image: the hello image built for the K230's UART0
# (DesignWare, 32-bit registers, stride 4), linked where U-Boot loads it.
hello="$BOARD/coproc-hello"
zig cc -E -P -x c -DLOAD_ADDR="$COPROC_ADDR" -o "$WORK/hello.ld" "$hello/hello.ld"
zig cc -target riscv64-freestanding-none -mcpu=generic_rv64 -nostdlib -static \
  -DUART_BASE=0x91400000 -DUART_SHIFT=2 -DUART_WORD=1 \
  -Wl,-T,"$WORK/hello.ld" -o "$WORK/coproc.elf" "$hello/hello.S"
zig objcopy -O binary "$WORK/coproc.elf" "$OUT/coproc.bin"
[ "$(size "$OUT/coproc.bin")" -le "$COPROC_MAX" ] || die "coproc.bin does not fit the reserved region"

# p1: what U-Boot's environment loads, by the names it uses.
mkdir -p "$WORK/boot"
cp "$OUT/coproc.bin" "$WORK/boot/"
k230_boot_partition "$WORK/boot" "$WORK/boot.img"

# p2: the data disk.
k230_data_partition "$WORK/data.img"

k230_assemble "$IMG" "$WORK/boot.img" "$WORK/data.img" "$FIRMWARE/env.bin"
k230_report "$IMG" "$WORK/boot"
