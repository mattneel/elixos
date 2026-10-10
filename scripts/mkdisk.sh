#!/usr/bin/env bash
# Create the pristine persistent disk, build/disk.img: ext4, label ELIXOS.
# QEMU tests never boot this file directly; each test boots a sparse copy
# (Elixos.Test.Disk.fresh!/1), so tests cannot leak state into each other.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
SIZE="${DISK_SIZE:-1G}"
DISK="$BUILD/disk.img"

mkdir -p "$BUILD"

# The pristine disk carries the guest toolchain (M11, ADR-009): the disk is
# mounted at /priv, so this is what a box with no network builds NIFs with.
# The toolchain is a melange package (M16, ADR-041), signed with the dev key
# like every other in-house package, so the disk cannot drift from the image.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

TOOLCHAIN_APK="$(ls "$BUILD"/apk/x86_64/x86_64/elixos-toolchain-*.apk 2>/dev/null | head -n1)"
if [ -z "$TOOLCHAIN_APK" ]; then
  echo "disk: no elixos-toolchain package under $BUILD/apk/x86_64" >&2
  echo "  build it first: scripts/build-image.sh x86_64" >&2
  exit 1
fi
# melange's APKs are tar streams a plain `tar` reads (the checksum xattr is
# just a warning); only toolchain/ is wanted, not the package metadata.
tar -xzf "$TOOLCHAIN_APK" -C "$STAGE" --warning=no-unknown-keyword toolchain
[ -x "$STAGE/toolchain/zig" ] || { echo "disk: $TOOLCHAIN_APK carried no toolchain/zig" >&2; exit 1; }

rm -f "$DISK"
truncate -s "$SIZE" "$DISK"
mkfs.ext4 -q -F -L ELIXOS -E root_owner=0:0 -d "$STAGE" "$DISK"
echo "disk: $DISK ($SIZE, ext4, label ELIXOS, toolchain $(du -sh "$STAGE/toolchain" | cut -f1), $(basename "$TOOLCHAIN_APK"))"
