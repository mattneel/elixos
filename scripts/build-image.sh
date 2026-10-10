#!/usr/bin/env bash
# Build the Elixos images (M16, ADR-041).
#
#   scripts/build-image.sh [arch ...]        default: x86_64 aarch64
#
# Per architecture:
#   1. stage the sources the melange packages read (a small copy: melange
#      *copies* --source-dir into its workspace);
#   2. build every melange/*.yaml APK with melange, signed with the dev key in
#      build/apk/ (gitignored), into build/apk/<arch>/;
#   3. resolve the Alpine set with `apko lock` into the committed
#      apko/apko.lock.<arch>.json (the lock is bound to the config's checksum,
#      so it is regenerated whenever the config changes);
#   4. assemble the root filesystem with apko build, which also writes the
#      SPDX SBOM next to the image;
#   5. pack the layer into the initramfs (scripts/mkinitramfs.sh) and copy the
#      kernel out of its APK;
#   6. check the SBOM names every elixos-* package the config asks for, and
#      that a second assembly of the same lockfile yields the same layer
#      digest (reproducibility).
#
# Outputs:
#   x86_64:  build/bzImage, build/initramfs.cpio.gz   (where the tests look)
#   aarch64: build/aarch64/Image, build/aarch64/initramfs.cpio.gz
#   both:    build/<arch>/rootfs.tar, sbom-<arch>.spdx.json, rootfs.digest
#
# Everything is pinned: our packages by the sha256s in their melange YAMLs, the
# Alpine set by the lockfile, melange and apko by
# scripts/install-build-tools.sh. The APK mirror is build/mirror.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
TOOLS="$BUILD/tools"
MELANGE="${MELANGE:-$TOOLS/melange}"
APKO="${APKO:-$TOOLS/apko}"
KEY="$BUILD/apk/melange.rsa"
MIRROR="$BUILD/mirror"
SRC="$BUILD/melange-src"
# One date for every assembly: file timestamps are the only thing that would
# otherwise differ between two builds of the same lockfile.
BUILD_DATE="${BUILD_DATE:-2026-01-01T00:00:00Z}"

[ -x "$MELANGE" ] || { echo "build-image: no melange; run scripts/install-build-tools.sh" >&2; exit 1; }
[ -x "$APKO" ] || { echo "build-image: no apko; run scripts/install-build-tools.sh" >&2; exit 1; }
[ -x "$ROOT/scripts/mkinitramfs.sh" ] || { echo "build-image: scripts/mkinitramfs.sh missing" >&2; exit 1; }

mkdir -p "$BUILD/apk" "$MIRROR"
if [ ! -f "$KEY" ]; then
  echo "build-image: generating the dev signing key (build/apk/, never committed)"
  (cd "$BUILD/apk" && "$MELANGE" keygen >/dev/null)
fi

stage() {
  # Only what the packages read: melange copies this directory into its
  # workspace, so it must not be the repository (55G, once).
  rm -rf "$SRC"
  mkdir -p "$SRC/os"
  cp -r "$ROOT/build.zig" "$ROOT/build.zig.zon" "$ROOT/.zig-version" "$ROOT/.tool-versions" \
        "$ROOT/shim" "$ROOT/spec" "$ROOT/kernel" "$ROOT/scripts" "$SRC/"
  cp -r "$ROOT/os/mix.exs" "$ROOT/os/mix.lock" "$ROOT/os/lib" "$ROOT/os/config" "$SRC/os/"
}

build_packages() { # build_packages <arch>
  local arch="$1" repo="$BUILD/apk/$arch" pkg pname
  for pkg in "$ROOT"/melange/*.yaml; do
    pname="elixos-$(basename "$pkg" .yaml)"
    # An architecture's OTP build is expensive (aarch64 runs emulated on an
    # x86_64 host), so a built APK is kept: delete build/apk (or the one APK)
    # to rebuild from source, the way the old toolchain cache worked.
    if [ -z "${FORCE:-}" ] && ls "$repo/$arch/$pname"-*.apk >/dev/null 2>&1; then
      echo "build-image: [$arch] $pname already built (FORCE=1 rebuilds)"
      continue
    fi
    echo "build-image: [$arch] melange $(basename "$pkg")"
    # -r/-k let a package build against the ones built before it (the factory
    # needs OTP and Elixir; melange would otherwise only see Alpine).
    "$MELANGE" build "$pkg" --arch "$arch" --source-dir "$SRC" \
      --out-dir "$repo" --signing-key "$KEY" \
      -r "$repo" -k "$KEY.pub" >/dev/null
  done
}

build_index() { # build_index <arch>
  # Regenerate the repository index from the APKs themselves: melange updates
  # it per build, but a merge or a stale index silently hides a package from
  # the guest's resolution ("nothing provides elixos-otp"), so this is not
  # left to chance.
  local arch="$1" repo="$BUILD/apk/$arch/$arch"
  ( cd "$repo" && "$MELANGE" index -a "$arch" --signing-key "$KEY" -o APKINDEX.tar.gz ./*.apk >/dev/null )
}

lock() { # lock <arch>
  local arch="$1"
  "$APKO" lock "$ROOT/apko/apko.yaml" --arch "$arch" \
    -r "$BUILD/apk/$arch" -k "$KEY.pub" \
    --cache-dir "$MIRROR" --output "$ROOT/apko/apko.lock.$arch.json"
}

assemble() { # assemble <arch> <output tar>
  local arch="$1" out="$2"
  "$APKO" build --lockfile "$ROOT/apko/apko.lock.$arch.json" --arch "$arch" \
    -r "$BUILD/apk/$arch" -k "$KEY.pub" \
    --build-date "$BUILD_DATE" --sbom-path "$(dirname "$out")" --cache-dir "$MIRROR" \
    "$ROOT/apko/apko.yaml" "elixos:$arch" "$out"
}

layer_digest() { # layer_digest <image tar>: the layer file *is* named by its digest
  tar -tf "$1" | grep -E '\.tar\.gz$' | head -n1
}

check_sbom() { # check_sbom <arch> <sbom>
  local arch="$1" sbom="$2"
  # Every elixos-* package the image config asks for must be in the SBOM with
  # its version - that is the acceptance's "the SBOM lists at least the kernel,
  # OTP and Elixir versions", and it tightens as the packages land.
  python3 - "$ROOT/apko/apko.yaml" "$sbom" "$arch" <<'PY'
import json, re, sys

config, sbom, arch = sys.argv[1], sys.argv[2], sys.argv[3]
wanted = re.findall(r"^\s*- (elixos-[a-z]+)$", open(config).read(), re.M)
packages = {p["name"]: p.get("versionInfo", "") for p in json.load(open(sbom))["packages"]}

for name in wanted:
    if name in packages:
        print(f"build-image: [{arch}] sbom: {name} {packages[name]}")

missing = [name for name in wanted if name not in packages]
if missing:
    print(f"build-image: [{arch}] in the image config, not in the SBOM: {' '.join(missing)}",
          file=sys.stderr)
    sys.exit(1)
PY
}

build_arch() { # build_arch <arch>
  local arch="$1" work="$BUILD/$arch" digest second
  mkdir -p "$work"

  build_packages "$arch"
  build_index "$arch"
  lock "$arch"
  assemble "$arch" "$work/rootfs.tar"

  rm -rf "$work/oci"
  mkdir -p "$work/oci"
  tar -xf "$work/rootfs.tar" -C "$work/oci"
  local layer
  layer="$(ls "$work"/oci/*.tar.gz)"
  "$ROOT/scripts/mkinitramfs.sh" "$layer" "$work/initramfs.cpio.gz"

  # The kernel is a file the firmware/QEMU loads, not part of the root
  # filesystem: take it out of its own APK.
  local kernel_apk
  kernel_apk="$(ls "$BUILD/apk/$arch/$arch"/elixos-kernel-*.apk)" || {
    echo "build-image: [$arch] no kernel APK; the image has no kernel yet" >&2
    return 1
  }
  case "$arch" in
    x86_64) tar -xzf "$kernel_apk" -O boot/bzImage > "$work/bzImage" ;;
    aarch64) tar -xzf "$kernel_apk" -O boot/Image > "$work/Image" ;;
  esac

  check_sbom "$arch" "$work/sbom-$arch.spdx.json"

  # Reproducible: assemble the same lockfile again and compare the layer
  # digest, which apko names the blob by.
  digest="$(layer_digest "$work/rootfs.tar")"
  assemble "$arch" "$work/rootfs-again.tar" >/dev/null
  second="$(layer_digest "$work/rootfs-again.tar")"
  if [ "$digest" != "$second" ]; then
    echo "build-image: [$arch] not reproducible: $digest vs $second" >&2
    exit 1
  fi
  echo "$digest" > "$work/rootfs.digest"
  echo "build-image: [$arch] rootfs digest $digest (two builds agree)"

  # x86_64 writes the paths the QEMU tests look for by default.
  if [ "$arch" = x86_64 ]; then
    cp "$work/bzImage" "$BUILD/bzImage"
    cp "$work/initramfs.cpio.gz" "$BUILD/initramfs.cpio.gz"
  fi
}

stage

if [ "$#" -eq 0 ]; then
  set -- x86_64 aarch64
fi

for arch in "$@"; do
  echo "build-image: == $arch =="
  build_arch "$arch"
done
echo "build-image: done"
