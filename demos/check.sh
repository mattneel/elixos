#!/usr/bin/env bash
# Check one recording: demos/mNN-<slug>.cast must show what it claims.
#
#   demos/check.sh m03-first-boot
#
# The cast is dumped as text (asciinema convert -f txt) and every line in the
# demo's .keys file must appear, in order; the recording must end on the shim's
# shutdown line and must not contain a kernel panic.
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
"$ASCII" convert -f txt -o "$TEXT" "$DEMO.cast" >/dev/null

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

if [ "$problems" -eq 0 ]; then
  echo "check: $NAME ok ($(grep -c '' "$TEXT") lines of transcript)"
else
  echo "check: $NAME: $problems problem(s); transcript: $TEXT" >&2
fi
[ "$problems" -eq 0 ]
