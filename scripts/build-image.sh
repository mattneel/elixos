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
#   riscv64: build/riscv64/Image, build/riscv64/initramfs.cpio.gz
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
# Optional Eval builds never reuse the default factory/image output directory.
EVAL_PROFILE="${ELIXOS_EVAL_PROFILE:-0}"
ROOTFS_CONFIG="$ROOT/apko/apko.yaml"
LOCK_ROOT="$ROOT/apko"
case "$EVAL_PROFILE" in
  0) ;;
  1)
    : "${ELIXOS_BUILD:?Eval profile requires a separate explicit ELIXOS_BUILD directory}"
    [ "$(readlink -m "$BUILD")" != "$(readlink -m "$ROOT/build")" ] || {
      echo "build-image: Eval profile refuses the default build directory" >&2; exit 1;
    }
    ROOTFS_CONFIG="$ROOT/apko/apko-eval.yaml"
    LOCK_ROOT="$BUILD/locks"
    mkdir -p "$LOCK_ROOT"
    ;;
  *) echo "build-image: ELIXOS_EVAL_PROFILE must be 0 or 1" >&2; exit 1 ;;
esac
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
  cp -r "$ROOT/build.zig" "$ROOT/build.zig.zon" "$ROOT/.zig-version" "$ROOT/.tool-versions" "$ROOT/MILESTONE" \
        "$ROOT/shim" "$ROOT/spec" "$ROOT/kernel" "$ROOT/scripts" "$ROOT/hex" "$ROOT/toolchain" \
        "$SRC/"
  cp -r "$ROOT/os/mix.exs" "$ROOT/os/mix.lock" "$ROOT/os/lib" "$ROOT/os/config" "$ROOT/os/priv" "$ROOT/os/test" "$SRC/os/"
  # Canonical native coding packages are human-pinned source inputs, never
  # host BEAM or the example's reduced host-test OS application (ADR-084).
  local coding_source="${ELIXOS_OH_MY_JIDO_SOURCE:-$ROOT/../oh_my_jido}"
  local coding_pin="${ELIXOS_CODING_SHA256:?set the reviewed pin from scripts/stage-coding.exs pin SOURCE}"
  local operation=stage
  [ "$EVAL_PROFILE" = 0 ] || operation=stage-eval
  elixir "$ROOT/scripts/stage-coding.exs" "$operation" "$coding_source" "$SRC/coding" "$coding_pin"
  cp -r "$ROOT/melange" "$SRC/"
}

package_inputs() { # package_inputs <arch> <package>: hash of everything the recipe reads
  local arch="$1" pkg="$2" path
  local -a paths
  case "$pkg" in
    kernel) paths=(kernel melange/kernel.yaml prebuilt/kernel) ;;
    # The aarch64 ERTS comes from the cross build (ADR-060), so the tree that
    # build staged is one of this package's inputs. The x86_64 build must not
    # see it: it is another architecture's binaries.
    otp)
      if foreign_arch "$arch"; then
        paths=(.tool-versions melange/otp.yaml prebuilt/otp prebuilt/otp.links)
      else
        paths=(.tool-versions melange/otp.yaml)
      fi
      ;;
    elixir) paths=(.tool-versions melange/elixir.yaml prebuilt/elixir prebuilt/elixir.links) ;;
    factory|factory-eval)
      paths=(os coding spec MILESTONE hex .tool-versions melange/factory.yaml melange/factory-eval.yaml melange/coding-eval-python.yaml scripts/stage-coding.exs scripts/factory-coding-receipt.exs scripts/package-factory.sh scripts/build-coding-eval.exs scripts/coding-eval-native.py scripts/coding-eval scripts/build-image.sh)
      # The aarch64 factory is the tree the host cross build staged (ADR-094).
      foreign_arch "$arch" && paths+=(prebuilt/factory prebuilt/factory.links)
      ;;
    coding-eval-python) paths=(melange/coding-eval-python.yaml scripts/coding-eval-native.py scripts/coding-eval) ;;
    shim) paths=(shim spec .zig-version build.zig build.zig.zon melange/shim.yaml) ;;
    browser) paths=(melange/browser.yaml) ;;
    gui-renderer)
      paths=(melange/gui-renderer.yaml)
      foreign_arch "$arch" && paths+=(prebuilt/gui-renderer prebuilt/gui-renderer.links)
      ;;
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

# Architectures whose packages are compiled on the build host and staged
# (ADR-060, ADR-094); their own melange environments only install the result.
foreign_arch() { [ "$1" = aarch64 ] || [ "$1" = riscv64 ]; }

# The service image's configuration. Lightpanda publishes no riscv64 build, so
# riscv64 uses a copy of system.yaml without the browser (ADR-097), checked
# here to differ by exactly that package and nothing else.
system_config() { # system_config <arch>
  if [ "$1" = riscv64 ]; then
    local strip='^    - elixos-browser$|^  - (x86_64|aarch64|riscv64)$|^ *#'
    if ! diff <(grep -Ev "$strip" "$ROOT/apko/system.yaml") \
              <(grep -Ev "$strip" "$ROOT/apko/system-riscv64.yaml") >/dev/null; then
      echo "build-image: apko/system-riscv64.yaml must equal system.yaml without elixos-browser" >&2
      return 1
    fi
    echo "$ROOT/apko/system-riscv64.yaml"
  else
    echo "$ROOT/apko/system.yaml"
  fi
}

cross_inputs() { # cross_inputs <arch> <name> <recipe> <paths...>: everything that build reads
  local arch="$1" name="$2" recipe="$3" path
  shift 3
  {
    printf 'target=%s\npackage=%s\n' "$arch" "$name"
    sha256sum "$MELANGE" "$KEY.pub" "$recipe"
    (
      cd "$SRC"
      for path in "$@"; do
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

# A native cross build (ADR-060): a melange pipeline runs inside the target
# rootfs, so building for arm64 there means emulating every compiler process.
# These recipes run in this machine's own x86_64 environment instead and emit
# the target's artifacts, which the target's package installs. Each keeps its
# APK in its own repository, keyed on its inputs, so nothing is rebuilt that
# has not changed.
cross_build() { # cross_build <arch> <name> <recipe> <paths...>
  local arch="$1" name="$2" recipe="$3"
  shift 3
  # One repository per target and cross build: clearing a shared one to
  # rebuild, say, OTP would throw away the kernel's cached APK, and two targets
  # must never overwrite each other's.
  local repo="$BUILD/apk-cross/$arch/$name" stamp="$BUILD/apk-cross/$arch/$name/.inputs" inputs apk
  local cached_inputs="" cached_sha="" cached_apk=""
  inputs="$(cross_inputs "$arch" "$name" "$recipe" "$@")"
  if [ -f "$stamp" ]; then
    read -r cached_inputs cached_sha cached_apk < "$stamp" || true
  fi

  apk="$repo/x86_64/$cached_apk"
  if [ -n "${FORCE:-}" ] || [ "$inputs" != "$cached_inputs" ] || [ ! -f "$apk" ] ||
     [ "$(sha256sum "$apk" 2>/dev/null | cut -d' ' -f1)" != "$cached_sha" ]; then
    echo "build-image: melange $(basename "$recipe") (native cross, $arch)"
    rm -rf "$repo/x86_64" "$stamp"
    mkdir -p "$repo/x86_64"
    # The shared compiler cache and the host-arch variable: one pinned Zig SDK
    # for the shim and the kernel, outside melange's per-build workspace.
    mkdir -p "$ZIG_CACHE"
    printf 'ELIXOS_ZIG_HOST_ARCH=%s\nELIXOS_CROSS_ARCH=%s\n' "$HOST_ARCH" "$arch" > "$ZIG_CACHE/cross-$arch.env"
    "$MELANGE" build "$recipe" --arch x86_64 --source-dir "$SRC" \
      --out-dir "$repo" --signing-key "$KEY" -r "$BUILD/apk/$HOST_ARCH" -k "$KEY.pub" \
      --cache-dir "$ZIG_CACHE" --env-file "$ZIG_CACHE/cross-$arch.env" >/dev/null
    apk="$(ls "$repo/x86_64/elixos-$name-cross"-*.apk | head -n1)"
    [ -f "$apk" ] || { echo "build-image: no elixos-$name-cross APK was produced" >&2; return 1; }
    printf '%s %s %s\n' "$inputs" "$(sha256sum "$apk" | cut -d' ' -f1)" "$(basename "$apk")" > "$stamp"
  else
    echo "build-image: elixos-$name-cross inputs unchanged (cache hit, $arch)"
  fi

  stage_prebuilt "$name" "$apk"
}

# Adopt a native build: unpack the APK it produced into the staging area the
# architecture's package installs from. melange APKs are tar streams a plain
# tar reads (mkdisk.sh reads one the same way).
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
  # links): record them here so the package recreates them itself.
  ( cd "$tmp" && find . -type l -printf '%P\t%l\n' ) | LC_ALL=C sort > "$dir.links.tmp"

  rm -rf "$dir"
  mv "$tmp" "$dir"
  mv "$dir.links.tmp" "$dir.links"
  echo "build-image: staged the native $name build ($(wc -l < "$dir.links") symlink(s) recorded)"
}

# Elixir itself is architecture-neutral bytecode and symlinks into target OTP.
# The factory is not: Emerge's loader is compiled with target-specific options
# and points at that target's NIF. Never transplant the host factory tree.
native_reuse() {
  local pkg pname repo="$BUILD/apk/x86_64" apk
  for pkg in elixir; do
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
  # build against it), the kernel and the shim independent, the browser a
  # download-and-repack, the toolchain last (it needs only a compiler).
  local -a packages=(kernel otp elixir gui-renderer)
  if [ "$EVAL_PROFILE" = 1 ]; then
    packages+=(coding-eval-python factory-eval)
  else
    packages+=(factory)
  fi
  packages+=(shim)
  # Lightpanda ships x86_64 and aarch64 only (ADR-097).
  [ "$arch" = riscv64 ] || packages+=(browser)
  packages+=(toolchain)
  for pkg in "${packages[@]}"; do
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
    if [ "$pkg" = shim ] || [ "$pkg" = toolchain ]; then
      # The shim and the toolchain's cc bridge build with the build host's
      # Zig (ADR-094); its caches live outside melange's per-build workspace
      # (see docs/notes).
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
  "$APKO" lock "$ROOTFS_CONFIG" --arch "$arch" \
    -r "$BUILD/apk/$arch" -k "$KEY.pub" \
    --cache-dir "$MIRROR" --output "$LOCK_ROOT/apko.lock.$arch.json"
}

assemble() { # assemble <arch> <output tar>
  local arch="$1" out="$2"
  "$APKO" build --lockfile "$LOCK_ROOT/apko.lock.$arch.json" --arch "$arch" \
    -r "$BUILD/apk/$arch" -k "$KEY.pub" \
    --build-date "$BUILD_DATE" --sbom-path "$(dirname "$out")" --cache-dir "$MIRROR" \
    "$ROOTFS_CONFIG" "elixos:$arch" "$out"
}

system_lock() { # system_lock <arch>: retain committed pins until config changes
  local arch="$1" config lockfile="$LOCK_ROOT/system.lock.$1.json"
  config="$(system_config "$arch")"
  if [ "$EVAL_PROFILE" = 1 ]; then
    "$APKO" lock "$config" --arch "$arch" --cache-dir "$MIRROR" \
      -r "$BUILD/apk/$arch" -k "$KEY.pub" --output "$lockfile"
    return
  fi
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
    "$APKO" lock "$config" --arch "$arch" --cache-dir "$MIRROR" \
      -r "$BUILD/apk/$arch" -k "$KEY.pub" --output "$lockfile"
  fi
}

assemble_system() { # assemble_system <arch> <work directory>
  local arch="$1" work="$2" epoch config
  epoch="$(date -u -d "$BUILD_DATE" +%s)"
  config="$(system_config "$arch")"
  mkdir -p "$work"
  "$APKO" build --lockfile "$LOCK_ROOT/system.lock.$arch.json" --arch "$arch" \
    --build-date "$BUILD_DATE" --sbom-path "$work" --cache-dir "$MIRROR" \
    -r "$BUILD/apk/$arch" -k "$KEY.pub" \
    "$config" "elixos-system:$arch" "$work/rootfs.tar"
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
  check_sbom "$arch" "$work/system/sbom-$arch.spdx.json" "$(system_config "$arch")"
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
  local arch="$1" sbom="$2" config="${3:-$ROOTFS_CONFIG}"
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
    sha256sum "$APKO" "$ROOTFS_CONFIG" "$LOCK_ROOT/apko.lock.$arch.json" \
      "$(system_config "$arch")" "$LOCK_ROOT/system.lock.$arch.json" \
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
    aarch64|riscv64) tar -xzf "$kernel_apk" -O boot/Image > "$work/Image" ;;
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
  if foreign_arch "$arch"; then
    # Keyed on what the recipes read, not on whole directories: editing an
    # unrelated script must not rebuild a kernel.
    cross_build "$arch" kernel "$ROOT/melange/kernel-cross.yaml" kernel scripts/check-kernel-config.sh
    # The ERTS is the one package that is pure compiled C, so a cross build
    # needs a real cross toolchain - and OTP has a native cross mode for it
    # (ADR-060). This runs on the build machine, in this architecture's own
    # environment; the target's elixos-otp package installs what it produces.
    cross_build "$arch" otp "$ROOT/melange/otp-cross.yaml" .tool-versions melange/otp.yaml
    native_reuse
    # Nothing compiles under emulation (ADR-094): the renderer NIF (Rust and
    # Skia, cross toolchain plus the target's sysroot) and the factory (target-
    # configured bytecode, compiled by the native BEAM) are built here too.
    cross_build "$arch" gui-renderer "$ROOT/melange/gui-renderer-cross.yaml" melange/gui-renderer.yaml
    if [ "$EVAL_PROFILE" = 1 ]; then
      echo "build-image: the $arch eval profile has no cross build yet; refusing an emulated compile" >&2
      return 1
    fi
    cross_build "$arch" factory "$ROOT/melange/factory-cross.yaml" os coding spec MILESTONE hex .tool-versions \
      melange/factory.yaml scripts/stage-coding.exs scripts/factory-coding-receipt.exs scripts/package-factory.sh
  fi
  build_packages "$arch"
  build_index "$arch"
  if [ "$EVAL_PROFILE" = 1 ]; then
    # These locks do not exist in a fresh optional output directory, and their
    # local APK identities must be resolved before the assembly cache key.
    lock "$arch"
    system_lock "$arch"
  fi

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
  # This machine's own image. The other architecture's takes several minutes
  # even with the native cross builds (kernel, ERTS) and the reused trees
  # (Elixir only), so it is asked for explicitly:
  # `scripts/build-image.sh aarch64`, or `make images`.
  set -- "$HOST_ARCH"
fi

for arch in "$@"; do
  echo "build-image: == $arch =="
  build_arch "$arch"
done
echo "build-image: done"
