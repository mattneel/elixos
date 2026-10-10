#!/usr/bin/env bash
# Stage the guest toolchain (M11, ADR-009): zig, whose `cc`/`c++` are how a
# NIF gets built on the box. The build host fetches it once; the pristine disk
# carries it, so a guest with no network can still compile. It is deliberately
# not part of the factory: the factory is the OS, the toolchain is a tool.
#
#   scripts/fetch-toolchain.sh <staging-dir>
#
# Writes <staging-dir>/toolchain/{zig,lib,cc,...}: zig, its library and the
# cc bridge (toolchain/cc.zig), which execs `zig cc`. c++ is a symlink to cc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
STAGE="${1:?usage: fetch-toolchain.sh <staging-dir>}"
VERSION="$(cat "$ROOT/.zig-version")"
DEST="$STAGE/toolchain"

[ -x "$DEST/zig" ] && [ -x "$DEST/cc" ] && [ ! -L "$DEST/cc" ] &&
  [ "$("$DEST/zig" version)" = "$VERSION" ] && {
  echo "toolchain: $DEST (zig $VERSION, cached)"
  exit 0
}

rm -rf "$DEST"
mkdir -p "$DEST"

# The pinned Zig lives in the host's package cache; the tarballs' contents are
# what zig build already uses, so this is the same compiler, hashed by anyzig.
SOURCE="$(find "$HOME/.cache/zig/p" -maxdepth 2 -name zig -type f 2>/dev/null |
  while read -r candidate; do
    if [ "$("$candidate" version 2>/dev/null)" = "$VERSION" ]; then
      dirname "$candidate"
      break
    fi
  done)"

if [ -z "$SOURCE" ]; then
  echo "fetch-toolchain: no zig $VERSION in $HOME/.cache/zig/p" >&2
  echo "  install it with anyzig or mise, then run this again" >&2
  exit 1
fi

# Everything but the documentation: the compiler, its std library, its linker.
cp -a "$SOURCE/zig" "$SOURCE/lib" "$DEST/"
chmod +x "$DEST/zig"

# zig acts as a C compiler only when it is given the `cc` subcommand -
# being invoked under the name `cc` is not enough - so `cc` and `c++` are the
# bridge in toolchain/cc.zig, built here by the staged compiler itself. One
# binary, symlinked under both names; no shell is involved at run time.
( cd "$DEST" && "$DEST/zig" build-exe -O ReleaseSafe -target x86_64-linux-musl \
    --name cc \
    --cache-dir "$BUILD/cc-cache" \
    --global-cache-dir "$BUILD/cc-global-cache" \
    "$ROOT/toolchain/cc.zig" )
ln -sfn cc "$DEST/c++"

echo "toolchain: $DEST (zig $("$DEST/zig" version), from $SOURCE)"
