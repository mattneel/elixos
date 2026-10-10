#!/usr/bin/env bash
# Render one recording to a video: demos/mNN-<slug>.cast -> demos/mNN-<slug>.mp4
#
#   demos/render.sh m03-first-boot
#
# asciinema's own GIF renderer (agg) draws the frames; ffmpeg encodes them as
# H.264, which is a fraction of the size with sharper text. The GIF is only an
# intermediate and lives in build/, next to the transcript.
#
# The cast already carries the window size (80x30), so agg picks it up; a
# larger font keeps the text crisp once scaled, --fps-cap and
# --idle-time-limit keep a chatty boot from exploding the frame count.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
NAME="${1:?usage: render.sh <name>}"
DEMO="$ROOT/demos/$NAME"
FRAMES="$BUILD/$NAME.gif"

[ -f "$DEMO.cast" ] || { echo "render: no $DEMO.cast (run demos/record.sh first)" >&2; exit 1; }

AGG=""
for candidate in "${ELIXOS_AGG:-}" "$BUILD/tools/agg" "$(command -v agg || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] && AGG="$candidate" && break
done
[ -n "$AGG" ] || {
  cat >&2 <<'MSG'
render: agg is required (asciinema's frame renderer).

  curl -sfL -o build/tools/agg \
    https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-unknown-linux-gnu
  chmod +x build/tools/agg

MSG
  exit 1
}
command -v ffmpeg >/dev/null || { echo "render: ffmpeg is required (apt install ffmpeg)" >&2; exit 1; }

# agg refuses to overwrite; clearing the intermediates makes re-renders work.
rm -f "$FRAMES" "$DEMO.mp4"
"$AGG" --font-size 16 --idle-time-limit 2 --speed 1.5 --fps-cap 12 \
  "$DEMO.cast" "$FRAMES"

# H.264 wants even dimensions, and yuv420p so every player can decode it.
ffmpeg -loglevel error -y -i "$FRAMES" \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -pix_fmt yuv420p -crf 24 \
  -movflags +faststart "$DEMO.mp4"

ls -l "$DEMO.mp4" | awk '{printf "render: %s (%.0f kB)\n", $NF, $5/1024}'
