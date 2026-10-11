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
#   both:    build/<arch>/system.squashfs, system/sbom-<arch>.spdx.json,
#            system.digest (a second gzip SquashFS assembly must agree)
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
ZIG_CACHE="$BUILD/melange-cache"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64|aarch64) ;;
  arm64) HOST_ARCH=aarch64 ;;
  *) echo "build-image: unsupported build host $HOST_ARCH" >&2; exit 1 ;;
esac
# One date for every assembly: file timestamps are the only thing that would
# otherwise differ between two builds of the same lockfile.
BUILD_DATE="${BUILD_DATE:-2026-01-01T00:00:00Z}"

[ -x "$MELANGE" ] || { echo "build-image: no melange; run scripts/install-build-tools.sh" >&2; exit 1; }
[ -x "$APKO" ] || { echo "build-image: no apko; run scripts/install-build-tools.sh" >&2; exit 1; }
[ -x "$ROOT/scripts/mkinitramfs.sh" ] || { echo "build-image: scripts/mkinitramfs.sh missing" >&2; exit 1; }
[ -x "$(command -v mksquashfs)" ] || { echo "build-image: no mksquashfs; install squashfs-tools" >&2; exit 1; }

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
        "$ROOT/shim" "$ROOT/spec" "$ROOT/kernel" "$ROOT/scripts" "$ROOT/hex" "$ROOT/toolchain" \
        "$SRC/"
  cp -r "$ROOT/os/mix.exs" "$ROOT/os/mix.lock" "$ROOT/os/lib" "$ROOT/os/config" "$ROOT/os/priv" "$SRC/os/"
  cp -r "$ROOT/melange" "$SRC/"
}

package_inputs() { # package_inputs <arch> <package>: hash of everything the recipe reads
  local arch="$1" pkg="$2" path
  local -a paths
  case "$pkg" in
    kernel) paths=(kernel melange/kernel.yaml prebuilt/kernel) ;;
    otp) paths=(.tool-versions melange/otp.yaml) ;;
    elixir) paths=(.tool-versions melange/elixir.yaml prebuilt/elixir prebuilt/elixir.links) ;;
    factory) paths=(os hex .tool-versions melange/factory.yaml prebuilt/factory prebuilt/factory.links) ;;
    shim) paths=(shim spec .zig-version build.zig build.zig.zon melange/shim.yaml) ;;
    toolchain) paths=(toolchain .zig-version melange/toolchain.yaml) ;;
    *) paths=(melange) ;;
  esac

  {
    printf 'arch=%s\nhost=%s\npackage=%s\n' "$arch" "$HOST_ARCH" "$pkg"
    # The tools that run the build are inputs too: a new melange or a new
    # signing key must not reuse what the old one produced.
    sha256sum "$MELANGE" "$KEY.pub"
    (
      cd "$SRC"
      for path in "${paths[@]}"; do
        [ -e "$path" ] || continue
        if [ -d "$path" ]; then
          find "$path" -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
        else
          sha256sum "$path"
        fi
      done
    )
  } | sha256sum | cut -d' ' -f1
}

kernel_cross_inputs() { # kernel_cross_inputs: what the native arm64 build reads
  {
    printf 'package=kernel-cross\n'
    sha256sum "$MELANGE" "$KEY.pub" "$ROOT/melange/kernel-cross.yaml"
    (
      cd "$SRC"
      for path in kernel scripts; do
        find "$path" -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
      done
    )
  } | sha256sum | cut -d' ' -f1
}

# The arm64 kernel, compiled natively on the build host (ADR-060): a melange
# pipeline runs inside the target rootfs, so the only way to cross is a
# separate, native step whose artifact the aarch64 package installs. This is
# the kernel's own LLVM=1 cross mode; the kernel is freestanding, so no
# sysroot and no target packages are involved.
kernel_cross() {
  # A build tool, not an image package: it lives in its own repository, so no
  # image glob (elixos-kernel-*.apk) can ever pick it up as a kernel.
  local repo="$BUILD/apk-cross" stamp="$BUILD/apk-cross/.kernel-cross.inputs" inputs apk
  local cached_inputs="" cached_sha="" cached_apk=""
  inputs="$(kernel_cross_inputs)"
  if [ -f "$stamp" ]; then
    read -r cached_inputs cached_sha cached_apk < "$stamp" || true
  fi

  apk="$repo/x86_64/$cached_apk"
  if [ -n "${FORCE:-}" ] || [ "$inputs" != "$cached_inputs" ] || [ ! -f "$apk" ] ||
     [ "$(sha256sum "$apk" 2>/dev/null | cut -d' ' -f1)" != "$cached_sha" ]; then
    echo "build-image: melange kernel-cross.yaml (arm64 kernel, native cross)"
    rm -rf "$repo/x86_64" "$stamp"
    mkdir -p "$repo/x86_64"
    # The same compiler cache and host-arch variable the shim package uses:
    # one pinned Zig SDK, shared, outside melange's per-build workspace.
    mkdir -p "$ZIG_CACHE"
    printf 'ELIXOS_ZIG_HOST_ARCH=%s\n' "$HOST_ARCH" > "$ZIG_CACHE/host.env"
    "$MELANGE" build "$ROOT/melange/kernel-cross.yaml" --arch x86_64 --source-dir "$SRC" \
      --out-dir "$repo" --signing-key "$KEY" -r "$repo" -k "$KEY.pub" \
      --cache-dir "$ZIG_CACHE" --env-file "$ZIG_CACHE/host.env" >/dev/null
    apk="$(ls "$repo"/x86_64/elixos-kernel-cross-*.apk | head -n1)"
    [ -f "$apk" ] || { echo "build-image: no elixos-kernel-cross APK was produced" >&2; return 1; }
    printf '%s %s %s\n' "$inputs" "$(sha256sum "$apk" | cut -d' ' -f1)" "$(basename "$apk")" > "$stamp"
  else
    echo "build-image: elixos-kernel-cross inputs unchanged (cache hit)"
  fi

  stage_prebuilt kernel "$apk"
}

# Adopt a native build: unpack the APK it produced into the staging area the
# architecture's package installs from. melange APKs are tar streams a plain
# tar reads (mkdisk.sh does the same for the toolchain).
stage_prebuilt() { # stage_prebuilt <name> <apk>
  local name="$1" archive="$2" dir="$SRC/prebuilt/$1" tmp="$SRC/prebuilt/.$1.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  tar -xzf "$archive" --warning=no-unknown-keyword -C "$tmp"
  [ -n "$(ls -A "$tmp")" ] || {
    echo "build-image: the native $name build produced nothing" >&2
    rm -rf "$tmp"
    return 1
  }
  # melange's workspace copy does not carry symlinks whose target is outside
  # the tree (the release's links into /usr/local/lib/erlang, Elixir's bin
  # links): record them here so the package can recreate them itself.
  ( cd "$tmp" && find . -type l -printf '%P\t%l\n' ) | LC_ALL=C sort > "$dir.links.tmp"

  rm -rf "$dir"
  mv "$tmp" "$dir"
  mv "$dir.links.tmp" "$dir.links"
  echo "build-image: staged the native $name build ($(wc -l < "$dir.links") symlink(s) recorded)"
}

# Elixir and the factory are architecture-neutral (ADR-060): build them once
# in the native x86_64 environment - the same recipes the x86_64 image uses -
# and hand the aarch64 packages the tree instead of rebuilding it emulated.
native_reuse() {
  local pkg pname repo="$BUILD/apk/x86_64" apk
  for pkg in elixir factory; do
    pname="elixos-$pkg"
    if [ -n "${FORCE:-}" ] || ! ls "$repo/$HOST_ARCH/$pname"-*.apk >/dev/null 2>&1; then
      echo "build-image: melange $pkg.yaml (native, for the $HOST_ARCH image)"
      "$MELANGE" build "$SRC/melange/$pkg.yaml" --arch "$HOST_ARCH" --source-dir "$SRC" \
        --out-dir "$repo" --signing-key "$KEY" \
        -r "$repo" -k "$KEY.pub" >/dev/null
    fi
    apk="$(ls "$repo/$HOST_ARCH/$pname"-*.apk | head -n1)"
    [ -f "$apk" ] || { echo "build-image: no $pname APK to reuse" >&2; return 1; }
    stage_prebuilt "$pkg" "$apk"
  done
}

build_packages() { # build_packages <arch>
  local arch="$1" repo="$BUILD/apk/$arch" pkg pname file inputs stamp actual
  local cached_inputs="" cached_sha="" cached_apk=""
  local -a extra apks
  # Dependency order, not glob order: OTP before Elixir and the factory (they
  # build against it), the kernel and the shim independent, the toolchain last
  # (it needs only a compiler).
  for pkg in kernel otp elixir factory shim toolchain; do
    file="$SRC/melange/$pkg.yaml"
    [ -f "$file" ] || continue
    pname="elixos-$pkg"
    inputs="$(package_inputs "$arch" "$pkg")"
    stamp="$repo/$arch/.$pname.inputs"
    cached_inputs="" cached_sha="" cached_apk=""
    if [ -f "$stamp" ]; then
      read -r cached_inputs cached_sha cached_apk < "$stamp" || true
    fi

    # A hit needs the recipe's inputs to match *and* the APK the last build
    # published to still be those bytes: an APK that exists is not an APK
    # that is current, and a stale factory would ship the wrong OS.
    if [ -z "${FORCE:-}" ] && [ "$inputs" = "$cached_inputs" ] &&
       [ -n "$cached_apk" ] && [ -f "$repo/$arch/$cached_apk" ]; then
      actual="$(sha256sum "$repo/$arch/$cached_apk" | cut -d' ' -f1)"
      if [ "$actual" = "$cached_sha" ]; then
        echo "build-image: [$arch] $pname inputs unchanged (cache hit)"
        continue
      fi
    fi

    extra=()
    if [ "$pkg" = shim ]; then
      # Only the shim builds with Zig; its compiler and local/global caches
      # live outside melange's per-build workspace (see docs/notes).
      mkdir -p "$ZIG_CACHE"
      printf 'ELIXOS_ZIG_HOST_ARCH=%s\n' "$HOST_ARCH" > "$ZIG_CACHE/host.env"
      extra=(--cache-dir "$ZIG_CACHE" --env-file "$ZIG_CACHE/host.env")
    fi

    # Publish only this recipe's APK; an old build must not shadow the new one,
    # and the stamp leaves with it.
    echo "build-image: [$arch] melange $(basename "$file")"
    rm -f "$repo/$arch/$pname"-*.apk "$stamp"
    # -r/-k let a package build against the ones built before it (the factory
    # needs OTP and Elixir; melange would otherwise only see Alpine).
    "$MELANGE" build "$file" --arch "$arch" --source-dir "$SRC" \
      --out-dir "$repo" --signing-key "$KEY" \
      -r "$repo" -k "$KEY.pub" "${extra[@]}" >/dev/null

    apks=("$repo/$arch/$pname"-*.apk)
    if [ "${#apks[@]}" -ne 1 ] || [ ! -f "${apks[0]}" ]; then
      echo "build-image: [$arch] expected exactly one freshly built $pname APK" >&2
      return 1
    fi
    actual="$(sha256sum "${apks[0]}" | cut -d' ' -f1)"
    printf '%s %s %s\n' "$inputs" "$actual" "${apks[0]##*/}" > "$stamp.tmp"
    mv "$stamp.tmp" "$stamp"
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

system_lock() { # system_lock <arch>: retain committed pins until config changes
  local arch="$1" config="$ROOT/apko/system.yaml" lockfile="$ROOT/apko/system.lock.$1.json"
  if ! python3 - "$config" "$lockfile" <<'PY'
import base64, hashlib, json, sys
try:
    checksum = "sha256-" + base64.b64encode(hashlib.sha256(open(sys.argv[1], "rb").read()).digest()).decode()
    current = json.load(open(sys.argv[2]))["config"]["checksum"]
except (OSError, KeyError, ValueError):
    sys.exit(1)
sys.exit(0 if current == checksum else 1)
PY
  then
    "$APKO" lock "$config" --arch "$arch" --cache-dir "$MIRROR" --output "$lockfile"
  fi
}

assemble_system() { # assemble_system <arch> <work directory>
  local arch="$1" work="$2" epoch
  epoch="$(date -u -d "$BUILD_DATE" +%s)"
  mkdir -p "$work"
  "$APKO" build --lockfile "$ROOT/apko/system.lock.$arch.json" --arch "$arch" \
    --build-date "$BUILD_DATE" --sbom-path "$work" --cache-dir "$MIRROR" \
    "$ROOT/apko/system.yaml" "elixos-system:$arch" "$work/rootfs.tar"
  rm -rf "$work/oci" "$work/rootfs"
  mkdir -p "$work/oci" "$work/rootfs"
  tar -xf "$work/rootfs.tar" -C "$work/oci"
  local layers=("$work"/oci/*.tar.gz)
  [ "${#layers[@]}" -eq 1 ] && [ -f "${layers[0]}" ] || {
    echo "build-image: [$arch] expected exactly one system layer" >&2; return 1;
  }
  # Services use the machine's /dev, not /system/dev. Exclude apko's device
  # placeholders so assembling this read-only asset does not require root.
  tar -xzf "${layers[0]}" -C "$work/rootfs" --exclude='dev/*' --exclude='./dev/*'
  # Stable ordering, timestamps, ownership and compressor concurrency. Do not
  # append: an old filesystem must never influence a new image.
  mksquashfs "$work/rootfs" "$work/system.squashfs" -noappend -comp gzip \
    -all-root -no-xattrs -mkfs-time "$epoch" -all-time "$epoch" -processors 1 -no-progress
}

build_system() { # build_system <arch>
  local arch="$1" work="$BUILD/$1" digest second
  system_lock "$arch"
  assemble_system "$arch" "$work/system"
  check_sbom "$arch" "$work/system/sbom-$arch.spdx.json" "$ROOT/apko/system.yaml"
  assemble_system "$arch" "$work/system-again" >/dev/null
  digest="$(sha256sum "$work/system/system.squashfs" | cut -d' ' -f1)"
  second="$(sha256sum "$work/system-again/system.squashfs" | cut -d' ' -f1)"
  [ "$digest" = "$second" ] || {
    echo "build-image: [$arch] system not reproducible: $digest vs $second" >&2; return 1;
  }
  install -m0444 "$work/system/system.squashfs" "$work/system.squashfs"
  echo "$digest" > "$work/system.digest"
  echo "build-image: [$arch] system digest $digest (two builds agree)"
}

layer_digest() { # layer_digest <image tar>: the layer file *is* named by its digest
  tar -tf "$1" | grep -E '\.tar\.gz$' | head -n1
}

check_sbom() { # check_sbom <arch> <sbom> [config]
  local arch="$1" sbom="$2" config="${3:-$ROOT/apko/apko.yaml}"
  # Every requested package must have its resolved version in the SBOM.
  python3 - "$config" "$sbom" "$arch" <<'PY'
import json, re, sys

config, sbom, arch = sys.argv[1], sys.argv[2], sys.argv[3]
wanted = re.findall(r"^\s*- ([a-z][a-z0-9-]*)(?:[=@][^\s]+)?$", open(config).read().split("  packages:\n", 1)[1].split("\n\n", 1)[0], re.M)
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

image_inputs() { # image_inputs <arch>: everything the assembled image is made of
  local arch="$1" apk
  {
    printf 'arch=%s\nbuild_date=%s\n' "$arch" "$BUILD_DATE"
    sha256sum "$APKO" "$ROOT/apko/apko.yaml" "$ROOT/apko/apko.lock.$arch.json" \
      "$ROOT/apko/system.yaml" "$ROOT/apko/system.lock.$arch.json" \
      "$ROOT/scripts/mkinitramfs.sh" "$ROOT/scripts/build-image.sh"
    sha256sum "$BUILD/apk/$arch/$arch/APKINDEX.tar.gz"
    for apk in "$BUILD/apk/$arch/$arch"/elixos-*.apk; do sha256sum "$apk"; done
  } | sha256sum | cut -d' ' -f1
}

publish_host_artifacts() { # publish_host_artifacts <arch> <work>
  local arch="$1" work="$2"
  # x86_64 writes the paths the QEMU tests look for by default.
  if [ "$arch" = x86_64 ]; then
    cp "$work/bzImage" "$BUILD/bzImage"
    cp "$work/initramfs.cpio.gz" "$BUILD/initramfs.cpio.gz"
  fi
}


assemble_arch() { # assemble_arch <arch>: root filesystem, initramfs, kernel
  local arch="$1" work="$BUILD/$arch" digest second
  mkdir -p "$work"
  build_system "$arch"
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

  publish_host_artifacts "$arch" "$work"
}

build_arch() { # build_arch <arch>
  local arch="$1" work="$BUILD/$arch" inputs stamp
  mkdir -p "$work"

  # The packages first: each decides for itself whether its recipe's inputs
  # moved. The image key below must see the APKs this run would actually
  # install, so it cannot be checked before them.
  if [ "$arch" = aarch64 ]; then
    kernel_cross
    native_reuse
  fi
  build_packages "$arch"
  build_index "$arch"

  # Assembly (root filesystem, reproducibility, initramfs, squashfs) is the
  # other expensive half: skip it when the lockfiles, the APKs and the packers
  # are the ones that produced what is already there.
  inputs="$(image_inputs "$arch")"
  stamp="$work/.image.inputs"
  if [ -z "${FORCE:-}" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$inputs" ] &&
     [ -f "$work/initramfs.cpio.gz" ] && [ -f "$work/rootfs.digest" ]; then
    echo "build-image: [$arch] assembly inputs unchanged (cache hit)"
    publish_host_artifacts "$arch" "$work"
    return 0
  fi

  assemble_arch "$arch"
  printf '%s\n' "$inputs" > "$stamp"
}

stage

if [ "$#" -eq 0 ]; then
  # This machine's own image. The other architecture's packages are built
  # under emulation (ADR-041) and cost many minutes, so it is asked for
  # explicitly: `scripts/build-image.sh aarch64`, or `make images`.
  set -- "$HOST_ARCH"
fi

for arch in "$@"; do
  echo "build-image: == $arch =="
  build_arch "$arch"
done
echo "build-image: done"
