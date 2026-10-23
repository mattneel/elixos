#!/usr/bin/env python3
"""Render M27's framebuffer and IEx on one uncompressed capture timebase."""
import json
import pathlib
import re
import subprocess
import sys

agg, cast_file, frames_dir, gif_file, output_file = sys.argv[1:]
cast_file, frames_dir, gif_file, output_file = map(pathlib.Path, (cast_file, frames_dir, gif_file, output_file))
frames = sorted(frames_dir.glob("frame-*.ppm"))
if not frames:
    raise SystemExit("compose: no actual framebuffer captures")
duration = len(frames) / 4
clock = 0.0
text = ""
start = None
stop = None
with cast_file.open() as cast:
    header = json.loads(cast.readline())
    for line in cast:
        if not line.strip():
            continue
        event = json.loads(line)
        clock = clock + event[0] if header["version"] == 3 else event[0]
        if event[1] != "o":
            continue
        text += event[2]
        if start is None and "CAPTURE READY" in text:
            start = clock
        # The GUI hands the screen back by itself once nothing is pending;
        # the last confirmed handback ends the framebuffer panel.
        if "M27 HANDED BACK {:error, :not_running}" in text:
            stop = clock
if start is None:
    raise SystemExit("compose: capture start marker missing from console recording")
if stop is None:
    raise SystemExit("compose: successful console handback marker missing")
stop -= start
end = start + duration
for path in (gif_file, output_file):
    path.unlink(missing_ok=True)
subprocess.run([
    agg, "--font-size", "16", "--speed", "1", "--idle-time-limit", "86400",
    "--fps-cap", "12", "--last-frame-duration", "0.25",
    "--select", f"{start:.3f}..{end:.3f}", str(cast_file), str(gif_file)
], check=True)
console = output_file.with_name(output_file.stem + "-console.mp4")
framebuffer = output_file.with_name(output_file.stem + "-framebuffer.mp4")
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(gif_file),
    "-vf", f"fps=4,tpad=stop_mode=clone:stop_duration={duration},scale=trunc(iw/2)*2:trunc(ih/2)*2",
    "-t", str(duration), "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart", str(console)
], check=True)
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", "4",
    "-i", str(frames_dir / "frame-%06d.ppm"), "-pix_fmt", "yuv420p", "-crf", "20",
    "-movflags", "+faststart", str(framebuffer)
], check=True)
# The dialog occupies the centered 720px panel. Remove empty side margins,
# then pan to the left edge on handback so the returned fbcon text stays visible.
ppm = frames[0].read_bytes()
match = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", ppm)
if not match:
    raise SystemExit("compose: invalid framebuffer PPM")
width, height = map(int, match.groups())
crop_width = min(width, 768)
font = subprocess.check_output(["fc-match", "-f", "%{file}", "DejaVu Sans"], text=True).strip()
filter_graph = (
    f"[0:v]crop={crop_width}:{height}:x='if(lt(t,{stop:.3f}),(iw-{crop_width})/2,0)':y=0,"
    "scale=800:880:force_original_aspect_ratio=decrease,"
    "pad=800:880:(ow-iw)/2:0:color=0x0e121b[g];"
    "[1:v]scale=1200:880:force_original_aspect_ratio=decrease,"
    "pad=1200:880:0:0:color=0x161b25[c];"
    "[g][c]hstack=inputs=2,pad=2000:1000:0:60:color=0x0e121b,"
    f"drawtext=fontfile='{font}':text='GUI  /  LIVE FRAMEBUFFER':x=24:y=16:fontsize=28:fontcolor=white,"
    f"drawtext=fontfile='{font}':text='IEx  /  COMMANDS AND ANSWERS':x=824:y=16:fontsize=28:fontcolor=white,"
    f"drawtext=fontfile='{font}':text='Real keyboard input answers the Oh-My-Jido approvals listed in IEx.':"
    "x=24:y=958:fontsize=26:fontcolor=0xb8c8dc[v]"
)
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(framebuffer), "-i", str(console),
    "-filter_complex", filter_graph, "-map", "[v]", "-t", str(duration), "-r", "4",
    "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart", str(output_file)
], check=True)
print(f"compose: aligned to console {start:.3f}s; {len(frames)} framebuffer frames; {duration:.2f}s side-by-side")
