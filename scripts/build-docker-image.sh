#!/usr/bin/env bash
# Package the pinned native userland; compile only the current container shim.
# Never run the machine image build or use its zig-out/bin/init.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
PROFILE=sdk
ARCH="$(uname -m)"
case "$ARCH" in arm64) ARCH=aarch64 ;; esac
IMAGE=

usage() {
    cat <<'USAGE'
usage: scripts/build-docker-image.sh [--runtime] [--arch x86_64|aarch64] [image:tag]

Build a native OCI image of the existing Elixos factory and services.
Default: elixos:sdk (includes the immutable /toolchain).
--runtime: elixos:runtime (the same OS, without the compiler toolchain).
--arch: select that target's artifacts (default: the build host architecture).
Cross-arch packaging compiles the shim but does not execute or verify the target.

Prerequisites:
  Docker CLI, a running daemon, and buildx/BuildKit; Python 3.10+; pinned Zig.
  ELIXOS_BUILD/<arch>/oci/{manifest.json,sha256:*,<digest>.tar.gz}
  ELIXOS_BUILD/<arch>/rootfs.digest
  ELIXOS_BUILD/<arch>/system/oci/{manifest.json,sha256:*,<digest>.tar.gz}
  SDK only: ELIXOS_BUILD/apk/<arch>/<arch>/elixos-toolchain-0.0.0-r0.apk
These are outputs of scripts/build-image.sh <arch>. This helper never rebuilds
kernel, OTP, NIFs, factory or toolchain artifacts, and never reads a disk/session.
It always compiles the current /init with -Dcontainer=true -Dtest-hooks=false.

Environment:
  ELIXOS_BUILD         artifact directory (default: repository build/)
  ELIXOS_DOCKER_IMAGE  default tag override
  ZIG                 pinned Zig executable (default: zig on PATH)
  BUILD_DATE          reproducible timestamp (default: 2026-01-01T00:00:00Z)

Run headless with ordinary container networking and an optional persistent volume:
  docker run --rm -v elixos-state:/priv elixos:sdk
Opt into IEx with a tty:
  docker run --rm -it -e ELIXOS_CONSOLE=1 -v elixos-state:/priv elixos:sdk
Do not override USER: /init starts the BEAM as uid/gid 1000 and PostgreSQL as 70.
No privileged mode, host namespace, /dev/kvm, kernel or boot image is required.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --runtime) PROFILE=runtime; shift ;;
        --arch)
            if [ "$#" -lt 2 ]; then
                echo "build-docker: --arch requires x86_64 or aarch64" >&2
                exit 1
            fi
            ARCH="$2"
            shift 2
            ;;
        --)
            shift
            if [ "$#" -ne 1 ] || [ -n "$IMAGE" ]; then
                usage >&2
                exit 1
            fi
            IMAGE="$1"
            shift
            ;;
        -*) echo "build-docker: unknown option $1; use --help" >&2; exit 1 ;;
        *)
            if [ -n "$IMAGE" ]; then
                echo "build-docker: expected at most one image tag; use --help" >&2
                exit 1
            fi
            IMAGE="$1"
            shift
            ;;
    esac
done
case "$ARCH" in
    x86_64) PLATFORM=linux/amd64 ;;
    aarch64) PLATFORM=linux/arm64 ;;
    *) echo "build-docker: unsupported architecture $ARCH; use --arch x86_64 or --arch aarch64" >&2; exit 1 ;;
esac
IMAGE="${IMAGE:-${ELIXOS_DOCKER_IMAGE:-elixos:$PROFILE}}"
BUILD_DATE="${BUILD_DATE:-2026-01-01T00:00:00Z}"

for tool in python3 docker; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "build-docker: missing $tool; see --help for prerequisites" >&2
        exit 1
    fi
done
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
    echo "build-docker: Python 3.10 or newer is required" >&2
    exit 1
fi
if ! docker buildx version >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "build-docker: a running Docker daemon and buildx/BuildKit are required" >&2
    exit 1
fi
ZIG="${ZIG:-zig}"
if ! command -v "$ZIG" >/dev/null 2>&1; then
    echo "build-docker: no Zig compiler; run scripts/install-zig.sh and set PATH or ZIG" >&2
    exit 1
fi
IFS= read -r PINNED_ZIG < "$ROOT/.zig-version"
if [ "$("$ZIG" version)" != "$PINNED_ZIG" ]; then
    echo "build-docker: Zig $PINNED_ZIG is required; run scripts/install-zig.sh and set PATH or ZIG" >&2
    exit 1
fi

# This context contains only repacked public package assets. Neither the repo,
# its build directory, signing keys, credentials, nor mutable /priv is sent.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/elixos-docker.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
CONTEXT="$WORK/context"
mkdir "$CONTEXT"

# Validate exact existing target inputs before compiling even the small shim.
python3 "$ROOT/docker/package-userland.py" \
    --build "$BUILD" --arch "$ARCH" --profile "$PROFILE" --inspect
SOURCE_DATE_EPOCH="$(python3 -c 'from datetime import datetime; import sys; print(int(datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).timestamp()))' "$BUILD_DATE")"

echo "build-docker: compiling current $ARCH container shim (isolated prefix, test hooks disabled)"
(
    cd "$ROOT"
    "$ZIG" build -Dcontainer=true -Dtest-hooks=false -Drelease \
        -Dtarget="$ARCH-linux-none" --prefix "$WORK/shim" --cache-dir "$WORK/zig-cache"
)
python3 "$ROOT/docker/package-userland.py" \
    --build "$BUILD" --arch "$ARCH" --profile "$PROFILE" \
    --shim-prefix "$WORK/shim" --source-root "$ROOT" \
    --epoch "$SOURCE_DATE_EPOCH" --output "$CONTEXT"

echo "build-docker: packaging native $PROFILE ($PLATFORM) as $IMAGE"
docker buildx build --load --platform "$PLATFORM" \
    --target "$PROFILE" --tag "$IMAGE" \
    --build-arg "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH" \
    --file "$ROOT/docker/Dockerfile" "$CONTEXT"
