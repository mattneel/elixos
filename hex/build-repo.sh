#!/usr/bin/env bash
# Sign and assemble the official Hex repository (ADR-019).
#
# The private key comes from $ELIXOS_HEX_PRIVATE_KEY (CI) or from the file in
# $ELIXOS_HEX_PRIVATE_KEY_FILE (a local run). The public key it produces must
# be the one the factory images ship (hex/keys/elixos.pub): if it is not, the
# key changed and every Elixos box would refuse the repository, so this stops.
#
# Output: build/hex-repo/public/{names,versions,packages/,tarballs/,public_key}
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
PACKAGES="$BUILD/hex-packages"
REPO="$BUILD/hex-repo"
NAME=elixos

KEY_FILE="${ELIXOS_HEX_PRIVATE_KEY_FILE:-$BUILD/keys/$NAME-private.pem}"
if [ -n "${ELIXOS_HEX_PRIVATE_KEY:-}" ]; then
  mkdir -p "$(dirname "$KEY_FILE")"
  printf '%s\n' "$ELIXOS_HEX_PRIVATE_KEY" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
fi
[ -f "$KEY_FILE" ] || {
  echo "build-repo: no private key: set ELIXOS_HEX_PRIVATE_KEY or create $KEY_FILE" >&2
  exit 1
}

rm -rf "$REPO"
mkdir -p "$REPO/public/tarballs"
cp "$PACKAGES"/*.tar "$REPO/public/tarballs/" 2>/dev/null || true

mix hex.registry build "$REPO/public" --name="$NAME" --private-key="$KEY_FILE"

if ! cmp -s "$REPO/public/public_key" "$ROOT/hex/keys/$NAME.pub"; then
  echo "build-repo: the signing key is not the one hex/keys/$NAME.pub ships." >&2
  echo "  Factory images trust the shipped key, so this repository would be" >&2
  echo "  refused everywhere. Restore the old key, or ship the new public" >&2
  echo "  key in the factory and add an ADR (AGENTS.md)." >&2
  exit 1
fi

echo "build-repo: $REPO/public"
ls "$REPO/public"
