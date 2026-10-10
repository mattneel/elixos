#!/usr/bin/env bash
# Install the pinned melange and apko into build/tools (M16, ADR-041).
#
#   scripts/install-build-tools.sh
#
# Both are Go binaries built by Chainguard; both are pinned here by version and
# sha256, and the host arch picks the release. They run on the *build host*
# only - the box never sees them - but they are pins like the kernel's
# (ADR-001): a build must not change because an upstream tag moved.
#
# If a pin no longer resolves, fetch the release's checksums.txt, read the new
# sha256, update it here, and say why in the commit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="${ELIXOS_BUILD:-$ROOT/build}/tools"

MELANGE_VERSION=0.62.0
APKO_VERSION=1.4.10

case "$(uname -m)" in
  x86_64)
    MELANGE_SHA256=1d41c132fefc3b8cc5f1927c28c2f6c61a53f35f3b267913938731b03de16e80
    APKO_SHA256=c5254f80e8d06d423616f6df6ea900bf95164ff08d7ce69c7f677a1a41eadd88
    ARCH=amd64
    ;;
  aarch64|arm64)
    MELANGE_SHA256=5541c281d0a07b253baa7a4879298ddf2c8bf00a1d70043ede7cfbdf9b8ccbc0
    APKO_SHA256=78780544e3cb32c94109db66ebb852aec15e68eeb4b2df538d9b01c3add0e3eb
    ARCH=arm64
    ;;
  *)
    echo "install-build-tools: unsupported host arch $(uname -m)" >&2
    exit 1
    ;;
esac

install_one() { # install_one <name> <version> <sha256> <url>
  local name="$1" version="$2" sha256="$3" url="$4"
  local dest="$TOOLS/$name"

  if [ -x "$dest" ] && "$dest" version 2>/dev/null | grep -q "$version"; then
    echo "$name $version already installed"
    return
  fi

  echo "downloading $url"
  curl -fL --retry 3 -o "$TOOLS/$name.tar.gz" "$url"
  echo "$sha256  $TOOLS/$name.tar.gz" | sha256sum -c -

  # The releases pack one directory (<name>_<version>_linux_<arch>/) with the
  # binary and a license; take the binary out of it.
  local member
  member="$(tar -tzf "$TOOLS/$name.tar.gz" | grep -E "(^|/)$name\$" | head -n1)"
  [ -n "$member" ] || { echo "install-build-tools: no $name in the archive" >&2; exit 1; }
  tar -xzf "$TOOLS/$name.tar.gz" -C "$TOOLS" --strip-components=1 "$member"

  rm -f "$TOOLS/$name.tar.gz"
  chmod +x "$dest"
}

mkdir -p "$TOOLS"

install_one melange "$MELANGE_VERSION" "$MELANGE_SHA256" \
  "https://github.com/chainguard-dev/melange/releases/download/v$MELANGE_VERSION/melange_${MELANGE_VERSION}_linux_${ARCH}.tar.gz"

install_one apko "$APKO_VERSION" "$APKO_SHA256" \
  "https://github.com/chainguard-dev/apko/releases/download/v$APKO_VERSION/apko_${APKO_VERSION}_linux_${ARCH}.tar.gz"

echo "melange $("$TOOLS/melange" version 2>/dev/null | awk '/GitVersion/ {print $2}')"
echo "apko    $("$TOOLS/apko" version 2>/dev/null | awk '/GitVersion/ {print $2}')"
