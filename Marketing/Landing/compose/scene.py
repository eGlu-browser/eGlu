"""A still of the videos' scene: an iPhone capture in the phone, held in the hand, its thumb resting
at a point on the screen; and a capture of the Mac (the rect from (560, 206), two pixels a point,
the front window's corner 160 pixels in) close up beside it, running off the right and bottom.

python scene.py iphone.png mac.png hand.png bezel.png out.png [--zoom Z] [--thumb X,Y] [--no-hand]
"""
import sys

from PIL import Image, ImageDraw

iphone_png, mac_png, hand_png, bezel_png, out = sys.argv[1:6]
ZOOM = float(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 1.0
THUMB = tuple(float(v) for v in sys.argv[sys.argv.index("--thumb") + 1].split(",")) if "--thumb" in sys.argv else (34, 764)
CW, CH, BG = 2730, 1536, (17, 17, 19)
S = 0.3815
BX, BY = 380.6, 116.7
bezel = Image.open(bezel_png).convert("RGBA").resize((round(1470 * S), round(3000 * S)), Image.LANCZOS)
SX, SY = round(BX + 75 * S), round(BY + 66 * S)
SW, SH, SR = round(1320 * S), round(2868 * S), 245 * S
mask = Image.new("L", (SW * 4, SH * 4), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, SW * 4 - 1, SH * 4 - 1), radius=SR * 4, fill=255)
mask = mask.resize((SW, SH), Image.LANCZOS)
PT = SW / 402
WX, WY = 1060, 124.7

canvas = Image.new("RGBA", (CW, CH), BG + (255,))
mac = Image.open(mac_png).convert("RGB")
cx0, cy0 = int(160 - 120 / ZOOM), max(int(160 - WY / ZOOM), 0)
cx1, cy1 = min(int(160 + (CW - WX) / ZOOM) + 2, mac.width), min(int(160 + (CH - WY) / ZOOM) + 2, mac.height)
crop = mac.crop((cx0, cy0, cx1, cy1)).resize((round((cx1 - cx0) * ZOOM), round((cy1 - cy0) * ZOOM)), Image.LANCZOS)
canvas.paste(crop, (round(WX + (cx0 - 160) * ZOOM), round(WY + (cy0 - 160) * ZOOM)))
canvas.paste(Image.open(iphone_png).convert("RGB").resize((SW, SH), Image.LANCZOS), (SX, SY), mask)
canvas.alpha_composite(bezel, (round(BX), round(BY)))
if "--no-hand" not in sys.argv:
    hand = Image.open(hand_png).convert("RGBA")
    x, y = THUMB
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    layer.paste(hand, (round(0.7 * (x - 36.6) * PT), round((y - 445.5) * PT)))
    canvas.alpha_composite(layer)
canvas.convert("RGB").save(out)
print("wrote", out)
