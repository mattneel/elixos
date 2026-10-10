#!/usr/bin/env bash
# Build generation 0, the factory image, into build/rootfs (overlaid at / by
# build-initramfs.sh). This is milestone M4's job; see docs/ROADMAP.md M4 and
# ADR-008 (dynamic musl ERTS built with zig cc).
#
# Expected result, roughly:
#   build/rootfs/lib/ld-musl-x86_64.so.1          musl's loader (also its libc.so)
#   build/rootfs/factory/erts-<vsn>/bin/erlexec   exec'd directly by the shim, no sh
#   build/rootfs/factory/lib/...                  OTP apps, elixir, iex, logger, elixos
#   build/rootfs/factory/releases/...             boot script + sys.config
set -euo pipefail

echo "TODO(M4): scripts/build-factory.sh is not written yet (docs/ROADMAP.md M4)" >&2
exit 1
