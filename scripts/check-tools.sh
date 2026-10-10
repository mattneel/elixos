#!/usr/bin/env bash
# Report which host tools are present. Exit 1 if a required one is missing.
# Target host: WSL2 Ubuntu 24.04 (any x86_64 Linux works).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
status=0

need() { # need <cmd> <apt package> <why>
  if command -v "$1" >/dev/null 2>&1; then
    printf '  ok       %-20s %s\n' "$1" "$3"
  else
    printf '  MISSING  %-20s %s  (apt install %s)\n' "$1" "$3" "$2"
    status=1
  fi
}

echo "toolchains (versions pinned in .zig-version and .tool-versions):"
need zig "-" "shim; also the C toolchain for ERTS (ADR-003, ADR-008)"
need erl "-" "Erlang/OTP, host side"
need elixir "-" "Elixir, host side"
need mix "-" "Elixir build tool"

echo "kernel build:"
for t in "make:make" "gcc:gcc" "flex:flex" "bison:bison" "bc:bc" "perl:perl" "xz:xz-utils" "cpio:cpio"; do
  need "${t%%:*}" "${t##*:}" "mainline kernel build"
done
if ! dpkg -s libelf-dev >/dev/null 2>&1 && ! [ -f /usr/include/libelf.h ]; then
  echo "  MISSING  libelf headers         (apt install libelf-dev)"; status=1
fi
if ! [ -f /usr/include/openssl/ssl.h ]; then
  echo "  MISSING  openssl headers        (apt install libssl-dev)"; status=1
fi

echo "images and tests:"
need qemu-system-x86_64 qemu-system-x86 "boots every QEMU test"
need mkfs.ext4 e2fsprogs "persistent disk image"
need debugfs e2fsprogs "tests read/write the disk image without root"
need mformat mtools "ESP image (M13)"
need ssh-keygen openssh-client "SSH test keys (M12)"
if [ ! -e /lib/ld-musl-x86_64.so.1 ]; then
  echo "  MISSING  musl loader           the factory build runs target binaries on this host"
  echo "                                   install: sudo cp build/toolchain/x86_64-linux-musl-cross/x86_64-linux-musl/lib/libc.so /lib/ld-musl-x86_64.so.1"
  status=1
fi

echo "versions:"
if command -v zig >/dev/null 2>&1; then
  echo "  zig $(zig version) (pinned: $(head -n1 "$ROOT/.zig-version"))"
fi
if command -v erl >/dev/null 2>&1; then
  echo "  otp $(erl -noshell -eval 'io:put_chars(erlang:system_info(otp_release)), halt().')"
fi
if command -v elixir >/dev/null 2>&1; then
  echo "  $(elixir --version 2>/dev/null | tail -n1)"
fi
if [ -e /dev/kvm ]; then
  echo "  /dev/kvm present: QEMU tests use KVM"
else
  echo "  /dev/kvm absent: QEMU tests fall back to TCG (slow); set ELIXOS_QEMU_SLOWDOWN=4"
fi

exit "$status"
