#!/usr/bin/env bash
# Install the Zig nightly pinned in .zig-version into ~/.local/zig/<version>
# and print the PATH line to use. Elixos tracks Zig master (ADR-003).
#
# ziglang.org only keeps recent master builds. If the pinned one is gone,
# bump .zig-version (and build.zig.zon's minimum_zig_version) to the current
# "master" version from https://ziglang.org/download/index.json, then fix
# whatever the compiler reports. That is expected work, not a failure.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(head -n1 "$ROOT/.zig-version")"
DEST="${ZIG_HOME:-$HOME/.local/zig}/$VERSION"
ARCH="$(uname -m)"

if [ -x "$DEST/zig" ]; then
  echo "zig $VERSION already installed"
else
  case "$VERSION" in
    *-dev.*) URL="https://ziglang.org/builds/zig-$ARCH-linux-$VERSION.tar.xz" ;;
    *) URL="https://ziglang.org/download/$VERSION/zig-$ARCH-linux-$VERSION.tar.xz" ;;
  esac
  echo "downloading $URL"
  mkdir -p "$DEST"
  if ! curl -fL --retry 3 "$URL" | tar -xJ --strip-components=1 -C "$DEST"; then
    rm -rf "$DEST"
    echo "could not download zig $VERSION; see the comment at the top of this script" >&2
    exit 1
  fi
fi

"$DEST/zig" version
echo "add to your shell profile:  export PATH=\"$DEST:\$PATH\""
