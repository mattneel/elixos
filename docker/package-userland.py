#!/usr/bin/env python3
"""Repack pinned package layers as native OCI inputs, without host extraction."""

import argparse
import copy
from contextlib import contextmanager
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tarfile


ARCHITECTURES = {"x86_64": ("amd64", 62), "aarch64": ("arm64", 183)}
HELPERS = ("elixos-postgres-init", "elixos-gui-io", "elixos-console-handover")


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def required_file(path):
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"missing or empty {path}; provide existing target artifacts (see --help)")
    return path

def verify_toolchain(path):
    stamp = required_file(path.parent / ".elixos-toolchain.inputs").read_text().split()
    if (len(stamp) != 3 or not re.fullmatch(r"[0-9a-f]{64}", stamp[0])
            or not re.fullmatch(r"[0-9a-f]{64}", stamp[1]) or stamp[2] != path.name
            or digest(required_file(path)) != stamp[1]):
        raise ValueError(f"{path}: does not match the pinned toolchain build receipt")



def archive_name(name):
    if name.startswith("/") or "\0" in name or ".." in name.split("/"):
        raise ValueError(f"unsafe archive path: {name!r}")
    return "/".join(part for part in name.split("/") if part not in ("", "."))


def read_layer(directory, arch, root_digest=None):
    manifest = json.loads(required_file(directory / "manifest.json").read_text())
    if not isinstance(manifest, list) or len(manifest) != 1:
        raise ValueError(f"{directory}: expected one packaged target image")
    image = manifest[0]
    layers = image["Layers"]
    if len(layers) != 1 or not re.fullmatch(r"[0-9a-f]{64}\.tar\.gz", layers[0]):
        raise ValueError(f"{directory}: expected one digest-named apko layer")
    config_name = image["Config"]
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", config_name):
        raise ValueError(f"{directory}: invalid packaged image config name")
    config_path = required_file(directory / config_name)
    if digest(config_path) != config_name.removeprefix("sha256:"):
        raise ValueError(f"{config_path}: image config digest mismatch")
    config = json.loads(config_path.read_text())
    if config.get("os") != "linux" or config.get("architecture") != ARCHITECTURES[arch][0]:
        raise ValueError(f"{directory}: image does not target Linux {arch}")
    if root_digest is not None and required_file(root_digest).read_text().strip() != layers[0]:
        raise ValueError(f"{root_digest}: does not identify the packaged rootfs layer")
    return required_file(directory / layers[0])


@contextmanager
def output_tar(path, epoch):
    # No filename, host timestamps, ownership names or variable compressor seed.
    with path.open("wb") as raw:
        with gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=epoch, compresslevel=6) as compressed:
            with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.GNU_FORMAT) as output:
                yield output


def metadata(name, epoch, mode=0o444, kind=tarfile.REGTYPE):
    entry = tarfile.TarInfo(name)
    entry.mtime = epoch
    entry.mode = mode
    entry.type = kind
    return entry


def add_bytes(output, name, data, epoch, mode=0o444):
    entry = metadata(name, epoch, mode)
    entry.size = len(data)
    output.addfile(entry, io.BytesIO(data))


def add_binary(output, name, path, arch, epoch):
    with required_file(path).open("rb") as source:
        header = source.read(20)
        if (len(header) != 20 or header[:6] != b"\x7fELF\x02\x01"
                or int.from_bytes(header[18:20], "little") != ARCHITECTURES[arch][1]):
            raise ValueError(f"{path}: expected a current {arch} Linux ELF executable")
        source.seek(0)
        entry = metadata(name, epoch, 0o755)
        entry.size = path.stat().st_size
        output.addfile(entry, source)


def members(tar, keep):
    # Headers only: payloads are streamed from the archive into another tar.
    # Never extractall(), follow a packaged link, create a host device, or read
    # a mounted disk/session. Reject ambiguous paths before Docker sees them.
    entries = {}
    for member in tar:
        name = archive_name(member.name)
        if not name or not keep(name, member):
            continue
        if name in entries:
            raise ValueError(f"duplicate archive path: {name}")
        if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
            raise ValueError(f"unsupported archive entry: {name}")
        entries[name] = member
    for name, member in entries.items():
        for parent in Path(name).parents:
            if str(parent) in entries and not entries[str(parent)].isdir():
                raise ValueError(f"archive path traverses a non-directory: {name}")
        if member.islnk():
            target = archive_name(member.linkname)
            visited = {name}
            while target in entries and entries[target].islnk():
                if target in visited:
                    raise ValueError(f"cyclic archive hard link: {name}")
                visited.add(target)
                target = archive_name(entries[target].linkname)
            if target not in entries or not entries[target].isfile():
                raise ValueError(f"hard link outside packaged regular files: {name}")
    return entries


def copy_entries(tar, entries, output, epoch, prefix="", immutable=False):
    for name, member in entries.items():
        entry = copy.copy(member)
        entry.name = prefix + name
        entry.mtime = epoch
        entry.uname = entry.gname = ""
        entry.pax_headers = {}
        if immutable:
            entry.uid = entry.gid = 0
            entry.mode &= ~0o222
        if entry.islnk():
            entry.linkname = prefix + archive_name(entry.linkname)
        if entry.isfile():
            with tar.extractfile(member) as source:
                if name == "toolchain/rust/cargo-home/config.toml":
                    # The machine package lives on /priv; OCI's immutable
                    # toolchain must remain available under an empty volume.
                    data = source.read().replace(b"/priv/toolchain/", b"/toolchain/")
                    entry.size = len(data)
                    output.addfile(entry, io.BytesIO(data))
                else:
                    output.addfile(entry, source)
        else:
            output.addfile(entry)


def require_paths(entries, paths, label):
    missing = set(paths) - entries.keys()
    if missing:
        raise ValueError(f"{label}: missing packaged assets {', '.join(sorted(missing))}")


def root_member(name, member):
    if name == "priv" or name.startswith("priv/"):
        homes = {"priv": (0, 0, 0o755), "priv/home": (1000, 1000, 0o700),
                 "priv/postgres": (70, 70, 0o700)}
        if (name not in homes or not member.isdir()
                or (member.uid, member.gid, member.mode) != homes[name]):
            raise ValueError(f"packaged root carries mutable or unexpected /{name}")
    excluded = ("boot", "dev", "proc", "sys", "system", "toolchain",
                "usr/share/icu", "usr/share/zoneinfo")
    if any(name.startswith(path + "/") for path in excluded):
        return False
    return name not in {"boot", "init", "toolchain", "priv/postgres", "etc/elixos/helpers",
                        "etc/elixos/runtime", "usr/share/icu", "usr/share/zoneinfo",
                        *(f"usr/bin/{helper}" for helper in HELPERS)}


def package_root(path, output, args):
    with tarfile.open(path, "r:gz") as source:
        entries = members(source, root_member)
        require_paths(entries, ("factory", "factory/lib", "factory/erts", "factory/releases/current",
                                "usr/local/lib/erlang", "priv", "priv/home", "system"), path)
        with output_tar(output, args.epoch) as destination:
            copy_entries(source, entries, destination, args.epoch)
            destination.addfile(metadata("priv/postgres", args.epoch, 0o755, tarfile.DIRTYPE))
            for name in ("icu", "zoneinfo"):
                link = metadata(f"usr/share/{name}", args.epoch, 0o777, tarfile.SYMTYPE)
                link.linkname = f"/system/usr/share/{name}"
                destination.addfile(link)
            add_bytes(destination, "etc/elixos/runtime", b"container\n", args.epoch)
            add_bytes(destination, "etc/elixos/helpers",
                      required_file(args.source_root / "shim/helpers").read_bytes(), args.epoch)
            add_binary(destination, "init", args.shim_prefix / "bin/init", args.arch, args.epoch)
            for helper in HELPERS:
                add_binary(destination, f"usr/bin/{helper}", args.shim_prefix / "bin" / helper,
                           args.arch, args.epoch)


def package_system(path, output, args):
    def keep(name, member):
        return name.split("/", 1)[0] not in {"dev", "proc", "sys", "priv", "tmp", "boot"}

    with tarfile.open(path, "r:gz") as source:
        entries = members(source, keep)
        require_paths(entries, ("usr/libexec/postgresql17/postgres", "usr/libexec/postgresql17/initdb",
                                "usr/libexec/postgresql17/psql", "usr/share/icu", "usr/share/zoneinfo",
                                "browser/manifest.json",
                                f"gui/{args.arch}-unknown-linux-musl/libemerge_skia.so"), path)
        with output_tar(output, args.epoch) as destination:
            destination.addfile(metadata("system", args.epoch, 0o555, tarfile.DIRTYPE))
            copy_entries(source, entries, destination, args.epoch, prefix="system/", immutable=True)


def package_toolchain(path, output, args):
    # APK v2 concatenates signed control and data gzip/tar streams; ignore tar
    # trailers to reach the data, exactly as mkinitramfs.sh does for Live.
    with tarfile.open(path, "r:gz", ignore_zeros=True) as source:
        package = None
        for member in source:
            if archive_name(member.name) == ".PKGINFO":
                if package is not None or not member.isfile() or member.size > 1024 * 1024:
                    raise ValueError(f"{path}: invalid APK metadata")
                with source.extractfile(member) as control:
                    package = dict(line.split(" = ", 1) for line in control.read().decode().splitlines()
                                   if line and not line.startswith("#") and " = " in line)
        if not package or any(package.get(key) != value for key, value in (
                ("pkgname", "elixos-toolchain"), ("pkgver", "0.0.0-r0"), ("arch", args.arch))):
            raise ValueError(f"{path}: wrong toolchain package, version or target architecture")
        entries = members(source, lambda name, member: name == "toolchain" or name.startswith("toolchain/"))
        require_paths(entries, ("toolchain", "toolchain/lib", "toolchain/zig", "toolchain/cc",
                                "toolchain/c++", "toolchain/rust/usr/bin/rustc",
                                "toolchain/rust/usr/bin/cargo", "toolchain/rust/cargo-home/config.toml"), path)
        with output_tar(output, args.epoch) as destination:
            copy_entries(source, entries, destination, args.epoch, immutable=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", required=True, type=Path)
    parser.add_argument("--arch", required=True, choices=ARCHITECTURES)
    parser.add_argument("--profile", required=True, choices=("sdk", "runtime"))
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("--shim-prefix", type=Path)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--epoch", type=int)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    work = args.build / args.arch
    root = read_layer(work / "oci", args.arch, work / "rootfs.digest")
    system = read_layer(work / "system/oci", args.arch)
    toolchain = args.build / "apk" / args.arch / args.arch / "elixos-toolchain-0.0.0-r0.apk"
    if args.profile == "sdk":
        verify_toolchain(toolchain)
    if args.inspect:
        for label, path in (("rootfs", root), ("system", system)):
            print(f"build-docker: {args.arch} {label}: {path}")
        if args.profile == "sdk":
            print(f"build-docker: {args.arch} toolchain: {toolchain}")
        return
    if any(value is None for value in (args.shim_prefix, args.source_root, args.epoch, args.output)):
        parser.error("packaging requires --shim-prefix, --source-root, --epoch and --output")
    if not 0 <= args.epoch <= 0xFFFFFFFF:
        raise ValueError("BUILD_DATE must fit an unsigned 32-bit gzip timestamp")
    for path in (root, system):
        if digest(path) != path.name.removesuffix(".tar.gz"):
            raise ValueError(f"{path}: packaged layer digest mismatch; refusing altered artifacts")
    package_root(root, args.output / "rootfs.tar.gz", args)
    package_system(system, args.output / "system.tar.gz", args)
    if args.profile == "sdk":
        package_toolchain(toolchain, args.output / "toolchain.tar.gz", args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        print(f"build-docker: {error}", file=sys.stderr)
        sys.exit(1)
