#!/usr/bin/env bash
# Pack an apko-built root filesystem into the initramfs the kernel unpacks.
#
#   scripts/mkinitramfs.sh <rootfs.tar.gz> <initramfs.cpio.gz>
#
# The input is apko's layer for an architecture (scripts/build-image.sh builds
# it): a gzipped tar of the whole root filesystem, written from the packages -
# which is where ownership lives. Reading it is why this needs no root:
# gen_init_cpio is told every entry's uid, gid and mode explicitly, device
# nodes are declared (mknod needs privileges, a list entry does not), and the
# archive is extracted only for file *contents*.
#
# Env: ELIXOS_BUILD (default build/), GEN (gen_init_cpio from the kernel tree).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../kernel/VERSION
. "$ROOT/kernel/VERSION"

BUILD="${ELIXOS_BUILD:-$ROOT/build}"
GEN="${GEN:-$BUILD/linux-$KERNEL_VERSION/usr/gen_init_cpio}"
LAYER="${1:?usage: mkinitramfs.sh <rootfs.tar.gz> <initramfs.cpio.gz>}"
OUT="${2:?usage: mkinitramfs.sh <rootfs.tar.gz> <initramfs.cpio.gz>}"
SCRATCH="$BUILD/initramfs-scratch"
LIST="$BUILD/initramfs.list"

[ -x "$GEN" ] || { echo "mkinitramfs: $GEN missing; run: make kernel" >&2; exit 1; }
[ -f "$LAYER" ] || { echo "mkinitramfs: no $LAYER" >&2; exit 1; }

rm -rf "$SCRATCH"
mkdir -p "$SCRATCH"
# Device nodes cannot be extracted without root, and they do not need to be:
# the list below declares them from the tar's own major/minor.
tar -xzf "$LAYER" -C "$SCRATCH" --exclude 'dev/*'

python3 - "$LAYER" "$SCRATCH" > "$LIST" <<'PY'
import sys, tarfile

layer, scratch = sys.argv[1], sys.argv[2]

# gen_init_cpio processes the list in order and expects a directory before
# anything inside it; the tar is already parent-first, so one pass is enough.
def emit(kind, name, mode, uid, gid, extra=""):
    print(f"{kind} /{name.lstrip('./')} {mode:04o} {uid} {gid}{extra}", flush=True)

with tarfile.open(layer, "r:gz") as tar:
    for member in tar:
        name = member.name
        if name in (".", "./"):
            continue
        if name.startswith("dev/") and (member.ischr() or member.isblk()):
            kind = "c" if member.ischr() else "b"
            emit("nod", name, member.mode, member.uid, member.gid,
                 f" {kind} {member.devmajor} {member.devminor}")
        elif member.isdir():
            emit("dir", name, member.mode, member.uid, member.gid)
        elif member.issym():
            print(f"slink /{name.lstrip('./')} {member.linkname} {member.mode:04o} {member.uid} {member.gid}",
                  flush=True)
        elif member.isfile():
            # NB: for `file` gen_init_cpio wants the location *before* mode,
            # uid and gid (the other entry kinds carry no location).
            print(f"file /{name.lstrip('./')} {scratch}/{name} "
                  f"{member.mode:04o} {member.uid} {member.gid}", flush=True)
        elif member.islnk():
            # A hard link: gen_init_cpio has no primitive for it, and the tar
            # has the content elsewhere - both files carry it.
            print(f"file /{name.lstrip('./')} {scratch}/{member.linkname.lstrip('./')} "
                  f"{member.mode:04o} {member.uid} {member.gid}", flush=True)
        else:
            print(f"mkinitramfs: ignoring {name} ({member.type})", file=sys.stderr)
PY

"$GEN" -t 0 "$LIST" | gzip -9n > "$OUT"
echo "initramfs: $OUT ($(du -h "$OUT" | cut -f1), $(grep -c '' "$LIST") entries)"
