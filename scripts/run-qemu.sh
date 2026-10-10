#!/usr/bin/env bash
# Boot Elixos interactively on this terminal: the serial console is your tty.
# Quit QEMU with Ctrl-A X. Extra arguments are appended to the kernel command
# line, e.g.:  scripts/run-qemu.sh elixos.safe
#
# This boots build/disk.img itself, so state persists between your sessions.
# (Tests never touch it; they boot copies.)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"

for f in bzImage initramfs.cpio.gz disk.img; do
  [ -f "$BUILD/$f" ] || { echo "missing $BUILD/$f; run: make image" >&2; exit 1; }
done

exec qemu-system-x86_64 \
  -machine q35 -accel kvm -accel tcg -cpu max -m "${QEMU_MEMORY:-1024}" -smp 2 \
  -nographic -no-reboot \
  -kernel "$BUILD/bzImage" \
  -initrd "$BUILD/initramfs.cpio.gz" \
  -append "console=ttyS0 panic=-1 $*" \
  -drive "file=$BUILD/disk.img,if=virtio,format=raw" \
  -device virtio-rng-pci \
  -nic none
