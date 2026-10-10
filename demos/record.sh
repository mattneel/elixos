#!/usr/bin/env bash
# Record one demo: demos/mNN-<slug>.exp driving QEMU under asciinema.
#
#   demos/record.sh 3 m03-first-boot
#
# The recording is demos/mNN-<slug>.cast, made exactly as docs/DEMOS.md says:
# 80x30 (the guest's serial console assumes 80 columns), headless (the caller
# has no TTY), and -i 2 so long waits and compiles do not eat playback time.
# Each demo gets its own sparse copy of build/disk.img.
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

# Demos that count attempts need the *pristine* disk, and never build/disk.img
# itself (which `make qemu` may have written to). mkdisk.sh recreates it
# unconditionally; `make disk` would leave a drifted file alone.
"$ROOT/scripts/mkdisk.sh" >/dev/null
cp --sparse=always "$BUILD/disk.img" "$DEMO.disk"
export ELIXOS_DEMO_DISK="$DEMO.disk"
export ELIXOS_DEMO_KERNEL="$BUILD/bzImage"
export ELIXOS_DEMO_INITRAMFS="$BUILD/initramfs.cpio.gz"

echo "record: $NAME -> $NAME.cast"
"$ASCII" rec --headless --window-size 80x30 -i 2 --overwrite \
  -c "expect $DEMO.exp" "$DEMO.cast"

rm -f "$DEMO.disk"

# The video is what people actually watch; the cast is its source.
demos/render.sh "$NAME"
