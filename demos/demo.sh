#!/usr/bin/env bash
# Record and check the demo recordings (demos/README.md).
#
#   demos/demo.sh 3        one milestone, by number
#   demos/demo.sh --all    every visible milestone up to the MILESTONE file
#
# A "visible" milestone is one with a QEMU test (M3-M9, M11-M13, M14): there is
# something to look at. Each demo is one expect script and one .cast.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

record_and_check() { # <name like m03-first-boot>
  local name="$1"
  demos/record.sh "${name%%-*}" "$name"
  demos/check.sh "$name"
}

case "${1:-}" in
  --all)
    milestone="$(cat MILESTONE)"
    for exp in demos/m*.exp; do
      name="$(basename "$exp" .exp)"
      # `m03-first-boot` is milestone 3: strip the m, then the leading zero.
      n="${name%%-*}"
      n="${n#m}"
      n="$((10#$n))"
      [ "$n" -le "$milestone" ] || continue
      record_and_check "$name"
    done
    ;;
  "")
    echo "usage: demos/demo.sh <milestone> | --all" >&2
    exit 1
    ;;
  *)
    matches=(demos/m$(printf '%02d' "$1")-*.exp)
    [ -f "${matches[0]}" ] || { echo "demo.sh: no demo for milestone $1" >&2; exit 1; }
    [ "${#matches[@]}" -eq 1 ] || { echo "demo.sh: milestone $1 has several demos" >&2; exit 1; }
    record_and_check "$(basename "${matches[0]}" .exp)"
    ;;
esac

echo "demos: ok"
