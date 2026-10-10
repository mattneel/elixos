#!/usr/bin/env bash
# Build generation 0, the factory, into build/rootfs (overlaid at / by
# build-initramfs.sh). See docs/ROADMAP.md M4 and ADR-008.
#
#   build/rootfs/lib/ld-musl-x86_64.so.1          musl's loader, also its libc
#   build/rootfs/lib/libncurses.so.6              the tty driver's terminal handling
#   build/rootfs/lib/libstdc++.so.6, libgcc_s.so.1  the JIT's C++ runtime
#   build/rootfs/lib/libcrypto.so.3, libssl.so.3  :crypto, :ssl and, later, ssh
#   build/rootfs/factory/erts-<vsn>/bin/erlexec   exec'd directly by the shim
#   build/rootfs/factory/erts -> erts-<vsn>       the stable name the shim uses
#   build/rootfs/factory/lib/                     OTP apps, Elixir, Elixos
#   build/rootfs/factory/releases/<vsn>/          start.boot + sys.config
#   build/rootfs/factory/releases/current -> <vsn>
#
# Everything below is cached under build/toolchain, so re-running is cheap;
# delete build/toolchain to rebuild the toolchain from source.
#
# Toolchain note (docs/notes/factory-build.md): the ERTS is built with the
# musl.cc gcc for x86_64-linux-musl rather than zig cc. Zig's linker localizes
# the string and math symbols shared libraries need at run time, and its
# bundled libc is not a usable dynamic loader; the musl cross toolchain has
# neither problem. The shim itself is still built by zig (ADR-003).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
TC="$BUILD/toolchain"
DL="$BUILD/dl"
SYS="$TC/sysroot"
CROSS="$TC/x86_64-linux-musl-cross"
OTP_INSTALL="$CROSS/otp-install"
OTP_ROOT="$OTP_INSTALL/usr/local/lib/erlang"
ROOTFS="$BUILD/rootfs"
JOBS="$(nproc)"

# Every download is pinned and checked, the way the kernel is (ADR-001): the
# factory must not change because an upstream tarball did.
#
# musl.cc rebuilds its toolchain file in place (they are dated snapshots), so
# this hash is the one published when the pin was taken (2026-10-09, gcc
# 11.2.1). If it stops matching, read their release notes, update the hash and
# this comment, and re-run — never build a factory from an unchecked tarball.
MUSL_CROSS_URL=https://musl.cc/x86_64-linux-musl-cross.tgz
MUSL_CROSS_SHA256=c5d410d9f82a4f24c549fe5d24f988f85b2679b452413a9f7e5f7b956f2fe7ea
OPENSSL_VERSION=3.5.9
OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
NCURSES_VERSION=6.5
NCURSES_SHA256=136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6
OTP_VERSION=29.1.1
OTP_SHA256=054e0143e39c780e091107fc9b345792a9c1a55f6bac1eca1c1101510fc06bf6

mkdir -p "$TC" "$DL"

step() { printf '\n== %s\n' "$1"; }
fetch() { # fetch <url> <file> <sha256>
  local url="$1" file="$2" expected="$3"

  if [ ! -f "$DL/$file" ]; then
    echo "fetching $file"
    curl -fL --retry 3 -o "$DL/$file.part" "$url"
    mv "$DL/$file.part" "$DL/$file"
  fi

  if ! echo "$expected  $DL/$file" | sha256sum -c - >/dev/null 2>&1; then
    cat >&2 <<EOF
fetch: $file does not match its pinned sha256.

  expected $expected
  got      $(sha256sum "$DL/$file" | cut -d' ' -f1)

  For a source tarball this means the download is damaged or upstream replaced
  the file: delete $DL/$file and re-run. musl.cc rebuilds its toolchain in
  place, so a changed hash there is expected occasionally - read their release
  notes, then update the pin and its comment in this script.
EOF
    exit 1
  fi
}

export PATH="$CROSS/bin:$PATH"
export CC=x86_64-linux-musl-gcc CXX=x86_64-linux-musl-g++ AR=x86_64-linux-musl-ar RANLIB=x86_64-linux-musl-ranlib
# Where the target's libraries live when a target binary runs on this host.
# Never export this globally: libstdc++.so.6 and libgcc_s.so.1 have the same
# sonames as the host's glibc versions, and the host's own tools (mix, erl)
# would pick the musl ones up and fail.
TARGET_LIBS="$SYS/usr/lib:$CROSS/x86_64-linux-musl/lib"

# --- 0. the host's musl runtime ---------------------------------------------
# The toolchain's programs (and OTP's own build steps) run *target* binaries on
# this host, and their ELF interpreter is the absolute /lib/ld-musl-x86_64.so.1:
# a glibc host does not have it, and LD_LIBRARY_PATH cannot redirect it.
if [ ! -e /lib/ld-musl-x86_64.so.1 ]; then
  cat >&2 <<EOF
build-factory: no musl loader at /lib/ld-musl-x86_64.so.1.

  The toolchain runs target binaries on this host (configure probes, and the
  ERTS itself while OTP builds). Their interpreter path is absolute, so install
  the loader once, from the toolchain that ships it:

      sudo cp "$CROSS/x86_64-linux-musl/lib/libc.so" /lib/ld-musl-x86_64.so.1

  \`make check-tools\` reports this too. See docs/notes/factory-build.md.
EOF
  exit 1
fi

# --- 1. the musl cross toolchain ---------------------------------------------
step "musl cross toolchain"
if [ ! -x "$CROSS/bin/x86_64-linux-musl-gcc" ]; then
  fetch "$MUSL_CROSS_URL" musl-cross.tgz "$MUSL_CROSS_SHA256"
  tar -C "$TC" -xzf "$DL/musl-cross.tgz"
fi
echo "using $($CROSS/bin/x86_64-linux-musl-gcc --version | head -n1)"

# --- 2. OpenSSL and ncurses for the target -----------------------------------
step "OpenSSL $OPENSSL_VERSION (target)"
if [ ! -f "$SYS/usr/lib/libcrypto.so.3" ]; then
  fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" \
    "openssl-$OPENSSL_VERSION.tar.gz" "$OPENSSL_SHA256"
  tar -C "$TC" -xzf "$DL/openssl-$OPENSSL_VERSION.tar.gz"
  (
    cd "$TC/openssl-$OPENSSL_VERSION"
    ./Configure linux-x86_64 shared no-tests --prefix=/usr --libdir=/lib --openssldir=/etc/ssl
    make -j"$JOBS"
    make install_sw DESTDIR="$SYS"
  )
  # The shim and the release expect one prefix; OpenSSL's libdir is /lib. On a
  # clean build usr/lib does not exist yet (ncurses creates it later), so the
  # destination comes first.
  mkdir -p "$SYS/usr/lib"
  ( cd "$SYS" && for l in libcrypto.so.3 libcrypto.so libcrypto.a libssl.so.3 libssl.so libssl.a; do
      ln -sf "../../lib/$l" "usr/lib/$l"; done )
fi
echo "ok: $SYS/usr/lib/libcrypto.so.3"

step "ncurses $NCURSES_VERSION (target)"
if [ ! -f "$SYS/usr/lib/libncurses.so.6" ]; then
  fetch "https://invisible-island.net/archives/ncurses/ncurses-$NCURSES_VERSION.tar.gz" \
    "ncurses-$NCURSES_VERSION.tar.gz" "$NCURSES_SHA256"
  rm -rf "$TC/ncurses-$NCURSES_VERSION"
  mkdir -p "$TC/ncurses-$NCURSES_VERSION"
  tar -C "$TC/ncurses-$NCURSES_VERSION" -xzf "$DL/ncurses-$NCURSES_VERSION.tar.gz" --strip-components=1
  (
    cd "$TC/ncurses-$NCURSES_VERSION"
    ./configure --prefix=/usr --with-shared --without-normal --without-debug \
      --without-ada --without-manpages --without-tests --disable-widec \
      --with-default-terminfo-dir=/usr/share/terminfo \
      --with-terminfo-dirs=/usr/share/terminfo --disable-stripping
    # ncurses hands -stats to the linker; neither lld nor ld accept it.
    find . -name Makefile -exec sed -i 's/,-stats,-lc//' {} +
    make -j"$JOBS"
    LD_LIBRARY_PATH="$PWD/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" make install DESTDIR="$SYS"
  )
fi
echo "ok: $SYS/usr/lib/libncurses.so.6"

# --- 3. OTP, ERTS included ---------------------------------------------------
step "OTP $OTP_VERSION (target)"
if [ ! -x "$OTP_ROOT"/erts-*/bin/erlexec ]; then
  fetch "https://github.com/erlang/otp/releases/download/OTP-$OTP_VERSION/otp_src_$OTP_VERSION.tar.gz" \
    "otp_src_$OTP_VERSION.tar.gz" "$OTP_SHA256"
  rm -rf "$TC/otp_src_$OTP_VERSION"
  tar -C "$TC" -xzf "$DL/otp_src_$OTP_VERSION.tar.gz"
  (
    cd "$TC/otp_src_$OTP_VERSION"
    export LD_LIBRARY_PATH="$TARGET_LIBS"
    # A native-looking build: the target binaries run on this host through the
    # musl loader the toolchain ships, so configure tests tell the truth.
    ./configure --enable-dynamic-ssl-lib --with-ssl="$SYS/usr" \
      --without-javac --without-wx --without-odbc --without-observer \
      --without-debugger --without-et --without-megaco \
      CPPFLAGS="-I$SYS/usr/include" LDFLAGS="-L$SYS/usr/lib"
    make -j"$JOBS"
    make install DESTDIR="$OTP_INSTALL"
  )
fi
echo "ok: $OTP_ROOT ($(ls "$OTP_ROOT" | grep '^erts-' | head -n1))"

# --- 4. the release, then the rootfs ----------------------------------------
step "the Elixos release"
ERTS_VERSION="$(ls "$OTP_ROOT" | grep '^erts-' | head -n1)"
RELEASE_VSN="$(sed -n 's/^  @version "\(.*\)"$/\1/p' "$ROOT/os/mix.exs")"
(
  cd "$ROOT/os"
  # Mix keeps an existing erts-<version> directory when it copies the ERTS
  # (same version, different libc: a host release would survive into a factory
  # one), so the assembly directory starts empty.
  rm -rf "$BUILD/rel"
  # Mix.Release takes the *erts* directory, and finds the OTP apps next to it.
  MIX_ENV=prod ELIXOS_ERTS="$OTP_ROOT/$ERTS_VERSION" mix release --overwrite --path "$BUILD/rel"
)

# M11: the box builds Mix projects itself, and `mix release` leaves the mix
# application out. Copying it in beside Elixir makes it loadable from lib/, so
# a child ERTS can run Mix.CLI directly - no mix script, no shell (ADR-012).
ELIXIR_LIB="$(elixir -e 'IO.puts(:code.lib_dir(:elixir))' | tail -n1)"
cp -a "$(dirname "$ELIXIR_LIB")/mix" "$BUILD/rel/lib/"

# M11: a NIF that includes erl_nif.h has to find it on the box, so the ERTS
# headers the OTP build installed travel with the release.
mkdir -p "$BUILD/rel/erts-${ERTS_VERSION#erts-}/usr/include"
cp -a "$OTP_ROOT/usr/include/." "$BUILD/rel/erts-${ERTS_VERSION#erts-}/usr/include/"

rm -rf "$ROOTFS"
mkdir -p "$ROOTFS/factory" "$ROOTFS/lib"

# The loader and the shared libraries the ERTS needs at run time.
cp "$CROSS/x86_64-linux-musl/lib/libc.so" "$ROOTFS/lib/ld-musl-x86_64.so.1"
for lib in libncurses.so.6 libstdc++.so.6 libgcc_s.so.1 libcrypto.so.3 libssl.so.3; do
  src="$(find "$SYS" "$CROSS/x86_64-linux-musl/lib" -name "$lib" -print -quit)"
  [ -n "$src" ] || { echo "factory: cannot find $lib" >&2; exit 1; }
  cp "$src" "$ROOTFS/lib/$lib"
done

# The factory itself: the release, with stable names for the two directories
# that carry a version (the shim must not guess them).
cp -a "$BUILD/rel/." "$ROOTFS/factory/"
ln -sfn "$ERTS_VERSION" "$ROOTFS/factory/erts"
ln -sfn "$RELEASE_VSN" "$ROOTFS/factory/releases/current"

# No shells, no release scripts: the shim execs erlexec itself (ADR-012).
rm -rf "$ROOTFS/factory/bin"

# The official Hex repository: the factory ships its public key and the
# preconfigured entry, so a box trusts it without anyone adding a repository
# first (ADR-019). `/priv/hex/` is the box's own copy and wins once it exists.
mkdir -p "$ROOTFS/factory/hex/keys"
cp "$ROOT/hex/keys/elixos.pub" "$ROOTFS/factory/hex/keys/elixos.pub"
{
  echo "# Trusted Hex repositories (PROTOCOL.md §8). This is the whole trust"
  echo "# decision: a repository is trusted exactly when it appears here."
  echo "["
  echo "  elixos: ["
  echo "    url: \"https://mattneel.github.io/elixos\","
  echo "    key: \"\"\""
  cat "$ROOT/hex/keys/elixos.pub"
  echo "\"\"\""
  echo "  ]"
  echo "]"
} > "$ROOTFS/factory/hex/repos.exs"

echo
echo "factory: $ROOTFS"
du -sh "$ROOTFS/factory" "$ROOTFS/lib" | sed 's/^/  /'
