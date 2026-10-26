"""Covers the Mac share menu's row of suggested Messages contacts (names of real people) with the
menu's own material: each pixel row filled from its colour at the row's left edge to its colour at
the right, between the separators above and below it. Full-size capture pixels."""
import numpy as np
from PIL import Image

X0, X1, Y0, Y1 = 2040, 2506, 952, 1101


def redact(im):
    a = np.asarray(im).astype(np.float32).copy()
    left = a[Y0:Y1, X0 + 1:X0 + 7].mean(axis=1)
    right = a[Y0:Y1, X1:X1 + 8].mean(axis=1)
    k = np.linspace(0, 1, X1 - X0)[None, :, None]
    a[Y0:Y1, X0:X1] = left[:, None, :] * (1 - k) + right[:, None, :] * k
    return Image.fromarray(a.astype(np.uint8), "RGB")
