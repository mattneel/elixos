#!/usr/bin/env python3
"""Check the retained QMP captures against the framebuffer video's stream."""
import hashlib
import json
import pathlib
import re
import subprocess
import sys

frames_dir, video = map(pathlib.Path, sys.argv[1:3])
combined = pathlib.Path(sys.argv[3]) if len(sys.argv) == 4 else None
frames = sorted(frames_dir.glob("frame-*.ppm"))
if len(frames) < 16:
    raise SystemExit("graphics: fewer than four seconds of actual framebuffer captures")
hashes = set()
dimensions = None
for index, frame in enumerate(frames):
    if frame.name != f"frame-{index:06d}.ppm":
        raise SystemExit("graphics: missing frame in capture sequence")
    data = frame.read_bytes()
    header = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", data)
    if not header:
        raise SystemExit(f"graphics: invalid QEMU PPM: {frame}")
    size = tuple(map(int, header.groups()))
    if len(data) - header.end() != size[0] * size[1] * 3:
        raise SystemExit(f"graphics: truncated QEMU PPM: {frame}")
    if dimensions is not None and size != dimensions:
        raise SystemExit("graphics: capture dimensions changed mid-recording")
    dimensions = size
    hashes.add(hashlib.sha256(data).digest())
if len(hashes) < 5:
    raise SystemExit("graphics: fewer than five distinct framebuffer images; dialogs not demonstrated")
probe = subprocess.check_output([
    "ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
    "-show_entries", "stream=width,height,nb_read_frames", "-of", "json", str(video)
])
stream = json.loads(probe)["streams"][0]
expected_dimensions = tuple(value // 2 * 2 for value in dimensions)
if (stream["width"], stream["height"]) != expected_dimensions:
    raise SystemExit("graphics: video dimensions do not match the framebuffer")
if int(stream["nb_read_frames"]) != len(frames):
    raise SystemExit("graphics: video frame count does not match the QMP captures")
print(f"graphics: {len(frames)} real framebuffer frames, {len(hashes)} distinct images")
if combined is not None:
    probe = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
        "-show_entries", "stream=width,height,nb_read_frames", "-of", "json", str(combined)
    ])
    stream = json.loads(probe)["streams"][0]
    if (stream["width"], stream["height"]) != (2000, 1000):
        raise SystemExit("graphics: side-by-side video panel dimensions are wrong")
    if int(stream["nb_read_frames"]) != len(frames):
        raise SystemExit("graphics: combined video does not retain the capture timeline")
    print("graphics: synchronized framebuffer and IEx panels verified")
