#!/usr/bin/env python3
"""Rewrites a U-Boot environment image with overrides (M33, the deck card).

    k230-env.py <env.bin> <overrides.txt> <out.bin> [--redundant]

<env.bin> is the firmware build's environment (melange/k230-firmware.yaml:
U-Boot's defaults plus boards/t-display-k230/uboot-env.txt, made by
mkenvimage). Every KEY=VALUE line of <overrides.txt> (blank lines and #
comments skipped) replaces or adds that variable, keeping the order;
<out.bin> has the same size, layout and CRC rules: CRC-32 (zlib) of the data
area, little-endian, then with --redundant one flags byte (1, as
mkenvimage -r writes), then NUL-terminated KEY=VALUE strings and a final NUL,
padded with the input's padding byte (0xff from this firmware build).
"""
import struct
import sys
import zlib


def decode(data, redundant):
    skip = 5 if redundant else 4
    (crc,) = struct.unpack("<I", data[:4])
    body = data[skip:]
    if zlib.crc32(body) != crc:
        sys.exit("k230-env: CRC mismatch in the input environment")
    end = body.index(b"\0\0")
    pad = body[end + 2:end + 3] or b"\0"
    pairs = body[:end].split(b"\0")
    env = []
    for pair in pairs:
        key, sep, value = pair.partition(b"=")
        if not sep:
            sys.exit(f"k230-env: malformed variable {pair!r}")
        env.append([key.decode(), value.decode()])
    return env, pad


def encode(env, size, redundant, pad):
    skip = 5 if redundant else 4
    strings = b"".join(f"{k}={v}".encode() + b"\0" for k, v in env) + b"\0"
    if len(strings) > size - skip:
        sys.exit(f"k230-env: {len(strings)} bytes of variables do not fit {size - skip}")
    body = strings + pad * (size - skip - len(strings))
    flags = b"\x01" if redundant else b""
    return struct.pack("<I", zlib.crc32(body)) + flags + body


def overrides(path):
    result = []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep or not key:
            sys.exit(f"k230-env: not KEY=VALUE: {line!r}")
        result.append((key, value))
    return result


def main():
    args = [a for a in sys.argv[1:] if a != "--redundant"]
    redundant = "--redundant" in sys.argv[1:]
    if len(args) != 3:
        sys.exit(__doc__.split("\n\n")[1])
    source, changes, target = args
    data = open(source, "rb").read()
    env, pad = decode(data, redundant)
    for key, value in overrides(changes):
        for pair in env:
            if pair[0] == key:
                pair[1] = value
                break
        else:
            env.append([key, value])
    open(target, "wb").write(encode(env, len(data), redundant, pad))
    for key, value in env:
        print(f"  {key}={value}")


if __name__ == "__main__":
    main()
