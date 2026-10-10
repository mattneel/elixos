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
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
"$ROOT/scripts/fetch-toolchain.sh" "$STAGE"

rm -f "$DISK"
truncate -s "$SIZE" "$DISK"
mkfs.ext4 -q -F -L ELIXOS -E root_owner=0:0 -d "$STAGE" "$DISK"
echo "disk: $DISK ($SIZE, ext4, label ELIXOS, toolchain $(du -sh "$STAGE/toolchain" | cut -f1))"
