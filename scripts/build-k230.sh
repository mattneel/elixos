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
# booting Linux (boards/t-display-k230/uboot-env.txt).
#
# Inputs: scripts/build-image.sh riscv64 (Image, initramfs, DTBs, system image)
# and scripts/build-k230-firmware.sh (run from here). Writes nothing outside
# build/k230/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
BOARD="$ROOT/boards/t-display-k230"
RISCV="$BUILD/riscv64"
OUT="$BUILD/k230"
FIRMWARE="$OUT/firmware"
IMG="$OUT/elixos-k230-bringup.img"

MIB=$((1024 * 1024))
SPL_OFFSET=$((1 * MIB))
SPL_COPY_OFFSET=$((MIB + MIB / 2))
SPL_MAX=$((512 * 1024)) # the BootROM's SRAM window (SPL_MAX_SIZE)
UBOOT_OFFSET=$((2 * MIB))
BOOT_OFFSET=$((30 * MIB))
BOOT_SIZE=$((192 * MIB))
DATA_SIZE=$((1024 * MIB))
COPROC_ADDR=0x07000000
COPROC_MAX=$((16 * MIB))

die() { echo "k230: $*" >&2; exit 1; }

for file in Image initramfs.cpio.gz system.squashfs dtbs/t-display-k230.dtb; do
  [ -f "$RISCV/$file" ] || die "no $RISCV/$file; build it first: scripts/build-image.sh riscv64"
done

"$ROOT/scripts/build-k230-firmware.sh"
for file in spl.bin uboot.bin env.bin fw_jump.uImage layout.env; do
  [ -f "$FIRMWARE/$file" ] || die "the firmware build left no $FIRMWARE/$file"
done
# ENV_OFFSET and ENV_SIZE, from the U-Boot configuration that was built.
# shellcheck source=/dev/null
. "$FIRMWARE/layout.env"
: "${ENV_OFFSET:?layout.env names no ENV_OFFSET}" "${ENV_SIZE:?layout.env names no ENV_SIZE}"

size() { stat -c %s "$1"; }
fits() { # fits <what> <offset> <size> <limit>
  [ $(($2 + $3)) -le "$4" ] || die "$1 ($3 bytes at $2) runs past $4"
}
fits "the SPL" "$SPL_OFFSET" "$(size "$FIRMWARE/spl.bin")" "$((SPL_OFFSET + SPL_MAX))"
fits "the SPL copy" "$SPL_COPY_OFFSET" "$(size "$FIRMWARE/spl.bin")" "$((ENV_OFFSET))"
[ "$(size "$FIRMWARE/env.bin")" -eq $((ENV_SIZE)) ] || die "env.bin is not ENV_SIZE ($ENV_SIZE) bytes"
fits "the environment" "$((ENV_OFFSET))" "$((ENV_SIZE))" "$UBOOT_OFFSET"
fits "U-Boot" "$UBOOT_OFFSET" "$(size "$FIRMWARE/uboot.bin")" "$BOOT_OFFSET"

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
cp "$FIRMWARE/fw_jump.uImage" "$RISCV/Image" "$RISCV/initramfs.cpio.gz" \
   "$RISCV/dtbs/t-display-k230.dtb" "$OUT/coproc.bin" "$WORK/boot/"
truncate -s "$BOOT_SIZE" "$WORK/boot.img"
mkfs.ext4 -q -F -L boot -E root_owner=0:0 -d "$WORK/boot" "$WORK/boot.img"

# p2: the data disk, as mkdisk.sh makes it for QEMU, minus the toolchain.
DISK_OUT="$WORK/data.img" DISK_SIZE="$DATA_SIZE" DISK_TOOLCHAIN=0 "$ROOT/scripts/mkdisk.sh" riscv64

rm -f "$IMG"
truncate -s $((BOOT_OFFSET + BOOT_SIZE + DATA_SIZE)) "$IMG"
sfdisk --quiet "$IMG" <<EOF
label: dos
unit: sectors

start=$((BOOT_OFFSET / 512)), size=$((BOOT_SIZE / 512)), type=83
start=$(((BOOT_OFFSET + BOOT_SIZE) / 512)), size=$((DATA_SIZE / 512)), type=83
EOF

put() { dd if="$1" of="$IMG" bs=512 seek=$(($2 / 512)) conv=notrunc status=none; }
put "$FIRMWARE/spl.bin" "$SPL_OFFSET"
put "$FIRMWARE/spl.bin" "$SPL_COPY_OFFSET"
put "$FIRMWARE/env.bin" "$((ENV_OFFSET))"
put "$FIRMWARE/uboot.bin" "$UBOOT_OFFSET"
put "$WORK/boot.img" "$BOOT_OFFSET"
put "$WORK/data.img" $((BOOT_OFFSET + BOOT_SIZE))

echo "k230: $IMG ($(du -h --apparent-size "$IMG" | cut -f1))"
echo "k230:   SPL @ $SPL_OFFSET and $SPL_COPY_OFFSET, env @ $((ENV_OFFSET)), U-Boot @ $UBOOT_OFFSET"
echo "k230:   p1 boot @ $BOOT_OFFSET: $(ls "$WORK/boot" | tr '\n' ' ')"
echo "k230:   p2 ELIXOS @ $((BOOT_OFFSET + BOOT_SIZE)) ($((DATA_SIZE / MIB)) MiB)"
echo "k230: sha256 $(sha256sum "$IMG" | cut -d' ' -f1)"
