#!/usr/bin/env bash
# Build the coprocessor firmware (M32): melange/coproc-firmware.yaml,
# extracted to build/coproc/ where the M32 firmware test and the K230 image
# take it.
#
#   scripts/build-coproc-firmware.sh
#
# The recipe, coproc/, spec/ring.vectors and the AtomVM patches
# (melange/atomvm/, melange/atomvm-baremetal/) are the cache key: nothing is
# rebuilt while they are unchanged and the output exists. FORCE=1 rebuilds.
#
# Outputs (docs/notes/coproc-firmware.md):
#   coproc-k230.bin, coproc-k230.elf            the board image (load 0x07000000)
#   coproc-qemu-virt.elf, coproc-qemu-virt.bin  the QEMU virt stand-in
#   atomvmlib.avm                               AtomVM's libraries, same patches
#   mkpayload.py                                packs the payload loaded next to it
#   SOURCES, licenses/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
MELANGE="${MELANGE:-$BUILD/tools/melange}"
KEY="$BUILD/apk/melange.rsa"
RECIPE="$ROOT/melange/coproc-firmware.yaml"
REPO="$BUILD/apk-coproc-firmware"
OUT="$BUILD/coproc"
ARCH=x86_64
NAMES=(coproc-k230.bin coproc-k230.elf coproc-qemu-virt.elf coproc-qemu-virt.bin atomvmlib.avm mkpayload.py SOURCES)

[ "$(uname -m)" = x86_64 ] || { echo "build-coproc-firmware: needs an x86_64 build host" >&2; exit 1; }
[ -x "$MELANGE" ] || { echo "build-coproc-firmware: no melange; run scripts/install-build-tools.sh" >&2; exit 1; }

inputs="$(
  cd "$ROOT"
  find melange/coproc-firmware.yaml coproc spec/ring.vectors melange/atomvm melange/atomvm-baremetal \
    -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
)"
complete=1
for name in "${NAMES[@]}"; do [ -f "$OUT/$name" ] || complete=; done
if [ -z "${FORCE:-}" ] && [ -n "$complete" ] && [ "$(cat "$OUT/.inputs" 2>&1)" = "$inputs" ]; then
  echo "build-coproc-firmware: inputs unchanged (cache hit)"
  exit 0
fi

mkdir -p "$BUILD/apk"
if [ ! -f "$KEY" ]; then
  echo "build-coproc-firmware: generating the dev signing key (build/apk/, never committed)"
  (cd "$BUILD/apk" && "$MELANGE" keygen)
fi

# The recipe downloads its pinned sources itself; from the repository it reads
# the port, the ring vectors and the patches.
src="$BUILD/coproc-melange-src"
rm -rf "$src" "$REPO/$ARCH"
mkdir -p "$src/patches/atomvm" "$src/patches/atomvm-baremetal" "$REPO/$ARCH" "$BUILD/coproc-dl"
cp -r "$ROOT/coproc" "$src/coproc"
cp "$ROOT/spec/ring.vectors" "$src/ring.vectors"
cp "$ROOT"/melange/atomvm/*.patch "$src/patches/atomvm/"
cp "$ROOT"/melange/atomvm-baremetal/*.patch "$src/patches/atomvm-baremetal/"
echo "build-coproc-firmware: melange coproc-firmware.yaml ($ARCH)"
"$MELANGE" build "$RECIPE" --arch "$ARCH" --source-dir "$src" \
  --cache-dir "$BUILD/coproc-dl" \
  --out-dir "$REPO" --signing-key "$KEY" -k "$KEY.pub"

apks=("$REPO/$ARCH"/elixos-coproc-firmware-*.apk)
if [ "${#apks[@]}" -ne 1 ] || [ ! -f "${apks[0]}" ]; then
  echo "build-coproc-firmware: expected exactly one elixos-coproc-firmware APK" >&2
  exit 1
fi

staging="$BUILD/coproc.tmp"
rm -rf "$staging"
mkdir -p "$staging/tree"
tar -xzf "${apks[0]}" -C "$staging/tree" usr/share/elixos/coproc-firmware
mv "$staging/tree/usr/share/elixos/coproc-firmware" "$staging/out"
printf '%s\n' "$inputs" > "$staging/out/.inputs"
rm -rf "$OUT"
mv "$staging/out" "$OUT"
rm -rf "$staging"
ls -l "$OUT"
