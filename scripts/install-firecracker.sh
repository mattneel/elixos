#!/usr/bin/env bash
# Install the checksum-pinned upstream VMM into build/, never system directories.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
VERSION=1.17.0
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) SHA256=06094a1108ae9e82aa4c23a775aa92758f53f1175d422270d9d6162cb9ade558 ;;
  aarch64) SHA256=e351ebe4f7a16b5873bbd51005d2e6767103cff4d5ebc829df2d3f95a93e2256 ;;
  *) echo "firecracker: unsupported host architecture $ARCH" >&2; exit 1 ;;
esac
ARCHIVE="$BUILD/dl/firecracker-v$VERSION-$ARCH.tgz"
DEST="$BUILD/tools/firecracker-v$VERSION-$ARCH"
mkdir -p "$BUILD/dl" "$DEST"
if [ ! -f "$ARCHIVE" ]; then
  curl -fL --retry 3 -o "$ARCHIVE.part" \
    "https://github.com/firecracker-microvm/firecracker/releases/download/v$VERSION/firecracker-v$VERSION-$ARCH.tgz"
  printf '%s  %s\n' "$SHA256" "$ARCHIVE.part" | sha256sum -c -
  mv "$ARCHIVE.part" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | sha256sum -c -
STAGE="$(mktemp -d "$DEST/.extract.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
MEMBER="release-v$VERSION-$ARCH/firecracker-v$VERSION-$ARCH"
tar -xzf "$ARCHIVE" -C "$STAGE" "$MEMBER"
install -m0755 "$STAGE/$MEMBER" "$DEST/firecracker.part"
mv "$DEST/firecracker.part" "$DEST/firecracker"
echo "firecracker: $DEST/firecracker (upstream v$VERSION, verified SHA256)"
