"""The hand's lines redrawn as smooth vectors: each line's centre traced, short stray bits dropped,
pieces that nearly meet joined, the centre smoothed, and drawn again at one even width.

python vectorize.py hand-lines.png hand-smooth.png [--smooth S] [--debug out.png]
"""
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import interpolate
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import shortest_path
from skimage.measure import label
from skimage.morphology import skeletonize

src, out = sys.argv[1:3]
SMOOTH = float(sys.argv[sys.argv.index("--smooth") + 1]) if "--smooth" in sys.argv else 6.0
alpha = np.asarray(Image.open(src))[..., 3].astype(np.float32) / 255
ink = alpha > 0.35
skel = skeletonize(ink)
WIDTH = alpha.sum() / max(skel.sum(), 1)  # the drawing's stroke width
print(f"stroke width {WIDTH:.2f}")


def ordered(pixels):
    """A component's pixels as one path: the longest shortest path through them."""
    idx = {p: i for i, p in enumerate(pixels)}
    rows, cols, w = [], [], []
    for (y, x), i in idx.items():
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                j = idx.get((y + dy, x + dx))
                if j is not None and j != i:
                    rows.append(i); cols.append(j); w.append(np.hypot(dy, dx))
    g = csr_matrix((w, (rows, cols)), shape=(len(pixels), len(pixels)))
    d0 = shortest_path(g, indices=0)
    a = int(np.argmax(np.where(np.isfinite(d0), d0, -1)))
    da, pred = shortest_path(g, indices=a, return_predecessors=True)
    b = int(np.argmax(np.where(np.isfinite(da), da, -1)))
    path, k = [], b
    while k != a and k >= 0:
        path.append(pixels[k]); k = pred[k]
    path.append(pixels[a])
    return np.array([(x, y) for y, x in path], np.float64)


labels = label(skel, connectivity=2)
paths = []
for n in range(1, labels.max() + 1):
    ys, xs = np.nonzero(labels == n)
    if len(ys) < 30:
        continue  # a stray bit, left from the phone taken out of the drawing
    paths.append(ordered(list(zip(ys, xs))))

# Pieces whose ends nearly meet, heading on from one another, are one line.
def join(paths, gap=22):
    changed = True
    while changed:
        changed = False
        for i in range(len(paths)):
            for j in range(len(paths)):
                if i == j:
                    continue
                for a in (paths[i], paths[i][::-1]):
                    for b in (paths[j], paths[j][::-1]):
                        if np.hypot(*(a[-1] - b[0])) < gap:
                            da = a[-1] - a[max(len(a) - 12, 0)]
                            db = b[min(11, len(b) - 1)] - b[0]
                            cos = da @ db / (np.linalg.norm(da) * np.linalg.norm(db) + 1e-9)
                            if cos > 0.5:
                                merged = np.vstack([a, b])
                                paths = [p for k, p in enumerate(paths) if k not in (i, j)] + [merged]
                                changed = True
                                break
                    if changed: break
                if changed: break
            if changed: break
    return paths


paths = join(paths)
print("lines", len(paths), [len(p) for p in paths])


def smooth(p):
    # Every 3 px along the line, then a smoothing spline through them.
    seg = np.hypot(*np.diff(p, axis=0).T)
    t = np.concatenate([[0], np.cumsum(seg)])
    keep = np.concatenate([[True], seg > 0])
    p, t = p[keep], t[keep]
    n = max(int(t[-1] / 3), 4)
    tt = np.linspace(0, t[-1], n)
    q = np.column_stack([np.interp(tt, t, p[:, 0]), np.interp(tt, t, p[:, 1])])
    tck, _ = interpolate.splprep(q.T, s=SMOOTH * len(q), k=3)
    x, y = interpolate.splev(np.linspace(0, 1, n * 4), tck)
    return np.column_stack([x, y])


SS = 4
h, w = alpha.shape
big = Image.new("L", (w * SS, h * SS), 0)
d = ImageDraw.Draw(big)
for p in paths:
    q = smooth(p) * SS
    lw = round(WIDTH * SS)
    d.line([tuple(v) for v in q], fill=255, width=lw, joint="curve")
    for v in (q[0], q[-1]):
        d.ellipse((v[0] - lw / 2, v[1] - lw / 2, v[0] + lw / 2, v[1] + lw / 2), fill=255)
a = big.resize((w, h), Image.LANCZOS)
rgba = Image.merge("RGBA", (Image.new("L", (w, h), 255),) * 3 + (a,))
rgba.save(out)
if "--debug" in sys.argv:
    dbg = Image.new("RGB", (w, h), (20, 20, 24))
    dbg.paste((255, 255, 255), mask=a)
    dbg.crop((0, 560, 600, 1536)).save(sys.argv[sys.argv.index("--debug") + 1])
print("wrote", out)
