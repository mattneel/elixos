#!/usr/bin/env bash
# Build the LilyGO T-Display K230 boot firmware (M30): melange/k230-firmware.yaml,
# extracted to build/k230/firmware/ for the SD card image.
#
#   scripts/build-k230-firmware.sh
#
# The recipe cross-builds on x86_64 with Alpine's riscv-none-elf GCC
# (ADR-094: no compiler under emulation). It, the files under
# boards/t-display-k230/firmware/ and boards/t-display-k230/uboot-env.txt are
# the cache key: nothing is rebuilt while they are unchanged and the output
# exists. FORCE=1 rebuilds.
#
# Outputs (raw SD offsets for the first four):
#   spl.bin         K230-headed U-Boot SPL      0x100000 and 0x180000
#   uboot.bin       K230 header + uImage(gzip(u-boot.bin))   0x200000
#   env.bin         U-Boot environment          ENV_OFFSET in layout.env
#   layout.env      ENV_OFFSET=, ENV_SIZE=, ENV_REDUNDANT= (shell assignments)
#   fw_jump.uImage  OpenSBI 1.4 fw_jump, mkimage kernel uImage, load/entry 0
#   licenses/, SOURCES
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
MELANGE="${MELANGE:-$BUILD/tools/melange}"
KEY="$BUILD/apk/melange.rsa"
RECIPE="$ROOT/melange/k230-firmware.yaml"
BOARD="$ROOT/boards/t-display-k230"
FIRMWARE="$BOARD/firmware"
REPO="$BUILD/apk-k230-firmware"
OUT="$BUILD/k230/firmware"
ARCH=x86_64
NAMES=(spl.bin uboot.bin env.bin layout.env fw_jump.uImage SOURCES)

[ "$(uname -m)" = x86_64 ] || { echo "build-k230-firmware: needs an x86_64 build host" >&2; exit 1; }
[ -x "$MELANGE" ] || { echo "build-k230-firmware: no melange; run scripts/install-build-tools.sh" >&2; exit 1; }

inputs="$(
  cd "$ROOT"
  find melange/k230-firmware.yaml boards/t-display-k230/firmware boards/t-display-k230/uboot-env.txt \
    -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
)"
complete=1
for name in "${NAMES[@]}"; do [ -f "$OUT/$name" ] || complete=; done
if [ -z "${FORCE:-}" ] && [ -n "$complete" ] && [ "$(cat "$OUT/.inputs" 2>&1)" = "$inputs" ]; then
  echo "build-k230-firmware: inputs unchanged (cache hit)"
  exit 0
fi

mkdir -p "$BUILD/apk"
if [ ! -f "$KEY" ]; then
  echo "build-k230-firmware: generating the dev signing key (build/apk/, never committed)"
  (cd "$BUILD/apk" && "$MELANGE" keygen)
fi

# The recipe downloads its pinned sources itself; from the repository it reads
# only the board's firmware files and U-Boot environment overrides.
src="$BUILD/k230-firmware-melange-src"
rm -rf "$src" "$REPO/$ARCH"
mkdir -p "$src" "$REPO/$ARCH"
cp -r "$FIRMWARE/." "$src/"
mkdir -p "$src/patches/u-boot" "$src/patches/opensbi"
cp "$BOARD/uboot-env.txt" "$src/uboot-env.txt"
# Pinned downloads persist in build/k230-firmware-dl (melange's cache
# directory); the recipe re-verifies their sha256 on every use.
mkdir -p "$BUILD/k230-firmware-dl"
echo "build-k230-firmware: melange k230-firmware.yaml ($ARCH)"
"$MELANGE" build "$RECIPE" --arch "$ARCH" --source-dir "$src" \
  --cache-dir "$BUILD/k230-firmware-dl" \
  --out-dir "$REPO" --signing-key "$KEY" -k "$KEY.pub"

apks=("$REPO/$ARCH"/elixos-k230-firmware-*.apk)
if [ "${#apks[@]}" -ne 1 ] || [ ! -f "${apks[0]}" ]; then
  echo "build-k230-firmware: expected exactly one elixos-k230-firmware APK" >&2
  exit 1
fi

staging="$BUILD/k230/firmware.tmp"
rm -rf "$staging"
mkdir -p "$staging/tree"
tar -xzf "${apks[0]}" -C "$staging/tree" usr/share/elixos/k230-firmware
mv "$staging/tree/usr/share/elixos/k230-firmware" "$staging/out"
rm -rf "$staging/tree"
for name in "${NAMES[@]}"; do
  [ -f "$staging/out/$name" ] || { echo "build-k230-firmware: APK lacks $name" >&2; exit 1; }
done
python3 "$FIRMWARE/k230-header.py" --check "$staging/out/spl.bin"
python3 "$FIRMWARE/k230-header.py" --check "$staging/out/uboot.bin"
printf '%s\n' "$inputs" > "$staging/out/.inputs"
rm -rf "$OUT"
mv "$staging/out" "$OUT"
rmdir "$staging"
echo "build-k230-firmware: $OUT"
ls -l "$OUT"
cat "$OUT/layout.env"
