"""The hand's line in the site's sky blue (its dark-mode --blue), keeping the line's own alpha.

python hand-sky.py hand-smooth.png hand-sky.png
"""
import sys

import numpy as np
from PIL import Image

h = np.asarray(Image.open(sys.argv[1]).convert("RGBA")).copy()
h[..., 0], h[..., 1], h[..., 2] = 61, 155, 233
Image.fromarray(h, "RGBA").save(sys.argv[2])
