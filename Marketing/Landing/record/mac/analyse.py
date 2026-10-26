"""Per frame of a take: how much the area round the pointer's start changed, and how bright each
of the first row's tiles is, to find when the pointer left and when each tile lit."""
import subprocess, sys
import numpy as np
mov, pts_file = sys.argv[1:3]
W, H = 2880, 1960
pts = [float(l) for l in open(pts_file) if l.strip()]
r = subprocess.Popen(["ffmpeg", "-v", "error", "-i", mov, "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                     stdout=subprocess.PIPE)
tiles = {"HN": (250, 372), "IG": (416, 372), "G": (582, 372)}
prev = None
i = 0
while True:
    b = r.stdout.read(W * H * 3)
    if len(b) < W * H * 3: break
    f = np.frombuffer(b, np.uint8).reshape(H, W, 3).astype(np.int16)
    start = f[900:1000, 1360:1460]
    d = 0 if prev is None else int(np.abs(start - prev).sum() // 1000)
    prev = start
    vals = " ".join(f"{k}={f[y-30:y+30, x-60:x+60].mean():5.1f}" for k, (x, y) in tiles.items())
    print(f"{i:4d} {pts[i]:6.3f} startdiff={d:6d} {vals}")
    i += 1
