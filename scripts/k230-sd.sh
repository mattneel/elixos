# shellcheck shell=bash disable=SC2034
# The LilyGO T-Display K230 SD card, shared by scripts/build-k230.sh (the M30
# bring-up card) and scripts/build-deck.sh (the M33 deck card). Sourced, not
# run. Layout (docs/notes/k230.md, "SD layout"):
#
#   raw, before the partitions   Canaan's SPL (twice), U-Boot environment and
#                                U-Boot (ADR-102), at the BootROM's offsets
#   p1  ext4 "boot" at 30 MiB    what U-Boot's environment loads
#   p2  ext4 "ELIXOS"            the data disk for /priv, without the guest
#                                toolchain (ADR-111)
#
# The caller sets K230_NAME (its log prefix) and calls, in order:
# k230_require_image, k230_firmware, k230_boot_partition, k230_data_partition,
# k230_assemble. Everything is written under $OUT (build/k230/).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
BOARD="$ROOT/boards/t-display-k230"
RISCV="$BUILD/riscv64"
OUT="$BUILD/k230"
FIRMWARE="$OUT/firmware"

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

die() { echo "${K230_NAME:-k230}: $*" >&2; exit 1; }
size() { stat -c %s "$1"; }
fits() { # fits <what> <offset> <size> <limit>
  [ $(($2 + $3)) -le "$4" ] || die "$1 ($3 bytes at $2) runs past $4"
}

# The riscv64 image's outputs (scripts/build-image.sh riscv64).
k230_require_image() {
  local file
  for file in Image initramfs.cpio.gz system.squashfs dtbs/t-display-k230.dtb; do
    [ -f "$RISCV/$file" ] || die "no $RISCV/$file; build it first: scripts/build-image.sh riscv64"
  done
}

# Canaan's firmware (ADR-102), built or cached, and its layout checked;
# leaves ENV_OFFSET, ENV_SIZE and ENV_REDUNDANT set.
k230_firmware() {
  "$ROOT/scripts/build-k230-firmware.sh"
  local file
  for file in spl.bin uboot.bin env.bin fw_jump.uImage layout.env; do
    [ -f "$FIRMWARE/$file" ] || die "the firmware build left no $FIRMWARE/$file"
  done
  # ENV_OFFSET and ENV_SIZE, from the U-Boot configuration that was built.
  # shellcheck source=/dev/null
  . "$FIRMWARE/layout.env"
  : "${ENV_OFFSET:?layout.env names no ENV_OFFSET}" "${ENV_SIZE:?layout.env names no ENV_SIZE}"
  fits "the SPL" "$SPL_OFFSET" "$(size "$FIRMWARE/spl.bin")" "$((SPL_OFFSET + SPL_MAX))"
  fits "the SPL copy" "$SPL_COPY_OFFSET" "$(size "$FIRMWARE/spl.bin")" "$((ENV_OFFSET))"
  [ "$(size "$FIRMWARE/env.bin")" -eq $((ENV_SIZE)) ] || die "env.bin is not ENV_SIZE ($ENV_SIZE) bytes"
  fits "the environment" "$((ENV_OFFSET))" "$((ENV_SIZE))" "$UBOOT_OFFSET"
  fits "U-Boot" "$UBOOT_OFFSET" "$(size "$FIRMWARE/uboot.bin")" "$BOOT_OFFSET"
}

# k230_boot_partition <dir> <out.img>: p1 from the files in <dir> plus the
# firmware's OpenSBI and the riscv64 kernel, initramfs and DTB.
k230_boot_partition() {
  cp "$FIRMWARE/fw_jump.uImage" "$RISCV/Image" "$RISCV/initramfs.cpio.gz" \
     "$RISCV/dtbs/t-display-k230.dtb" "$1/"
  rm -f "$2"
  truncate -s "$BOOT_SIZE" "$2"
  mkfs.ext4 -q -F -L boot -E root_owner=0:0 -d "$1" "$2"
}

# k230_data_partition <out.img>: p2, as mkdisk.sh makes it for QEMU, minus
# the toolchain.
k230_data_partition() {
  DISK_OUT="$1" DISK_SIZE="$DATA_SIZE" DISK_TOOLCHAIN=0 "$ROOT/scripts/mkdisk.sh" riscv64
}

# k230_assemble <img> <boot.img> <data.img> <env.bin>: the card.
k230_assemble() {
  local img="$1" boot="$2" data="$3" env="$4"
  [ "$(size "$env")" -eq $((ENV_SIZE)) ] || die "$env is not ENV_SIZE ($ENV_SIZE) bytes"
  rm -f "$img"
  truncate -s $((BOOT_OFFSET + BOOT_SIZE + DATA_SIZE)) "$img"
  sfdisk --quiet "$img" <<EOF
label: dos
unit: sectors

start=$((BOOT_OFFSET / 512)), size=$((BOOT_SIZE / 512)), type=83
start=$(((BOOT_OFFSET + BOOT_SIZE) / 512)), size=$((DATA_SIZE / 512)), type=83
EOF
  put() { dd if="$1" of="$img" bs=512 seek=$(($2 / 512)) conv=notrunc status=none; }
  put "$FIRMWARE/spl.bin" "$SPL_OFFSET"
  put "$FIRMWARE/spl.bin" "$SPL_COPY_OFFSET"
  put "$env" "$((ENV_OFFSET))"
  put "$FIRMWARE/uboot.bin" "$UBOOT_OFFSET"
  put "$boot" "$BOOT_OFFSET"
  put "$data" $((BOOT_OFFSET + BOOT_SIZE))
}

# k230_report <img> <boot dir>
k230_report() {
  local name="${K230_NAME:-k230}"
  echo "$name: $1 ($(du -h --apparent-size "$1" | cut -f1))"
  echo "$name:   SPL @ $SPL_OFFSET and $SPL_COPY_OFFSET, env @ $((ENV_OFFSET)), U-Boot @ $UBOOT_OFFSET"
  echo "$name:   p1 boot @ $BOOT_OFFSET: $(ls "$2" | tr '\n' ' ')"
  echo "$name:   p2 ELIXOS @ $((BOOT_OFFSET + BOOT_SIZE)) ($((DATA_SIZE / MIB)) MiB)"
  echo "$name: sha256 $(sha256sum "$1" | cut -d' ' -f1)"
}
