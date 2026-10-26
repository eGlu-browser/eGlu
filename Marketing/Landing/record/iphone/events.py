"""Per segment: when the switch changes, when the screen moves a lot (list opening, sheet moving).
Frames at 30 fps, downscaled."""
import subprocess, sys
import numpy as np
f = sys.argv[1]
W, H = 201, 437
p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", f, "-vf", f"fps=30,scale={W}:{H}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
prev = None; i = 0; rows = []
while True:
    b = p.stdout.read(W * H * 3)
    if len(b) < W * H * 3: break
    a = np.frombuffer(b, np.uint8).reshape(H, W, 3).astype(int)
    # The Instagram switch: (342, 250) pt -> at this scale x 171, y 125.
    sw = a[118:132, 160:182]
    green = int(((sw[..., 1] > 150) & (sw[..., 0] < 120)).sum())
    d = 0 if prev is None else int(np.abs(a - prev).mean() * 100)
    rows.append((i / 30, d, green))
    prev = a; i += 1
for t, d, g in rows:
    if d > 30 or (rows and abs(g - rows[0][2]) > 0 and t < 99):
        print(f"{t:6.2f} diff={d:5d} green={g}")
print("frames", i)
