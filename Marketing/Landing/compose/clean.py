"""The generated hand without its phone: white lines on clear, the drawn phone's outline taken out
except where the thumb and the ball of the thumb lie over it.

python clean.py hand-1.png hand-lines.png
"""
import sys

import numpy as np
from PIL import Image

src, out = sys.argv[1:3]
g = np.asarray(Image.open(src).convert("L")).astype(np.float32)
alpha = np.clip((g - 24) / (230 - 24), 0, 1)

# The drawn phone: its outline's centre line, and its corners' radius.
x0, y0, x1, y1, r = 393.5, 128.5, 928.5, 1249.5, 72
h, w = g.shape
yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
cx, cy, hx, hy = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
qx, qy = np.abs(xx - cx) - hx, np.abs(yy - cy) - hy
dist = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
band = np.abs(dist) < 8

# What lies over the phone and stays: the thumb, and the ball of the thumb below it.
keep = np.zeros_like(band)
keep[700:1150, 370:540] = True
keep[630:700, 400:540] = True
alpha[band & ~keep] = 0

rgba = np.dstack([np.full_like(alpha, 255), np.full_like(alpha, 255), np.full_like(alpha, 255), alpha * 255])
Image.fromarray(rgba.astype(np.uint8), "RGBA").save(out)
print("wrote", out)
