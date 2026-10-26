"""Where the take's drawn cursor really is, frame by frame: Figma's hand (white, black-edged) tracked as
the largest white blob near where it was; the script's own point where it is the plain dot or held
still. Writes [script time, x, y] in screen points, 60 a second.

python track.py take-cfr.mp4 take-script.json OFFSET out.json
"""
import json
import subprocess
import sys

import numpy as np
from scipy import ndimage

take, script, offset, out = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
steps = json.load(open(script))
mv = [s for s in steps if s["type"] == "move"]
ts = [s["t"] for s in mv]
END = steps[-1]["t"]


def planned(t):
    return np.interp(t, ts, [s["x"] for s in mv]) + 5, np.interp(t, ts, [s["y"] for s in mv]) + 92.5


W, H = 2752, 2064
p = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(offset), "-i", take, "-t", str(END + 0.05), "-f", "rawvideo",
                      "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
track, last, n = [], None, 0
while True:
    d = p.stdout.read(W * H * 3)
    if len(d) < W * H * 3:
        break
    s = n / 60
    px, py = planned(s)
    a = np.frombuffer(d, np.uint8).reshape(H, W, 3)
    found = None
    if 1.0 <= s <= END - 1.0:  # the hand's part: from the canvas to the canvas
        cx, cy = (last if last is not None else (px * 2, py * 2))
        x0, x1 = int(max(cx - 220, 0)), int(min(cx + 220, W))
        y0, y1 = int(max(cy - 220, 200)), int(min(cy + 220, H))
        win = a[y0:y1, x0:x1].astype(int)
        white = (win.min(axis=2) > 236)
        lab, k = ndimage.label(white)
        if k:
            sizes = ndimage.sum(white, lab, range(1, k + 1))
            i = int(np.argmax(sizes)) + 1
            if 150 < sizes[i - 1] < 2500:
                yy, xx = np.nonzero(lab == i)
                found = (x0 + xx.mean(), y0 + yy.mean())
    if found is None:
        found = (px * 2, py * 2)
    last = found
    track.append([round(s, 4), round(found[0] / 2, 2), round(found[1] / 2, 2)])
    n += 1
# a little smoothing: the blob's centre wobbles as the hand opens and closes
arr = np.array(track)
for c in (1, 2):
    arr[:, c] = ndimage.median_filter(arr[:, c], size=5, mode="nearest")
    arr[:, c] = ndimage.uniform_filter1d(arr[:, c], size=5, mode="nearest")
json.dump(arr.tolist(), open(out, "w"))
lag = [np.hypot(r[1] - planned(r[0])[0], r[2] - planned(r[0])[1]) for r in arr]
print(len(arr), "frames; distance from the script, points: median", round(float(np.median(lag)), 1), "max", round(float(np.max(lag)), 1))
