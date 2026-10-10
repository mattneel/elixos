#!/usr/bin/env bash
# Build build/initramfs.cpio.gz with the kernel's own usr/gen_init_cpio.
# No root needed: device nodes and ownership come from the list file.
#
# Layout (docs/ARCHITECTURE.md §2):
#   /init                          the Zig shim (zig-out/bin/init)
#   /dev/console, /dev/null        so PID 1 has stdio before it mounts devtmpfs
#   /proc /sys /dev /run /tmp      mount points
#   /priv                          mount point for the persistent disk
#   everything under build/rootfs  overlaid at /  (M4+: /factory, /lib/ld-musl-*)
#
# Env: INIT=<path to shim>  ROOTFS=<overlay dir>  ELIXOS_BUILD=<build dir>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../kernel/VERSION
. "$ROOT/kernel/VERSION"

BUILD="${ELIXOS_BUILD:-$ROOT/build}"
GEN="$BUILD/linux-$KERNEL_VERSION/usr/gen_init_cpio"
INIT="${INIT:-$ROOT/zig-out/bin/init}"
ROOTFS="${ROOTFS:-$BUILD/rootfs}"
LIST="$BUILD/initramfs.list"
OUT="$BUILD/initramfs.cpio.gz"

[ -x "$GEN" ] || { echo "initramfs: $GEN missing; run scripts/build-kernel.sh" >&2; exit 1; }
[ -x "$INIT" ] || { echo "initramfs: $INIT missing; run: zig build -Drelease" >&2; exit 1; }

{
  echo "dir /dev 0755 0 0"
  echo "nod /dev/console 0600 0 0 c 5 1"
  echo "nod /dev/null 0666 0 0 c 1 3"
  for dir in /proc /sys /run /tmp /priv; do
    echo "dir $dir 0755 0 0"
  done
  echo "file /init $INIT 0755 0 0"

  if [ -d "$ROOTFS" ]; then
    (cd "$ROOTFS" && find . -mindepth 1 | LC_ALL=C sort) | while IFS= read -r entry; do
      rel="${entry#./}"
      src="$ROOTFS/$rel"
      dst="/$rel"
      if [ -L "$src" ]; then
        echo "slink $dst $(readlink "$src") 0777 0 0"
      elif [ -d "$src" ]; then
        echo "dir $dst $(stat -c %a "$src") 0 0"
      else
        echo "file $dst $src $(stat -c %a "$src") 0 0"
      fi
    done
  fi
} > "$LIST"

"$GEN" -t 0 "$LIST" | gzip -9n > "$OUT"
echo "initramfs: $OUT ($(du -h "$OUT" | cut -f1), $(grep -c '' "$LIST") entries)"
