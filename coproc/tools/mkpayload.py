#!/usr/bin/env python3
"""Packs the coprocessor firmware's payload (docs/notes/coproc-firmware.md).

The payload is loaded at COPROC_PAYLOAD_OFFSET in the little core's region,
next to the firmware image: the configuration (an environment block the
runtime reads with os:getenv/1), the AVM packs AtomVM boots (the first holds
the start module) and the files of the RAM file system (the cookie, a
bundle).

    mkpayload.py -o payload.bin \
        --env ELIXOS_COPROC_NODE=coproc@10.0.3.9 ... \
        --avm runtime.avm --avm atomvmlib.avm \
        --file cookie=path/to/cookie

Layout, all integers little-endian u32:
    header (32 bytes): "ELXP", version 1, entry count, total size,
                       CRC-32 of bytes [32, total size), 3 x 0
    entries (64 bytes each): kind, offset, size, 0, name (48 bytes, NUL-padded)
        kind 1 env   KEY=VALUE lines, name "env"
        kind 2 avm   an AVM pack, name its file name
        kind 3 file  a RAM file system file, name its path
    data, each entry's bytes at a 16-byte aligned offset
"""
import argparse
import os
import struct
import sys
import zlib

MAGIC = b"ELXP"
VERSION = 1
HEADER = 32
ENTRY = 64
KIND_ENV, KIND_AVM, KIND_FILE = 1, 2, 3


def align(n, to=16):
    return (n + to - 1) & ~(to - 1)


def pack(entries):
    """entries: [(kind, name, bytes)] -> payload bytes."""
    offset = align(HEADER + ENTRY * len(entries))
    table, data = b"", bytearray()
    for kind, name, blob in entries:
        encoded = name.encode()
        if len(encoded) >= 48:
            sys.exit(f"mkpayload: name too long: {name}")
        start = align(offset + len(data))
        data += b"\0" * (start - offset - len(data))
        table += struct.pack("<4I48s", kind, start, len(blob), 0, encoded)
        data += blob
    body = table + b"\0" * (align(HEADER + len(table)) - HEADER - len(table)) + bytes(data)
    total = HEADER + len(body)
    header = struct.pack("<4s4I12x", MAGIC, VERSION, len(entries), total, zlib.crc32(body))
    return header + body


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("--env", action="append", default=[], metavar="KEY=VALUE")
    parser.add_argument("--avm", action="append", default=[], metavar="PATH")
    parser.add_argument("--file", action="append", default=[], metavar="NAME=PATH")
    args = parser.parse_args()

    entries = []
    for line in args.env:
        if "=" not in line or "\n" in line:
            sys.exit(f"mkpayload: bad --env {line!r}")
    if args.env:
        entries.append((KIND_ENV, "env", "".join(line + "\n" for line in args.env).encode()))
    if not args.avm:
        sys.exit("mkpayload: at least one --avm (the first holds the start module)")
    for path in args.avm:
        with open(path, "rb") as f:
            entries.append((KIND_AVM, os.path.basename(path), f.read()))
    for spec in args.file:
        name, sep, path = spec.partition("=")
        if not sep or not name:
            sys.exit(f"mkpayload: bad --file {spec!r}")
        with open(path, "rb") as f:
            entries.append((KIND_FILE, name, f.read()))

    payload = pack(entries)
    with open(args.output, "wb") as f:
        f.write(payload)
    names = ", ".join(f"{name} ({len(blob)})" for _, name, blob in entries)
    print(f"mkpayload: {args.output}: {len(payload)} bytes: {names}")


if __name__ == "__main__":
    main()
