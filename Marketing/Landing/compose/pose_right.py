import sys
import numpy as np
from PIL import Image, ImageDraw
B = sys.argv[1] if len(sys.argv) > 1 else 'promax-blue.png'  # Marketing/AppStore/source/bezels/promax-blue.png
CW, CH, BG = 1300, 1536, (17, 17, 19)
S = 0.3815; BX, BY = 380.6, 116.7
bezel = Image.open(B).convert("RGBA").resize((round(1470 * S), round(3000 * S)), Image.LANCZOS)
SX, SY = round(BX + 75 * S), round(BY + 66 * S)
SW, SH = round(1320 * S), round(2868 * S)
PT = SW / 402
MID = BX + 1470 * S / 2
hand = Image.open('hand-smooth.png').convert('RGBA').transpose(Image.FLIP_LEFT_RIGHT)
# On a canvas as wide as CW, mirrored about the phone's middle: its x' = 2 MID - x.
right = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
right.paste(hand, (round(2 * MID - 1024), 0))
a = np.asarray(right).astype(np.float32)
fy = np.clip((1535 - np.arange(CH)) / 260, 0, 1)
fx = np.clip((1000 - np.arange(CW)) / 70, 0, 1)   # fades past the phone's right edge
sm = lambda f: f * f * (3 - 2 * f)
a[..., 3] *= sm(fy)[:, None] * sm(fx)[None, :]
PADR = (2 * MID - (SX + 36.6 * PT), SY + 445.5 * PT)  # the mirrored pad, on the canvas
print('right pad pt', (PADR[0] - SX) / PT)
screen = Image.open(sys.argv[1]).convert('RGB').resize((SW, SH), Image.LANCZOS)
outs = []
for (x, y) in [(342, 250), (342, 330)]:
    c = Image.new('RGBA', (CW, CH), BG + (255,))
    c.paste(screen, (SX, SY)); c.alpha_composite(bezel, (round(BX), round(BY)))
    T = (SX + x * PT, SY + y * PT)
    dx, dy = T[0] - PADR[0], T[1] - PADR[1]
    layer = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
    # Shifting the faded picture moves its fade too: fade after the shift instead.
    shifted = Image.new('RGBA', (CW, CH), (0, 0, 0, 0)); shifted.paste(right, (round(dx), round(dy)))
    b = np.asarray(shifted).astype(np.float32)
    b[..., 3] *= sm(fx)[None, :]
    c.alpha_composite(Image.fromarray(b.astype(np.uint8), 'RGBA'))
    d = ImageDraw.Draw(c); d.ellipse((T[0] - 6, T[1] - 6, T[0] + 6, T[1] + 6), fill=(255, 40, 40, 255))
    d.line([(1060, 0), (1060, CH)], fill=(80, 80, 200, 255), width=2)
    outs.append(c.convert('RGB').resize((650, 768)))
s = Image.new('RGB', (1300, 768)); [s.paste(o, (i * 650, 0)) for i, o in enumerate(outs)]
s.save(sys.argv[2])
