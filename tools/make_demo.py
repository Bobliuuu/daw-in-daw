#!/usr/bin/env python3
"""Assemble the demo video from the app's own recorded framebuffer frames + real stage renders.
usage: tools/make_demo.py [out.mp4]      (needs: python3 + Pillow, ffmpeg)   inputs: out/demo/{frames.txt,stages.txt,final.wav,stages/*.wav}
Frames are the REAL gfx framebuffer of the running app (read back with gfx.getpixel); audio is real REAPER renders of the
project at each stage of composition. Motion frames are time-compressed; text holds and the live-playback scene are not."""
import os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEMO = os.path.join(ROOT, "out", "demo")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "demo", "daw-in-daw-demo.mp4")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
PNG = os.path.join(DEMO, "png"); os.makedirs(PNG, exist_ok=True)

# ---- parse frames
frames = []
txt = open(os.path.join(DEMO, "frames.txt")).read().splitlines()
i = 1
while i < len(txt):
    m = re.match(r"file '(.*)'", txt[i])
    if m and i + 1 < len(txt) and txt[i + 1].startswith("duration"):
        frames.append([m.group(1), float(txt[i + 1].split()[1])]); i += 2
    else: i += 1
stages = []; play_start = None; total = None
for line in open(os.path.join(DEMO, "stages.txt")):
    p = line.split()
    if p[0] == "TOTAL": total = float(p[1])
    elif p[3] == "playstart": play_start = float(p[1])
    else: stages.append((p[0], float(p[1]), int(p[2]), p[3]))

def conv(f):
    src = f.replace(".png", ".ppm").replace("/frames/", "/frames/")
    dst = os.path.join(PNG, os.path.basename(f))
    if not os.path.exists(dst): Image.open(src).save(dst)
    return dst
with ThreadPoolExecutor(8) as ex: pngs = list(ex.map(conv, [f for f, _ in frames], chunksize=16))

# ---- time scaling: old timeline -> new timeline
old_t, t = [], 0.0
for _, d in frames: old_t.append(t); t += d
play_end_old = None
new_frames, new_t = [], 0.0
mapping = []                     # (old_start, new_start) per frame, for audio alignment
for (f, d), o, png in zip(frames, old_t, pngs):
    in_play = play_start is not None and play_start <= o < play_start + 11.8
    k = 1.0 if in_play else (0.28 if d <= 0.22 else 0.50)
    nd = max(0.04, d * k)
    mapping.append((o, new_t))
    new_frames.append((png, nd)); new_t += nd
def to_new(o):
    prev = mapping[0]
    for m in mapping:
        if m[0] > o: break
        prev = m
    return prev[1]
video_len = new_t
print(f"video length {video_len:.1f}s from {len(frames)} frames (raw {total:.1f}s)")

with open(os.path.join(DEMO, "frames_scaled.txt"), "w") as f:
    f.write("ffconcat version 1.0\n")
    for png, d in new_frames: f.write(f"file '{png}'\nduration {d:.3f}\n")
    f.write(f"file '{new_frames[-1][0]}'\n")

# ---- audio bed: looped stage renders, then the final mix from the moment the transport starts
segs = []   # (wav, start_new, end_new, loop)
st = [s for s in stages if s[3] == "stage"]
for idx, s in enumerate(st):
    start = to_new(s[1])
    end = to_new(stages[-1][1] if False else (st[idx + 1][1] if idx + 1 < len(st) else play_start))
    end = to_new(st[idx + 1][1]) if idx + 1 < len(st) else to_new(play_start)
    if end > start + 0.05: segs.append((s[0], start, end, True))
fin = [s for s in stages if s[3] == "final"][0]
ps_new = to_new(play_start)
segs.append((fin[0], ps_new, video_len, False))
inputs, filters = [], []
for n, (wav, a, b, loop) in enumerate(segs):
    if loop: inputs += ["-stream_loop", "-1"]
    inputs += ["-i", wav]
    dur = b - a
    filters.append(f"[{n + 1}:a]atrim=0:{dur:.3f},asetpts=PTS-STARTPTS,volume={0.45 if loop else 0.9},afade=t=in:d=0.04,afade=t=out:st={max(0, dur - 0.25):.3f}:d=0.25,adelay={int(a * 1000)}|{int(a * 1000)}[a{n}]")
mix = "".join(f"[a{n}]" for n in range(len(segs))) + f"amix=inputs={len(segs)}:normalize=0,alimiter=limit=0.95[aout]"
cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", os.path.join(DEMO, "frames_scaled.txt")] + inputs + [
    "-filter_complex", ";".join(filters) + ";" + mix + f";[0:v]fps=20,format=yuv420p[v]",
    "-map", "[v]", "-map", "[aout]", "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-c:a", "aac", "-b:a", "160k",
    "-t", f"{video_len:.3f}", "-movflags", "+faststart", OUT]
# the concat demuxer is input 0; audio inputs follow
subprocess.run(cmd, check=True)
print("wrote", OUT, f"({os.path.getsize(OUT)/1e6:.1f} MB)")
