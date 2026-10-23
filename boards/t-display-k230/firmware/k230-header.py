#!/usr/bin/env python3
"""Wrap a payload in the K230 BootROM/SPL firmware header (plaintext mode).

Reimplements `firmware_gen.py -n` (k230_linux_sdk fc6cc215,
buildroot-overlay/boot/uboot/u-boot-2022.10-overlay/tools/firmware_gen_no_securiy.py;
same layout as k230_sdk v2.0 tools/firmware_gen.py l.329-350, 361-375) without
its pycryptodome/gmssl imports. The SPL parses it as `firmware_head_s`
(board/canaan/common/k230_board_common.h):

    off   size  field
    0     4     magic "K230" (0x3033324B little-endian)
    4     4     length of the data below, LE32 (version word + payload)
    8     4     crypto_type, LE32: 0 = no encryption, SHA-256 only
    12    32    SHA-256 of (version word + payload)
    44    484   zero (rest of the 516-byte signature/key union)
    528   4     version word, always 0
    532   ...   payload

  k230-header.py IN OUT      write OUT = header + version + IN
  k230-header.py --check F   verify magic, length, crypto_type and digest of F
"""
import hashlib
import struct
import sys

MAGIC = b"K230"
UNION = 516
HEADER = 12 + UNION


def wrap(payload: bytes) -> bytes:
    data = b"\0\0\0\0" + payload
    digest = hashlib.sha256(data).digest()
    head = MAGIC + struct.pack("<Ii", len(data), 0) + digest + bytes(UNION - len(digest))
    assert len(head) == HEADER
    return head + data


def check(image: bytes) -> str:
    if image[:4] != MAGIC:
        raise SystemExit(f"bad magic {image[:4]!r}")
    length, crypto = struct.unpack_from("<Ii", image, 4)
    data = image[HEADER:]
    if crypto != 0:
        raise SystemExit(f"crypto_type {crypto}, expected 0")
    if length != len(data):
        raise SystemExit(f"length field {length} != data {len(data)}")
    want = image[12:44]
    got = hashlib.sha256(data).digest()
    if want != got or any(image[44:HEADER]):
        raise SystemExit("header digest mismatch")
    return f"magic=K230 length={length} crypto_type=0 sha256={got.hex()} (matches)"


def main(argv):
    if len(argv) == 3 and argv[1] == "--check":
        with open(argv[2], "rb") as f:
            print(f"{argv[2]}: {check(f.read())}")
    elif len(argv) == 3:
        with open(argv[1], "rb") as f:
            out = wrap(f.read())
        with open(argv[2], "wb") as f:
            f.write(out)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
