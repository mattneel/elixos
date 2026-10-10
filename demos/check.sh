#!/usr/bin/env bash
# Check one recording: demos/mNN-<slug>.cast must show what it claims.
#
#   demos/check.sh m03-first-boot
#
# Every line in the demo's .keys file must appear in the recording, in order;
# the recording must end on the shim's shutdown line, must not contain a kernel
# panic, and must have a video next to it.
#
# The assertions run against the cast's own output events, not against
# `asciinema convert -f txt`: that export renders the *screen*, so a burst of
# output that scrolled past inside one frame can be missing from it (a boot's
# shim lines, for instance). The screen dump is written next to the raw dump,
# for reading.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
NAME="${1:?usage: check.sh <name>}"
DEMO="$ROOT/demos/$NAME"

[ -f "$DEMO.cast" ] || { echo "check: no $DEMO.cast (run make demo M=..)" >&2; exit 1; }
[ -f "$DEMO.keys" ] || { echo "check: no $DEMO.keys" >&2; exit 1; }

ASCII=""
for candidate in "${ELIXOS_ASCIINEMA:-}" "$BUILD/tools/asciinema" "$(command -v asciinema || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] || continue
  if "$candidate" --version 2>/dev/null | grep -q '^asciinema 3'; then ASCII="$candidate"; break; fi
done
[ -n "$ASCII" ] || { echo "check: asciinema 3.x is required (see demos/README.md)" >&2; exit 1; }

TEXT="$BUILD/$NAME.txt"
SCREEN="$BUILD/$NAME.screen.txt"

# asciinema 3 writes one JSON line per event: [time, kind, data]. The output
# events (kind "o") are the console, byte for byte.
python3 - "$DEMO.cast" "$TEXT" <<'PY'
import json, sys

with open(sys.argv[1]) as cast, open(sys.argv[2], "w") as out:
    json.loads(cast.readline())  # the header
    for line in cast:
        if line.strip():
            event = json.loads(line)
            if event[1] == "o":
                out.write(event[2])
PY

rm -f "$SCREEN"
"$ASCII" convert -f txt "$DEMO.cast" "$SCREEN" >/dev/null

problems=0
# Every expected line, in order: a demo that shows them out of order does not
# show the same story.
position=0
while IFS= read -r pattern; do
  [ -n "$pattern" ] || continue
  case "$pattern" in \#*) continue ;; esac
  found="$(tail -n "+$((position + 1))" "$TEXT" | grep -n -m1 -F -- "$pattern" | cut -d: -f1 || true)"
  if [ -z "$found" ]; then
    echo "check: $NAME: missing (or out of order): $pattern" >&2
    problems=$((problems + 1))
  else
    position=$((position + found))
  fi
done < "$DEMO.keys"

if ! grep -q "elixos-shim: shutdown poweroff" "$TEXT"; then
  echo "check: $NAME: the recording does not end on 'elixos-shim: shutdown poweroff'" >&2
  problems=$((problems + 1))
fi

if grep -q "Kernel panic" "$TEXT"; then
  echo "check: $NAME: the recording contains a kernel panic" >&2
  problems=$((problems + 1))
fi

if [ ! -s "$DEMO.mp4" ]; then
  echo "check: $NAME: no video ($DEMO.mp4); run demos/render.sh $NAME" >&2
  problems=$((problems + 1))
fi

if [ "$problems" -eq 0 ]; then
  echo "check: $NAME ok ($(wc -c < "$TEXT" | tr -d ' ') bytes of console)"
else
  echo "check: $NAME: $problems problem(s); raw: $TEXT, screen: $SCREEN" >&2
fi
[ "$problems" -eq 0 ]
