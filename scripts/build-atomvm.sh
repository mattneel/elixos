#!/usr/bin/env bash
# Build AtomVM for the build host (M29): melange/atomvm.yaml, extracted to
# build/atomvm/ where the coprocessor tests start it.
#
#   scripts/build-atomvm.sh
# The APK is a static binary plus AtomVM's library archive, so the extracted
# tree runs on the host as is. The recipe and its patches (melange/atomvm/)
# are the cache key: nothing is rebuilt while they are unchanged and the
# output exists.
#
# Outputs: build/atomvm/AtomVM, build/atomvm/atomvmlib.avm
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
MELANGE="${MELANGE:-$BUILD/tools/melange}"
KEY="$BUILD/apk/melange.rsa"
RECIPE="$ROOT/melange/atomvm.yaml"
REPO="$BUILD/apk-atomvm"
OUT="$BUILD/atomvm"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64|aarch64) ;;
  arm64) HOST_ARCH=aarch64 ;;
  *) echo "build-atomvm: unsupported build host $HOST_ARCH" >&2; exit 1 ;;
esac

[ -x "$MELANGE" ] || { echo "build-atomvm: no melange; run scripts/install-build-tools.sh" >&2; exit 1; }

inputs="$(cat "$RECIPE" "$ROOT"/melange/atomvm/*.patch | sha256sum | cut -d' ' -f1)"
if [ -z "${FORCE:-}" ] && [ -x "$OUT/AtomVM" ] && [ -f "$OUT/atomvmlib.avm" ] &&
   [ "$(cat "$OUT/.inputs" 2>&1)" = "$inputs" ]; then
  echo "build-atomvm: inputs unchanged (cache hit)"
  exit 0
fi

mkdir -p "$BUILD/apk"
if [ ! -f "$KEY" ]; then
  echo "build-atomvm: generating the dev signing key (build/apk/, never committed)"
  (cd "$BUILD/apk" && "$MELANGE" keygen)
fi

# The recipe downloads its pinned sources itself; from the repository it reads
# only the patches it applies, which are all melange gets to see.
src="$BUILD/atomvm-melange-src"
rm -rf "$src" "$REPO/$HOST_ARCH"
mkdir -p "$src/patches" "$REPO/$HOST_ARCH"
cp "$ROOT"/melange/atomvm/*.patch "$src/patches/"
echo "build-atomvm: melange atomvm.yaml ($HOST_ARCH)"
"$MELANGE" build "$RECIPE" --arch "$HOST_ARCH" --source-dir "$src" \
  --out-dir "$REPO" --signing-key "$KEY" -k "$KEY.pub"

apks=("$REPO/$HOST_ARCH"/elixos-atomvm-*.apk)
if [ "${#apks[@]}" -ne 1 ] || [ ! -f "${apks[0]}" ]; then
  echo "build-atomvm: expected exactly one elixos-atomvm APK" >&2
  exit 1
fi

staging="$BUILD/atomvm.tmp"
rm -rf "$staging"
mkdir -p "$staging/tree"
tar -xzf "${apks[0]}" -C "$staging/tree" usr/lib/atomvm usr/share/licenses
mv "$staging/tree/usr/lib/atomvm/AtomVM" "$staging/tree/usr/lib/atomvm/atomvmlib.avm" "$staging/"
mv "$staging/tree/usr/share/licenses/elixos-atomvm" "$staging/licenses"
rm -rf "$staging/tree"
printf '%s\n' "$inputs" > "$staging/.inputs"
rm -rf "$OUT"
mv "$staging" "$OUT"
echo "build-atomvm: $OUT/AtomVM ($(file -b "$OUT/AtomVM" | cut -d, -f1-2))"
