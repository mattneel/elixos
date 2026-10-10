#!/usr/bin/env bash
# Build build/esp.img: a FAT EFI System Partition whose EFI/BOOT/BOOTX64.EFI is
# the mainline kernel itself (EFI stub, ADR-014) with the initramfs and a
# command line built in. No bootloader. This is milestone M13's job.
#
# Expected approach (docs/ROADMAP.md M13):
#   1. Rebuild the kernel with CONFIG_INITRAMFS_SOURCE=build/initramfs.list and
#      CONFIG_CMDLINE="console=ttyS0 ..." (a second config, never a source patch).
#   2. mformat/mcopy (mtools) the result into a FAT image as EFI/BOOT/BOOTX64.EFI.
#   3. For real hardware, a variant with console=tty0 fbcon=font:TER16x32.
set -euo pipefail

echo "TODO(M13): scripts/build-uefi-image.sh is not written yet (docs/ROADMAP.md M13)" >&2
exit 1
