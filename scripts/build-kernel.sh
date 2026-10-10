#!/usr/bin/env bash
# Build the pinned, unmodified mainline kernel (ADR-001).
#
# We only ever *configure* the kernel: x86_64_defconfig + kvm_guest.config + our
# fragment. Nothing in this script (or anywhere in the repo) may patch the source.
#
# Outputs:
#   build/bzImage                      the kernel QEMU boots and UEFI runs
#   build/linux-<ver>/usr/gen_init_cpio  used by build-initramfs.sh (no root needed)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../kernel/VERSION
. "$ROOT/kernel/VERSION"

BUILD="${ELIXOS_BUILD:-$ROOT/build}"
DL="$BUILD/dl"
SRC="$BUILD/linux-$KERNEL_VERSION"
TARBALL="linux-$KERNEL_VERSION.tar.xz"
MAJOR="${KERNEL_VERSION%%.*}"
URL="https://cdn.kernel.org/pub/linux/kernel/v$MAJOR.x/$TARBALL"
JOBS="${JOBS:-$(nproc)}"

mkdir -p "$DL"

if [ ! -f "$DL/$TARBALL" ]; then
  echo "kernel: downloading $URL"
  curl -fL --retry 3 -o "$DL/$TARBALL.part" "$URL"
  mv "$DL/$TARBALL.part" "$DL/$TARBALL"
fi
echo "$KERNEL_SHA256  $DL/$TARBALL" | sha256sum -c -

if [ ! -d "$SRC" ]; then
  echo "kernel: extracting $TARBALL"
  tar -C "$BUILD" -xJf "$DL/$TARBALL"
fi

echo "kernel: configuring (x86_64_defconfig + kvm_guest.config + both fragments)"
# kbuild treats a non-empty $LLVM as "build with clang" and rejects anything but
# a path prefix, `-suffix` or 1. Hosts that source emsdk (mise does) export LLVM
# as a bin directory, which is none of those. We build with gcc: drop it.
unset LLVM
# Since M16 the fragment is common + one per architecture (ADR-041); this
# script builds x86_64 (the melange kernel package builds each arch), and the
# guard covers both files so the common half stays honest.
FRAGMENTS=("$ROOT/kernel/elixos.config" "$ROOT/kernel/config.x86_64")
make -C "$SRC" -s x86_64_defconfig
make -C "$SRC" -s kvm_guest.config
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$SRC" "$SRC/.config" "${FRAGMENTS[@]}" >/dev/null
make -C "$SRC" -s olddefconfig
"$ROOT/scripts/check-kernel-config.sh" "$SRC/.config" "${FRAGMENTS[@]}"

echo "kernel: building bzImage with $JOBS jobs"
make -C "$SRC" -s -j"$JOBS" bzImage

test -x "$SRC/usr/gen_init_cpio" || { echo "kernel: usr/gen_init_cpio was not built" >&2; exit 1; }
cp "$SRC/arch/x86/boot/bzImage" "$BUILD/bzImage"
echo "kernel: $BUILD/bzImage ($KERNEL_VERSION)"
