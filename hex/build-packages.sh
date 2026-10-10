#!/usr/bin/env bash
# Build the tarballs that go into the official Hex repository (ADR-019).
#
#   hex/packages/<project>/   a Mix project, built with `mix hex.build`
#   hex/prebuilt/*.tar        tarballs built elsewhere, copied as they are
#
# Output: build/hex-packages/*.tar, one per package version. Runs on the dev
# host and in CI (see .github/workflows/hex-repo.yml).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ELIXOS_BUILD:-$ROOT/build}/hex-packages"

rm -rf "$OUT"
mkdir -p "$OUT"

shopt -s nullglob
for project in "$ROOT"/hex/packages/*/; do
  [ -f "$project/mix.exs" ] || continue
  echo "hex: building $(basename "$project")"
  ( cd "$project" && mix hex.build )
  for tarball in "$project"/*.tar; do
    cp "$tarball" "$OUT/"
  done
done

for tarball in "$ROOT"/hex/prebuilt/*.tar; do
  echo "hex: taking $(basename "$tarball")"
  cp "$tarball" "$OUT/"
done

echo "hex: $(ls "$OUT" | wc -l) package(s) in $OUT"
