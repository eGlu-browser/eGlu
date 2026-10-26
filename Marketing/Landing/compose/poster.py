"""A still for the site: the headline and the line under it at the top left, in ABC Areal, and the
scene (a 2730 x 1536 picture of the phone and the Mac, as the videos have them) moved down under
them, running off the bottom.

python poster.py scene.png out.png "Headline" "The line under it." [--drop D] [--scale K]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

scene_png, out, headline, line = sys.argv[1:5]
DROP = float(sys.argv[sys.argv.index("--drop") + 1]) if "--drop" in sys.argv else 380
SCALE = float(sys.argv[sys.argv.index("--scale") + 1]) if "--scale" in sys.argv else 1.0
CW, CH, BG = 2730, 1536, (17, 17, 19)
FONTS = os.path.expanduser("~/Library/Fonts")
canvas = Image.new("RGB", (CW, CH), BG)
scene = Image.open(scene_png).convert("RGB")
if SCALE != 1:
    scene = scene.resize((round(CW * SCALE), round(CH * SCALE)), Image.LANCZOS)
canvas.paste(scene, (round((CW - scene.width) / 2), round(DROP)))
d = ImageDraw.Draw(canvas)
X, Y = 392, 128  # left with the phone's body; the first line's top
head = ImageFont.truetype(FONTS + "/ABCAreal-Medium.ttf", 92)
sub = ImageFont.truetype(FONTS + "/ABCAreal-Regular.ttf", 46)
d.text((X, Y), headline, font=head, fill=(244, 244, 246), anchor="la")
d.text((X, Y + 128), line, font=sub, fill=(150, 150, 158), anchor="la")
canvas.save(out)
print("wrote", out)
