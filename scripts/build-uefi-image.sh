#!/usr/bin/env bash
# Build the ESP for the real-hardware path (M13, ADR-014): a FAT EFI System
# Partition whose EFI/BOOT/BOOTX64.EFI is the mainline kernel itself, booted
# by the firmware through its EFI stub. No bootloader, no patched source: the
# initramfs and the command line are built into the kernel by configuration
# (CONFIG_INITRAMFS_SOURCE, CONFIG_CMDLINE - ADR-001).
#
#   scripts/build-uefi-image.sh             serial console -> build/esp.img
#                                           (what the M13 test boots under OVMF)
#   scripts/build-uefi-image.sh --hardware   the panel -> build/esp-hardware.img
#                                           (console=tty0 fbcon=font:TER16x32)
#
# The kernel is built out-of-tree (O=), so the QEMU kernel in build/ is left
# alone; both share the same pinned source and the same fragment.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../kernel/VERSION
. "$ROOT/kernel/VERSION"

BUILD="${ELIXOS_BUILD:-$ROOT/build}"
JOBS="${JOBS:-$(nproc)}"

case "${1:-}" in
  --hardware)
    ESP="$BUILD/esp-hardware.img"
    CMDLINE="console=tty0 fbcon=font:TER16x32 panic=-1 quiet"
    ;;
  "")
    ESP="$BUILD/esp.img"
    CMDLINE="console=ttyS0 panic=-1 quiet"
    ;;
  *)
    echo "usage: build-uefi-image.sh [--hardware]" >&2
    exit 1
    ;;
esac

INITRAMFS="$BUILD/initramfs.cpio.gz"
TARBALL="$BUILD/dl/linux-$KERNEL_VERSION.tar.xz"
# kbuild refuses O= builds from a tree that already has in-tree artifacts, and
# the QEMU kernel's tree does: the UEFI kernels get their own extraction. The
# two variants share it (switching reconfigures and rebuilds, which is fine
# for something built once per machine).
SRC="$BUILD/linux-uefi-$KERNEL_VERSION"

[ -f "$TARBALL" ] || { echo "uefi: $TARBALL missing; run scripts/build-kernel.sh" >&2; exit 1; }
[ -f "$INITRAMFS" ] || { echo "uefi: $INITRAMFS missing; run make initramfs" >&2; exit 1; }

if [ ! -d "$SRC" ]; then
  echo "uefi: extracting $(basename "$TARBALL") into $SRC"
  mkdir -p "$SRC"
  tar -C "$SRC" --strip-components=1 -xJf "$TARBALL"
fi

echo "uefi: configuring (built-in initramfs and cmdline)"
unset LLVM

make -C "$SRC" -s x86_64_defconfig
make -C "$SRC" -s kvm_guest.config
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$SRC" "$SRC/.config" "$ROOT/kernel/elixos.config" >/dev/null

"$SRC/scripts/config" --file "$SRC/.config" \
  --set-str INITRAMFS_SOURCE "$INITRAMFS" \
  --enable CMDLINE_BOOL \
  --set-str CMDLINE "$CMDLINE" \
  --enable CMDLINE_OVERRIDE
make -C "$SRC" -s olddefconfig
"$ROOT/scripts/check-kernel-config.sh" "$SRC/.config" "$ROOT/kernel/elixos.config"

echo "uefi: building bzImage with $JOBS jobs"
make -C "$SRC" -s -j"$JOBS" bzImage

KERNEL="$SRC/arch/x86/boot/bzImage"
[ -s "$KERNEL" ] || { echo "uefi: $KERNEL was not built" >&2; exit 1; }

# A FAT32 filesystem on the whole image (no partition table): firmware takes
# \EFI\BOOT\BOOTX64.EFI as the default application.
kernel_mb=$(( ($(stat -c%s "$KERNEL") + (1 << 20) - 1) / (1 << 20) ))
size_mb=$(( kernel_mb + 16 ))
rm -f "$ESP"
truncate -s "${size_mb}M" "$ESP"
mformat -i "$ESP" -F ::
mmd -i "$ESP" ::/EFI ::/EFI/BOOT
mcopy -i "$ESP" "$KERNEL" ::/EFI/BOOT/BOOTX64.EFI

echo "uefi: $ESP (${size_mb}M FAT32, kernel $(du -h "$KERNEL" | cut -f1) with initramfs, cmdline: $CMDLINE)"
