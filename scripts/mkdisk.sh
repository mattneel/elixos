#!/usr/bin/env bash
# Create an architecture's pristine persistent disk: ext4, label ELIXOS.
# QEMU tests never boot this file directly; each test boots a sparse copy
# (Elixos.Test.Disk.fresh!/1), so tests cannot leak state into each other.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
SIZE="${DISK_SIZE:-2G}"
ARCH="${1:-x86_64}"
case "$ARCH" in
  x86_64) DISK="$BUILD/disk.img" ;;
  aarch64) DISK="$BUILD/aarch64/disk.img" ;;
  *) echo "disk: unsupported architecture $ARCH" >&2; exit 1 ;;
esac

mkdir -p "$(dirname "$DISK")"

# The pristine disk carries the guest toolchain (M11, ADR-009): the disk is
# mounted at /priv, so this is what a box with no network builds NIFs with.
# The toolchain is a melange package (M16, ADR-041), signed with the dev key
# like every other in-house package, so the disk cannot drift from the image.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

shopt -s nullglob
packages=("$BUILD/apk/$ARCH/$ARCH"/elixos-toolchain-*.apk)
if [ "${#packages[@]}" -eq 0 ]; then
  echo "disk: no elixos-toolchain package under $BUILD/apk/$ARCH" >&2
  echo "  build it first: scripts/build-image.sh $ARCH" >&2
  exit 1
fi
TOOLCHAIN_APK="${packages[0]}"
# melange's APKs are tar streams a plain `tar` reads (the checksum xattr is
# just a warning); only toolchain/ is wanted, not the package metadata.
tar -xzf "$TOOLCHAIN_APK" -C "$STAGE" --warning=no-unknown-keyword toolchain
[ -x "$STAGE/toolchain/zig" ] || { echo "disk: $TOOLCHAIN_APK carried no toolchain/zig" >&2; exit 1; }

# The system service tree is a separate immutable filesystem, never a factory
# overlay. PID 1 loop-mounts this image read-only at /system in normal mode.
SYSTEM="$BUILD/$ARCH/system.squashfs"
[ -f "$SYSTEM" ] || {
  echo "disk: no system image at $SYSTEM; run scripts/build-image.sh $ARCH" >&2
  exit 1
}
install -d -m0755 "$STAGE/system"
install -m0444 "$SYSTEM" "$STAGE/system/system.squashfs"

rm -f "$DISK"
truncate -s "$SIZE" "$DISK"
mkfs.ext4 -q -F -L ELIXOS -E root_owner=0:0 -d "$STAGE" "$DISK"
# mkfs -d copies host uid/gid values. Builds need not run as root, so explicitly
# set the protected service image's ownership and modes inside ext4 itself.
debugfs -w -R 'set_inode_field /system uid 0' "$DISK" >/dev/null 2>&1
debugfs -w -R 'set_inode_field /system gid 0' "$DISK" >/dev/null 2>&1
debugfs -w -R 'set_inode_field /system mode 040755' "$DISK" >/dev/null 2>&1
debugfs -w -R 'set_inode_field /system/system.squashfs uid 0' "$DISK" >/dev/null 2>&1
debugfs -w -R 'set_inode_field /system/system.squashfs gid 0' "$DISK" >/dev/null 2>&1
debugfs -w -R 'set_inode_field /system/system.squashfs mode 0100444' "$DISK" >/dev/null 2>&1
echo "disk: $DISK ($SIZE, ext4, label ELIXOS, toolchain $(du -sh "$STAGE/toolchain" | cut -f1), $(basename "$TOOLCHAIN_APK"))"
