"""Figma's own cursors on iPad, as a loop: the hairline Magic Keyboard (magic-keyboard.js, its still
parts rendered once) with the iPad take in its screen and the finger's touch on its trackpad; on the
right, the screen close up where the cursor is, so the cursor can be read.

The take: eGlu on the iPad simulator, Figma's view-only file, the pointer played from take-script.json
by the scratch build (the simulator has no trackpad). Its script starts OFFSET seconds into the take.

python ipad-cursor.py TAKE_CFR.mp4 still-dark.png take-script.json OFFSET out.mp4 [--track track.json] [--no-panel] [--still t out.png]
"""
import json
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

take, still_png, script_json, offset, out = sys.argv[1:6]
offset = float(offset)
still = None
if "--still" in sys.argv:
    k = sys.argv.index("--still")
    still = (float(sys.argv[k + 1]), sys.argv[k + 2])

FPS = 60
CW, CH, BG = 2730, 1536, (17, 17, 19)
LINE = (61, 155, 233)  # the site's sky blue, as the other videos' drawn lines

# The drawing: rendered at 4.7 pixels a viewBox unit; its box (72.7, 11.3)-(327.3, 312.7) set at (110, 60).
K = 4.7
PANEL = "--no-panel" not in sys.argv
# With the close-up, the drawing on the left; without it, in the middle.
LEFT = 110 if PANEL else (CW - 254.6 * K) / 2
OX, OY = LEFT - 72.7 * K, 60 - 11.3 * K


def vb(x, y, z):
    """The figure's projection (Cam(0, 0.5, 0.86), fitted): world millimetres to canvas pixels."""
    return OX + (200 + 0.86 * x) * K, OY + (213.776 + 0.43 * y - 0.74478 * z) * K


# The screen in the drawing, and the take in it (1376 × 1032 points, 2 pixels a point).
SX0, SY0, SX1, SY1 = OX + 85.36 * K, OY + 17.776 * K, OX + 314.64 * K, OY + 190.206 * K
PT = (SX1 - SX0) / 1376
SCR_W, SCR_H = round(1376 * PT), round(1032 * PT)
SCR_Y = round((SY0 + SY1) / 2 - SCR_H / 2)
SCR_R = 9.03 * K
WEB = (5, 92.5)  # the web view's corner on the screen, in points

# The close-up: a panel on the right, PANEL_Z pixels a point.
PX0, PY0, PW, PH, PR = 1390, 248, 1240, 1040, 30
PANEL_Z = 2.3
VIEW_W, VIEW_H = PW / PANEL_Z, PH / PANEL_Z

# The trackpad (magic-keyboard.js): the finger at u, v in -1..1 is at x = u·49, y = 177 + v·26, on z 6.4.
PAD = dict(cx=0, cy=177, hx=49, hy=26, z=6.4, r=8.5)

# ----- The timeline ----------------------------------------------------------------------------
steps = json.load(open(script_json))
moves = [(s["t"], s["x"] + WEB[0], s["y"] + WEB[1]) for s in steps if s["type"] == "move"]
presses = [(s["t"], s["type"]) for s in steps if s["type"] in ("down", "up")]
SCRIPT_END = steps[-1]["t"]
LEAD, TAIL = 0.2, 0.2
TOTAL_T = LEAD + SCRIPT_END + TAIL
TOTAL = round(TOTAL_T * FPS)
mt = np.array([m[0] for m in moves])
mx = np.array([m[1] for m in moves])
my = np.array([m[2] for m in moves])
# Where the drawn cursor really was (track.py): it trails the script while Figma redraws a dragged canvas.
if "--track" in sys.argv:
    tr = np.array(json.load(open(sys.argv[sys.argv.index("--track") + 1])))
    mt, mx, my = tr[:, 0], tr[:, 1], tr[:, 2]


def script_time(t):
    return min(max(t - LEAD, 0.0), SCRIPT_END)


def cursor(s):
    return float(np.interp(s, mt, mx)), float(np.interp(s, mt, my))


def held(s):
    down = False
    for t, kind in presses:
        if t <= s:
            down = kind == "down"
    return down


# The close-up's camera follows the cursor on a spring, run round the loop twice so it meets itself.
def camera_path():
    k, c = 60.0, 15.5
    pos = np.array(cursor(0.0)); vel = np.zeros(2)
    path = []
    for lap in range(2):
        for n in range(TOTAL):
            target = np.array(cursor(script_time(n / FPS)))
            acc = k * (target - pos) - c * vel
            vel += acc / FPS
            pos += vel / FPS
            if lap == 1:
                path.append(pos.copy())
    return path


CAM = camera_path()


def view_box(n):
    cx, cy = CAM[n]
    cx = min(max(cx, VIEW_W / 2), 1376 - VIEW_W / 2)
    cy = min(max(cy, VIEW_H / 2), 1032 - VIEW_H / 2)
    return cx - VIEW_W / 2, cy - VIEW_H / 2


# ----- Pictures --------------------------------------------------------------------------------
def tinted(png):
    """The drawing's lines in the sky blue: their brightness over the dark ground, as alpha."""
    a = np.asarray(Image.open(png).convert("L")).astype(np.float32)
    alpha = np.clip((a - 9) / (93 - 9), 0, 1) * 0.95
    rgba = np.zeros(a.shape + (4,), np.uint8)
    rgba[..., :3] = LINE
    rgba[..., 3] = (alpha * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


lines = tinted(still_png)
lines_layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
lines_layer.alpha_composite(lines.crop((max(0, -round(OX)), 0, lines.width, lines.height)), (max(0, round(OX)), round(OY)))


def rounded_mask(w, h, r, ss=4):
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius=r * ss, fill=255)
    return m.resize((w, h), Image.LANCZOS)


screen_mask = rounded_mask(SCR_W, SCR_H, round(SCR_R))
panel_mask = rounded_mask(PW, PH, PR)


class Reader:
    def __init__(self, path, start):
        self.size = (2752, 2064)
        self.start = start
        self.p = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(start), "-i", path, "-f", "rawvideo",
                                   "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
        self.index, self.frame = -1, None

    def at(self, t):
        want = max(round((t - self.start) * FPS), 0)
        while self.index < want:
            data = self.p.stdout.read(self.size[0] * self.size[1] * 3)
            if len(data) < self.size[0] * self.size[1] * 3:
                break
            self.frame = Image.frombytes("RGB", self.size, data)
            self.index += 1
        return self.frame


SS = 3


def marks(n, s):
    """The finger's touch (bright), its middle, a fill while it holds the click; a burst as it clicks."""
    big = Image.new("RGBA", (CW * SS // 2, CH * SS // 2), (0, 0, 0, 0))
    g = ImageDraw.Draw(big)
    q = SS / 2
    x, y = cursor(s)
    u, v = x / 688 - 1, y / 516 - 1
    px, py = PAD["cx"] + u * PAD["hx"], PAD["cy"] + v * PAD["hy"]
    cx, cy = vb(px, py, PAD["z"])
    rx, ry = PAD["r"] * 0.86 * K, PAD["r"] * 0.43 * K
    if held(s):
        g.ellipse(((cx - rx) * q, (cy - ry) * q, (cx + rx) * q, (cy + ry) * q), fill=LINE + (60,))
    g.ellipse(((cx - rx) * q, (cy - ry) * q, (cx + rx) * q, (cy + ry) * q), outline=LINE + (255,), width=round(4.6 * q))
    d = 1.4 * K
    g.ellipse(((cx - d) * q, (cy - d) * q, (cx + d) * q, (cy + d) * q), fill=LINE + (170,))
    for t, kind in presses:
        k = s - t
        if kind == "down" and 0 <= k < 0.4:
            e = 1 - (1 - k / 0.4) ** 3
            alpha = round(240 * (1 - max(0, (k / 0.4 - 0.35) / 0.65)))
            for a in (-150, -90, -30):
                c_, s_ = np.cos(np.radians(a)), np.sin(np.radians(a))
                r0, r1 = 1.25 + 0.5 * e, 1.6 + 0.9 * e
                g.line(((cx + c_ * rx * r0) * q, (cy + s_ * ry * r0 * 1.6) * q, (cx + c_ * rx * r1) * q, (cy + s_ * ry * r1 * 1.6) * q),
                       fill=LINE + (alpha,), width=round(4.2 * q))
    if not PANEL:
        return big.resize((CW, CH), Image.LANCZOS)
    # the close-up's place on the small screen
    vx, vy = view_box(n)
    x0, y0 = SX0 + vx * PT, SCR_Y + vy * PT
    g.rounded_rectangle((x0 * q, y0 * q, (x0 + VIEW_W * PT) * q, (y0 + VIEW_H * PT) * q), radius=8 * q,
                        outline=LINE + (230,), width=round(3 * q))
    g.rounded_rectangle((PX0 * q, PY0 * q, (PX0 + PW) * q, (PY0 + PH) * q), radius=PR * q, outline=LINE + (230,), width=round(3.5 * q))
    return big.resize((CW, CH), Image.LANCZOS)


reader = Reader(take, max(offset - 0.1, 0))
back = Image.new("RGB", (CW, CH), BG)


def frame_at(n):
    t = n / FPS
    s = script_time(t)
    shot = reader.at(offset + s)
    canvas = back.copy()
    canvas.paste(shot.resize((SCR_W, SCR_H), Image.LANCZOS), (round(SX0), SCR_Y), screen_mask)
    if PANEL:
        vx, vy = view_box(n)
        crop = shot.crop((round(vx * 2), round(vy * 2), round((vx + VIEW_W) * 2), round((vy + VIEW_H) * 2)))
        canvas.paste(crop.resize((PW, PH), Image.LANCZOS), (PX0, PY0), panel_mask)
    canvas = canvas.convert("RGBA")
    canvas.alpha_composite(lines_layer)
    canvas.alpha_composite(marks(n, s))
    return canvas.convert("RGB")


print(f"loop {TOTAL_T:.2f} s, {TOTAL} frames; screen {SCR_W}×{SCR_H} at {round(SX0)},{SCR_Y}; {PT:.3f} px/pt")
writer = None
if not still:
    writer = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{CW}x{CH}",
                               "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
                               "-movflags", "+faststart", out], stdin=subprocess.PIPE)
for n in range(TOTAL):
    if still:
        if n < round(still[0] * FPS):
            reader.at(offset + script_time(n / FPS))
            continue
        frame_at(n).save(still[1])
        break
    writer.stdin.write(frame_at(n).tobytes())
reader.p.kill()
if writer:
    writer.stdin.close()
    writer.wait()
