#!/usr/bin/env bash
# Pack an apko-built root filesystem into the initramfs the kernel unpacks.
#
#   scripts/mkinitramfs.sh <rootfs.tar.gz> <initramfs.cpio.gz>
#
# The input is apko's layer for an architecture (scripts/build-image.sh builds
# it): a gzipped tar of the whole root filesystem, written from the packages -
# which is where ownership lives. Reading it is why this needs no root, and why
# it does not need the kernel tree either: the archive is written here, in the
# kernel's newc format (initramfs is a gzipped newc cpio), so device nodes are
# declared rather than mknod'd (privileges) and every entry carries the tar's
# own uid, gid and mode. Timestamps are zero and the gzip header carries no
# name, so two packings of the same layer are byte-identical.
#
# Env: ELIXOS_BUILD (default build/).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
LAYER="${1:?usage: mkinitramfs.sh <rootfs.tar.gz> <initramfs.cpio.gz>}"
OUT="${2:?usage: mkinitramfs.sh <rootfs.tar.gz> <initramfs.cpio.gz>}"

[ -f "$LAYER" ] || { echo "mkinitramfs: no $LAYER" >&2; exit 1; }

python3 - "$LAYER" "$OUT" <<'PY'
import gzip, stat, struct, sys, tarfile

layer, out = sys.argv[1], sys.argv[2]

# newc (initramfs) records: a 110-byte ASCII header, the NUL-terminated name,
# both padded to four bytes, then the data, padded the same way.
HEADER = "070701" + "{:08x}" * 13


def record(name, mode, uid, gid, data=b"", rdev=(0, 0)):
    name_bytes = name.encode() + b"\0"
    header = HEADER.format(
        0,  # inode: the kernel does not need uniqueness here
        mode,
        uid,
        gid,
        1,
        0,  # mtime: zero, for reproducibility
        len(data),
        0,
        0,
        rdev[0],
        rdev[1],
        len(name_bytes),
        0,
    ).encode()
    body = header + name_bytes
    # The 110-byte header is not a multiple of four, so the *record* (header
    # plus name) is what gets padded - aligning only the name leaves a
    # two-byte misalignment that the kernel's unpacker skips as junk.
    body += b"\0" * ((-len(body)) % 4)
    body += data + b"\0" * ((-len(data)) % 4)
    return body


with tarfile.open(layer, "r:gz") as tar:
    # filename="" keeps the name out of the gzip header, and mtime=0 keeps the
    # timestamp out: two packings of one layer are byte-identical.
    with open(out, "wb") as raw, gzip.GzipFile(
        filename="", mode="wb", fileobj=raw, mtime=0
    ) as cpio:
        for member in tar:
            name = member.name.lstrip("./")
            if name in ("", "."):
                continue

            if member.isdir():
                cpio.write(record(name, stat.S_IFDIR | member.mode, member.uid, member.gid))
            elif member.issym():
                data = member.linkname.encode()
                cpio.write(record(name, stat.S_IFLNK | member.mode, member.uid, member.gid, data))
            elif member.ischr() or member.isblk():
                kind = stat.S_IFCHR if member.ischr() else stat.S_IFBLK
                cpio.write(
                    record(
                        name,
                        kind | member.mode,
                        member.uid,
                        member.gid,
                        rdev=(member.devmajor, member.devminor),
                    )
                )
            elif member.isfile():
                cpio.write(
                    record(name, stat.S_IFREG | member.mode, member.uid, member.gid,
                           tar.extractfile(member).read())
                )
            elif member.islnk():
                # A hard link: newc has no primitive for it, and both names
                # carry the content, so the target's bytes are read here.
                source = tar.extractfile(tar.getmember(member.linkname))
                cpio.write(record(name, stat.S_IFREG | member.mode, member.uid, member.gid,
                                  source.read() if source else b""))
            else:
                print(f"mkinitramfs: ignoring {name} ({member.type})", file=sys.stderr)

        # The trailer, then zero padding to a 512-byte boundary: what the
        # kernel's unpacker expects at the end of the archive.
        cpio.write(record("TRAILER!!!", 0, 0, 0))
        cpio.write(b"\0" * ((-cpio.tell()) % 512))

print(f"initramfs: {out}", file=sys.stderr)
PY

echo "initramfs: $OUT ($(du -h "$OUT" | cut -f1))"
