#!/usr/bin/env bash
# Record one demo: demos/mNN-<slug>.exp driving QEMU under asciinema.
#
#   demos/record.sh 3 m03-first-boot
#
# The recording is demos/mNN-<slug>.cast, made as demos/README.md says:
# 120x36, headless (the caller has no TTY), and -i 2 so long waits and compiles
# do not eat playback time.
# Each demo gets its own sparse copy of its architecture's pristine disk.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
M="${1:?usage: record.sh <milestone> <name>}"
NAME="${2:?usage: record.sh <milestone> <name>}"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
DEMO="$ROOT/demos/$NAME"

[ -f "$DEMO.exp" ] || { echo "record: no $DEMO.exp" >&2; exit 1; }

# asciinema 3.x: apt ships 2.x, whose flags differ.
ASCII=""
for candidate in "${ELIXOS_ASCIINEMA:-}" "$BUILD/tools/asciinema" "$(command -v asciinema || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] || continue
  if "$candidate" --version 2>/dev/null | grep -q '^asciinema 3'; then ASCII="$candidate"; break; fi
done
[ -n "$ASCII" ] || {
  cat >&2 <<'MSG'
record: asciinema 3.x is required (apt ships 2.x, whose flags differ).

  curl -sfL -o build/tools/asciinema \
    https://github.com/asciinema/asciinema/releases/download/v3.2.1/asciinema-x86_64-unknown-linux-gnu
  chmod +x build/tools/asciinema

MSG
  exit 1
}


# Two demos boot another architecture (m16-aarch64, m28-riscv64); everything else is the
# host's.
case "$NAME" in
  *-aarch64|*-riscv64)
    arch="${NAME##*-}"
    pristine="$BUILD/$arch/disk.img"
    export ELIXOS_DEMO_KERNEL="$BUILD/$arch/Image"
    export ELIXOS_DEMO_INITRAMFS="$BUILD/$arch/initramfs.cpio.gz"
    ;;
  *)
    export ELIXOS_DEMO_KERNEL="$BUILD/bzImage"
    arch=x86_64
    pristine="$BUILD/disk.img"
    export ELIXOS_DEMO_INITRAMFS="$BUILD/initramfs.cpio.gz"
    ;;
esac
for f in "$ELIXOS_DEMO_KERNEL" "$ELIXOS_DEMO_INITRAMFS"; do
  [ -f "$f" ] || { echo "record: $f missing; run: make image" >&2; exit 1; }
done

# Recreate the pristine disk: interactive QEMU may have changed the x86 one.
"$ROOT/scripts/mkdisk.sh" "$arch" >/dev/null
cp --sparse=always "$pristine" "$DEMO.disk"
export ELIXOS_DEMO_DISK="$DEMO.disk"

# M27 keeps actual QEMU graphics frames, separate from the serial cast.
if [ "$NAME" = m27-gui ]; then
  export ELIXOS_DEMO_FRAMES="$BUILD/$NAME.frames"
  rm -rf "$ELIXOS_DEMO_FRAMES"
  mkdir -p "$ELIXOS_DEMO_FRAMES"
fi
trap 'rm -f "$DEMO.disk"' EXIT

echo "record: $NAME -> $NAME.cast"
"$ASCII" rec --headless --window-size 120x36 -i 2 --overwrite \
  -c "expect $DEMO.exp" "$DEMO.cast"

rm -f "$DEMO.disk"

# The video is what people actually watch; the cast is its source.
demos/render.sh "$NAME"
