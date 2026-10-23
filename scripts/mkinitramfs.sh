#!/usr/bin/env bash
# Pack an apko-built root filesystem into the initramfs the kernel unpacks.
#
#   scripts/mkinitramfs.sh <rootfs.tar.gz> <initramfs.cpio.gz>
#   scripts/mkinitramfs.sh --live <base-initramfs.cpio.gz> <out> <arch>
#
# The input is apko's layer for an architecture (scripts/build-image.sh builds
# it): a gzipped tar of the whole root filesystem, written from the packages -
# which is where ownership lives. Reading it is why this needs no root, and why
# it does not need the kernel tree either: the archive is written here, in the
# kernel's newc format (initramfs is a gzipped newc cpio), so device nodes are
# declared rather than mknod'd (privileges) and every entry carries the tar's
# own uid, gid and mode. Timestamps are zero and the gzip header carries no
# name, so two packings of the same inputs are byte-identical. Large payloads
# are streamed; no extracted host tree or compiler cache enters the archive.
#
# Live preserves the base initramfs verbatim and appends a second gzip/newc
# archive containing only mkdisk.sh's pristine /priv seeds. The pinned kernel's
# Documentation/driver-api/early-userspace/buffer-format.rst explicitly permits
# concatenated compressed archives and resets hard-link state at TRAILER!!!.
#
# Env: ELIXOS_BUILD (default build/).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ELIXOS_BUILD:-$ROOT/build}"
MODE=base
ARCH=
TOOLCHAIN=
SYSTEM=
usage() {
  echo "usage: mkinitramfs.sh <rootfs.tar.gz> <initramfs.cpio.gz>" >&2
  echo "       mkinitramfs.sh --live <base-initramfs.cpio.gz> <out> <arch>" >&2
  exit 1
}
if [ "${1:-}" = --live ]; then
  [ "$#" -eq 4 ] || usage
  MODE=live
  INPUT="$2"
  OUT="$3"
  ARCH="$4"
  case "$ARCH" in
    x86_64|aarch64|riscv64) ;;
    *) echo "mkinitramfs: unsupported architecture $ARCH" >&2; exit 1 ;;
  esac
  # Use the same package and immutable service filesystem as mkdisk.sh, not
  # a mounted disk, a host toolchain, or a prior session's writable /priv.
  TOOLCHAIN="$BUILD/apk/$ARCH/$ARCH/elixos-toolchain-0.0.0-r0.apk"
  SYSTEM="$BUILD/$ARCH/system.squashfs"
else
  [ "$#" -eq 2 ] || usage
  INPUT="$1"
  OUT="$2"
fi

for input in "$INPUT" ${TOOLCHAIN:+"$TOOLCHAIN"} ${SYSTEM:+"$SYSTEM"}; do
  [ -s "$input" ] && [ -f "$input" ] || {
    echo "mkinitramfs: missing or empty input $input; run scripts/build-image.sh ${ARCH:-x86_64}" >&2
    exit 1
  }
done

python3 - "$MODE" "$INPUT" "$OUT" "$TOOLCHAIN" "$SYSTEM" "$ARCH" <<'PY'
import filecmp
import gzip
import os
import shutil
import stat
import sys
import tarfile
import tempfile

mode, input_path, out, toolchain, system, arch = sys.argv[1:]
CHUNK = 1024 * 1024

# newc records: a 110-byte ASCII header and NUL-terminated name, padded
# together to four bytes, followed by the data and its four-byte padding.
HEADER = "070701" + "{:08x}" * 13


def copy_data(source, destination, size):
    while size:
        data = source.read(min(size, CHUNK))
        if not data:
            raise EOFError("truncated archive payload")
        if destination is not None:
            destination.write(data)
        size -= len(data)


def record(cpio, name, mode, uid, gid, data=b"", source=None, size=None, rdev=(0, 0),
           ino=0, nlink=1):
    name_bytes = name.encode(errors="surrogateescape") + b"\0"
    size = len(data) if size is None else size
    fields = (ino, mode, uid, gid, nlink, 0, size, 0, 0, *rdev, len(name_bytes), 0)
    if len(name_bytes) > 4096 or any(not 0 <= field <= 0xFFFFFFFF for field in fields):
        raise ValueError(f"{name}: metadata exceeds the kernel's newc limits")
    body = HEADER.format(*fields).encode() + name_bytes
    cpio.write(body)
    cpio.write(b"\0" * ((-len(body)) % 4))
    if source is None:
        cpio.write(data)
    else:
        copy_data(source, cpio, size)
    cpio.write(b"\0" * ((-size) % 4))


def clean_name(name):
    parts = name.split("/")
    if name.startswith("/") or ".." in parts or "\0" in name:
        raise ValueError(f"unsafe archive path: {name!r}")
    return "/".join(part for part in parts if part not in ("", "."))


def read_exact(source, size):
    data = source.read(size)
    if len(data) != size:
        raise EOFError("truncated newc header or filename")
    return data


def validate_base(path):
    # The Live base must be a pristine packaged root, never a captured session.
    # Parse metadata while discarding file data in bounded chunks; do not unpack
    # or recompress it. In particular, no boot.state or other /priv state is
    # allowed to hide underneath the new seeds.
    saw_priv = saw_init = trailer = False
    with gzip.open(path, "rb") as cpio:
        while True:
            first = cpio.read(1)
            while first == b"\0":
                first = cpio.read(1)
            if not first:
                break
            if (cpio.tell() - 1) % 4:
                raise ValueError("base newc header is not four-byte aligned")
            header = first + read_exact(cpio, 109)
            if header[:6] != b"070701":
                raise ValueError("Live base must contain newc archives from mkinitramfs.sh")
            fields = [int(header[index:index + 8], 16) for index in range(6, 110, 8)]
            _, entry_mode, uid, gid, _, _, size, _, _, _, _, namesize, _ = fields
            if not 1 <= namesize <= 4096:
                raise ValueError("invalid base newc filename length")
            raw_name = read_exact(cpio, namesize)
            if not raw_name.endswith(b"\0"):
                raise ValueError("unterminated base newc filename")
            name = clean_name(raw_name.rstrip(b"\0").decode(errors="surrogateescape"))
            read_exact(cpio, (-(110 + namesize)) % 4)
            trailer = name == "TRAILER!!!"
            if trailer and size:
                raise ValueError("base newc trailer carries data")
            if name == "priv":
                if (entry_mode, uid, gid) != (stat.S_IFDIR | 0o755, 0, 0):
                    raise ValueError("base /priv must be a root-owned 0755 directory")
                saw_priv = True
            elif name.startswith("priv/"):
                # apko creates the two account homes even in a pristine root.
                # Permit only those empty directories, never captured state.
                homes = {"priv/home": (1000, 1000), "priv/postgres": (70, 70)}
                if (name not in homes or (uid, gid) != homes[name]
                        or entry_mode != stat.S_IFDIR | 0o700 or size):
                    raise ValueError(f"Live base carries mutable /{name}; use the pristine initramfs")
            if name == "init" and stat.S_ISREG(entry_mode) and entry_mode & 0o111:
                saw_init = True
            copy_data(cpio, None, size)
            read_exact(cpio, (-size) % 4)
    if not saw_priv or not saw_init or not trailer:
        raise ValueError("Live base lacks /init, pristine /priv, or the final newc trailer")


def pack_tar(cpio, path, live=False):
    required = {
        "toolchain": "directory",
        "toolchain/lib": "directory",
        "toolchain/zig": "executable",
        "toolchain/cc": "executable",
        "toolchain/c++": "symlink",
        "toolchain/rust/usr/bin/rustc": "executable",
        "toolchain/rust/usr/bin/cargo": "executable",
        "toolchain/rust/cargo-home/config.toml": "file",
    }
    seen = set()
    package_ok = False
    # APK v2 is a concatenation of gzip/tar streams (signature, metadata, data).
    # ignore_zeros is required to get past the earlier tar trailers.
    with tarfile.open(path, "r:gz", ignore_zeros=live) as tar:
        # Retain only tar headers, not file contents. Knowing the hard-link
        # groups up front lets newc carry each large file exactly once, even
        # when a tar link precedes its target.
        entries = [(clean_name(member.name), member) for member in tar]
        by_name = {
            name: member for name, member in entries
            if name and (not live or name == "toolchain" or name.startswith("toolchain/"))
        }
        link_groups = {}
        for name, member in by_name.items():
            if not member.islnk():
                continue
            target = name
            visited = set()
            while by_name[target].islnk():
                if target in visited:
                    raise ValueError(f"cyclic tar hard link: {name}")
                visited.add(target)
                target = clean_name(by_name[target].linkname)
                if target not in by_name:
                    raise ValueError(f"tar hard link outside the packaged tree: {name}")
            if not by_name[target].isfile():
                raise ValueError(f"tar hard link has no regular-file target: {name}")
            link_groups.setdefault(target, [target]).append(name)
        link_fields = {
            name: {"ino": ino, "nlink": len(names)}
            for ino, names in enumerate(link_groups.values(), 1) for name in names
        }
        for name, member in entries:
            if not name:
                continue
            links = link_fields.get(name, {})
            if live:
                if name == ".PKGINFO":
                    if not member.isfile() or member.size > CHUNK:
                        raise ValueError("invalid toolchain APK metadata")
                    with tar.extractfile(member) as source:
                        metadata = source.read().decode()
                    values = dict(
                        line.split(" = ", 1) for line in metadata.splitlines()
                        if line and not line.startswith("#") and " = " in line
                    )
                    if any(values.get(key) != value for key, value in (
                        ("pkgname", "elixos-toolchain"), ("pkgver", "0.0.0-r0"), ("arch", arch)
                    )):
                        raise ValueError(f"{path}: wrong toolchain package or architecture")
                    package_ok = True
                if name != "toolchain" and not name.startswith("toolchain/"):
                    continue
                if name in seen:
                    raise ValueError(f"duplicate toolchain path: {name}")
                seen.add(name)
                kind = required.get(name)
                valid = (
                    (kind == "directory" and member.isdir())
                    or (kind == "executable" and (member.isfile() or member.islnk())
                        and member.mode & 0o111)
                    or (kind == "symlink" and member.issym() and member.linkname == "cc")
                    or (kind == "file" and (member.isfile() or member.islnk()))
                )
                if kind and not valid:
                    raise ValueError(f"{path}: invalid required {kind} {name}")
                name = "priv/" + name

            if member.isdir():
                record(cpio, name, stat.S_IFDIR | member.mode, member.uid, member.gid)
            elif member.issym():
                record(cpio, name, stat.S_IFLNK | member.mode, member.uid, member.gid,
                       data=member.linkname.encode(errors="surrogateescape"))
            elif member.ischr() or member.isblk():
                kind = stat.S_IFCHR if member.ischr() else stat.S_IFBLK
                record(cpio, name, kind | member.mode, member.uid, member.gid,
                       rdev=(member.devmajor, member.devminor))
            elif member.isfile():
                with tar.extractfile(member) as source:
                    record(cpio, name, stat.S_IFREG | member.mode, member.uid, member.gid,
                           source=source, size=member.size, **links)
            elif member.islnk():
                record(cpio, name, stat.S_IFREG | member.mode, member.uid, member.gid, **links)
            elif member.isfifo():
                record(cpio, name, stat.S_IFIFO | member.mode, member.uid, member.gid)
            elif live:
                raise ValueError(f"unsupported toolchain entry: {name} ({member.type!r})")
            else:
                print(f"mkinitramfs: ignoring {name} ({member.type})", file=sys.stderr)
    if live and (not package_ok or required.keys() - seen):
        raise ValueError(f"{path}: missing toolchain metadata or assets {sorted(required.keys() - seen)}")


temporary = None
try:
    inputs = (input_path, toolchain, system) if mode == "live" else (input_path,)
    if any(os.path.realpath(path) == os.path.realpath(out)
           or (os.path.exists(out) and os.path.samefile(path, out)) for path in inputs):
        raise ValueError("output must not overwrite an input")
    if mode == "live":
        validate_base(input_path)
        with open(system, "rb") as source:
            if source.read(4) != b"hsqs" or os.fstat(source.fileno()).st_size < 96:
                raise ValueError(f"{system}: not a SquashFS image")

    # Publish only a complete archive. A failed input never destroys a prior
    # good image, and byte-identical output keeps its mtime for kernel caching.
    with tempfile.NamedTemporaryFile(
        mode="wb", prefix=f".{os.path.basename(out)}.", dir=os.path.dirname(out) or ".",
        delete=False,
    ) as raw:
        temporary = raw.name
        if mode == "live":
            with open(input_path, "rb") as base:
                shutil.copyfileobj(base, raw, CHUNK)
        # filename="" and mtime=0 keep host names and time out of the gzip header.
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as cpio:
            if mode == "live":
                record(cpio, "priv", stat.S_IFDIR | 0o755, 0, 0)
                # The persistent disk hides apko's postgres-owned home. Live
                # exposes it, so install the root-owned parent required by the
                # unchanged privileged service-directory checks.
                record(cpio, "priv/postgres", stat.S_IFDIR | 0o755, 0, 0)
                record(cpio, "priv/system", stat.S_IFDIR | 0o755, 0, 0)
                with open(system, "rb") as source:
                    record(cpio, "priv/system/system.squashfs", stat.S_IFREG | 0o444, 0, 0,
                           source=source, size=os.fstat(source.fileno()).st_size)
            pack_tar(cpio, toolchain if mode == "live" else input_path, live=mode == "live")
            record(cpio, "TRAILER!!!", 0, 0, 0)
            cpio.write(b"\0" * ((-cpio.tell()) % 512))
    os.chmod(temporary, 0o644)
    if os.path.isfile(out) and filecmp.cmp(temporary, out, shallow=False):
        os.unlink(temporary)
    else:
        os.replace(temporary, out)
    temporary = None
except (OSError, ValueError, EOFError, tarfile.TarError) as error:
    raise SystemExit(f"mkinitramfs: {error}") from error
finally:
    if temporary is not None:
        os.unlink(temporary)

print(f"initramfs: {out}", file=sys.stderr)
PY

echo "initramfs: $OUT ($(du -h "$OUT" | cut -f1))"
