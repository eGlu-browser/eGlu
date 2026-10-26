"""Handoff as a loop: the iPhone in the generated hand, then the file it hands over.

P  the iPhone, in the middle: the right thumb opens the page menu, taps Send to App; the sheet reads
   the page (Apple Intelligence; its long wait on the simulator cut short), says it is ready; the thumb
   taps Send to App and the share sheet comes up with the page's Markdown file.
D  the phone moves left and the file comes in on the right, set in Paper Mono as the text it is:
   the real file the take wrote, its address shown as the demo's own; it scrolls a little, then the
   two go back to the start.

python handoff.py PHONE_MOV hand.png bezel.png FILE.md 0 out.mp4 [--still t out.png]
"""
import subprocess
import os
import sys

import numpy as np

from PIL import Image, ImageDraw, ImageFont

# The drawn lines (hand, tap lines, press arc) in the site's sky blue, its dark-mode --blue.
LINE = (61, 155, 233)

phone_mov, hand_png, bezel_png, doc_md, _unused, out = sys.argv[1:7]
still = None
if "--still" in sys.argv:
    k = sys.argv.index("--still")
    still = (float(sys.argv[k + 1]), sys.argv[k + 2])

FPS = 60
CW, CH, BG = 2730, 1536, (17, 17, 19)

# The phone, as in mockup3.py.
S = 0.3815
BX, BY = 380.6, 116.7
bezel = Image.open(bezel_png).convert("RGBA").resize((round(1470 * S), round(3000 * S)), Image.LANCZOS)
SX, SY = round(BX + 75 * S), round(BY + 66 * S)
SW, SH, SR = round(1320 * S), round(2868 * S), 245 * S
mask = Image.new("L", (SW * 4, SH * 4), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, SW * 4 - 1, SH * 4 - 1), radius=SR * 4, fill=255)
mask = mask.resize((SW, SH), Image.LANCZOS)
PT = SW / 402
MID = BX + 1470 * S / 2


def screen_pt(x, y):
    return SX + x * PT, SY + y * PT


# The hands: the drawing's left hand, its wrist fading out where it leaves the drawing; and the same
# mirrored about the phone's middle, a right hand on its right edge, fading out past the phone.
def smoothstep(f):
    f = np.clip(f, 0, 1)
    return f * f * (3 - 2 * f)


left = Image.open(hand_png).convert("RGBA")
_a = np.asarray(left).astype(np.float32)
_a[..., 3] *= smoothstep((1535 - np.arange(_a.shape[0])) / 260)[:, None] * smoothstep(np.arange(_a.shape[1]) / 130)[None, :]
left = Image.fromarray(_a.astype(np.uint8), "RGBA")
PAD_L = np.array(screen_pt(36.6, 445.5))  # the left thumb's pad, as drawn
right = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
right.paste(left.transpose(Image.FLIP_LEFT_RIGHT), (round(2 * MID - 1024), 0))
PAD_R = np.array([2 * MID - PAD_L[0], PAD_L[1]])
RIGHT_FADE = smoothstep((1000 - np.arange(CW)) / 70)[None, :]


def ease_out(k):
    k = min(max(k, 0), 1)
    return 1 - (1 - k) ** 3


def smooth(k):
    k = min(max(k, 0), 1)
    return k * k * (3 - 2 * k)


def hand_layer(side, touch, presence, arriving):
    """The hand ("left" or "right") with its pad on touch (screen points), coming in or going out:
    presence 0..1, from below and outside when it is less than 1."""
    x, y = touch
    e = ease_out(presence) if arriving else 1 - ease_out(1 - presence)
    away = 1 - e
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    if side == "left":
        # Along the phone's edge most of the way, so its edge stays on the bezel (mockup3.py).
        dx, dy = 0.7 * (x - 36.6) * PT, (y - 445.5) * PT
        layer.paste(left, (round(dx - 50 * away), round(dy + 60 * away)))
        arr = np.asarray(layer).astype(np.float32)
    else:
        tx, ty = screen_pt(x, y)
        layer.paste(right, (round(tx - PAD_R[0] + 50 * away), round(ty - PAD_R[1] + 60 * away)))
        arr = np.asarray(layer).astype(np.float32)
        arr[..., 3] *= RIGHT_FADE
    arr[..., 3] *= e
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


# The marks: an arc that fills round the thumb while it holds, lines that burst out at a tap.
SS = 3
ARC = 120
BURST = 0.4


def draw_burst(g, cx, cy, k, radius, length, angles):
    u = k / BURST
    if not 0 <= u < 1:
        return
    inner = radius + length * 0.9 * ease_out(u)
    outer = radius + length * 0.35 + length * 1.1 * ease_out(min(u * 1.6, 1))
    alpha = round(240 * (1 - smooth((u - 0.35) / 0.65)))
    w = round(3.2 * SS)
    for a in angles:
        c, s = np.cos(np.radians(a)), np.sin(np.radians(a))
        p0 = ((cx + c * inner) * SS, (cy + s * inner) * SS)
        p1 = ((cx + c * outer) * SS, (cy + s * outer) * SS)
        g.line([p0, p1], fill=(*LINE, alpha), width=w)
        for q in (p0, p1):
            g.ellipse((q[0] - w / 2, q[1] - w / 2, q[0] + w / 2, q[1] + w / 2), fill=(*LINE, alpha))


def draw_arc(g, cx, cy, fill, fade):
    cx, cy, r = cx * SS, cy * SS, ARC * SS
    w = round(3.2 * SS)
    box = (cx - r, cy - r, cx + r, cy + r)
    g.ellipse(box, outline=(*LINE, round(60 * fade)), width=w)
    if fill > 0:
        end = -90 + 360 * fill
        g.arc(box, -90, end, fill=(*LINE, round(240 * fade)), width=w)
        for a in (-90, end):
            ex, ey = cx + (r - w / 2) * np.cos(np.radians(a)), cy + (r - w / 2) * np.sin(np.radians(a))
            g.ellipse((ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2), fill=(*LINE, round(240 * fade)))


def marks_layer(arcs, bursts):
    if not arcs and not bursts:
        return None
    pts = [(a[0], a[1]) for a in arcs] + [(b[0], b[1]) for b in bursts]
    x0 = int(min(p[0] for p in pts)) - 200
    y0 = int(min(p[1] for p in pts)) - 200
    x1 = int(max(p[0] for p in pts)) + 200
    y1 = int(max(p[1] for p in pts)) + 200
    big = Image.new("RGBA", ((x1 - x0) * SS, (y1 - y0) * SS), (0, 0, 0, 0))
    g = ImageDraw.Draw(big)
    for cx, cy, fill, fade in arcs:
        draw_arc(g, cx - x0, cy - y0, fill, fade)
    for cx, cy, k, radius, length, angles in bursts:
        draw_burst(g, cx - x0, cy - y0, k, radius, length, angles)
    return big.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0)


# ----- The timeline ---------------------------------------------------------------------------
# The phone: loop time against the take's time, piecewise straight. Where two keys share a loop time
# the take jumps (a wait cut out); CUTS are the jumps that cross-fade, the rest are cut between frames
# that are the same.
MORE, MENU_SEND, SHEET_SEND = (367, 763), (342, 745), (201, 784)
KEYS = [
    (0.00, 2.30), (1.35, 3.65),          # the thumb comes in; taps the menu button (the take's 3.65)
    (3.05, 5.35),                        # Send to App in the menu
    (5.70, 8.00),                        # the sheet comes up and reads the page...
    (5.70, 113.45),                      # ...the rest of the model's wait cut (cross-faded)
    (7.45, 115.20),                      # ready: Apple Intelligence's step checked
    (8.00, 115.75), (8.00, 124.00),      # the ready sheet held (the same frames)
    (8.55, 124.55),                      # the thumb taps Send to App
    (9.25, 125.25), (9.25, 129.00),      # the share sheet's wait cut (the page, the same frames)
    (10.12, 129.82),                     # the share sheet is up
]
CUTS = [(5.70, 0.25)]
TAPS = [(1.35, MORE), (3.05, MENU_SEND), (8.55, SHEET_SEND)]
PHONE_END = 10.12
XF = 0.35

# The phone sits in the middle until the share sheet is up, then moves left as the file comes in.
CENTRE_DX = round(CW / 2 - MID)
MOVE_IN = (10.15, 10.95)
DOC_IN = (10.6, 11.4)
SCROLL = (12.4, 15.8)
DOC_OUT = (16.3, 16.8)
MOVE_OUT = (16.7, 17.4)
TOTAL_T = MOVE_OUT[1] + XF
TOTAL = round(TOTAL_T * FPS)
print(f"loop {TOTAL_T:.2f} s; phone 0-{PHONE_END:.2f}; file {DOC_IN[0]:.2f}-{DOC_OUT[1]:.2f}")


def phone_dx(t):
    if t < MOVE_OUT[0]:
        return CENTRE_DX * (1 - smooth((t - MOVE_IN[0]) / (MOVE_IN[1] - MOVE_IN[0])))
    return CENTRE_DX * smooth((t - MOVE_OUT[0]) / (MOVE_OUT[1] - MOVE_OUT[0]))


def segments():
    """The keys as straight runs: (loop t0, t1, take t0, t1)."""
    out = []
    for (a, sa), (b, sb) in zip(KEYS, KEYS[1:]):
        if b > a:
            out.append((a, b, sa, sb))
    return out


SEGS = segments()


def source_time(t):
    for a, b, sa, sb in SEGS:
        if a <= t < b:
            return sa + (t - a) / (b - a) * (sb - sa)
    return KEYS[-1][1] if t >= KEYS[-1][0] else KEYS[0][1]


# ----- Frames -----------------------------------------------------------------------------------
class Reader:
    """A recording's frames in order, at 60 a second, scaled; the one at a time asked for."""

    def __init__(self, path, size, vf_extra="", start=0.0):
        self.size, self.start = size, start
        vf = f"fps={FPS}" + (f",{vf_extra}" if vf_extra else "") + f",scale={size[0]}:{size[1]}:flags=lanczos"
        args = ["ffmpeg", "-v", "error"] + (["-ss", str(start)] if start else []) + ["-i", path, "-vf", vf,
                                                                                     "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
        self.p = subprocess.Popen(args, stdout=subprocess.PIPE)
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

    def close(self):
        self.p.kill()



class Seeker:
    """Frames of a recording at any take times in order, re-opening it after a jump forward."""

    def __init__(self, path, size):
        self.path, self.size, self.r = path, size, None

    def at(self, s):
        if self.r is None or s < self.r.start + self.r.index / FPS - 1e-6 or s > self.r.start + (self.r.index + 1) / FPS + 2.0:
            if self.r:
                self.r.close()
            self.r = Reader(self.path, self.size, start=max(s - 0.02, 0))
        return self.r.at(s)


phone = Seeker(phone_mov, (SW, SH))
phone_cut = Seeker(phone_mov, (SW, SH))
first_frame = Reader(phone_mov, (SW, SH), start=KEYS[0][1]).at(KEYS[0][1]).copy()

# ----- The file -----------------------------------------------------------------------------------
FONTS = os.path.expanduser("~/Library/Fonts")
DOC_SIZE, DOC_LEAD = 40, 64
REG = ImageFont.truetype(f"{FONTS}/PaperMono-Regular.otf", DOC_SIZE)
BOLD = ImageFont.truetype(f"{FONTS}/PaperMono-SemiBold.otf", DOC_SIZE)
LABEL = ImageFont.truetype(f"{FONTS}/PaperMono-Medium.otf", 30)
INK, MARK, SHEET = (22, 32, 43), (0, 94, 149), (244, 246, 250)  # the site's light ink, --blue-ink, paper
DOC_X, DOC_Y, DOC_W, PAD = 1110, 168, 1480, 84
COLS = int((DOC_W - 2 * PAD) / REG.getlength("M"))
DEMO_SOURCE = ("http://localhost:8766/jobs/mossgrove/senior-product-designer.html",
               "https://mossgrove.example/jobs/senior-product-designer")


def wrap(text, width):
    words, lines, line = text.split(" "), [], ""
    for w in words:
        if line and len(line) + 1 + len(w) > width:
            lines.append(line)
            line = w
        else:
            line = f"{line} {w}" if line else w
    return lines + [line]


def doc_runs(md):
    """Each printed line as runs of (text, bold, marked): Markdown's own marks in blue."""
    out = []
    for raw in md.replace(*DEMO_SOURCE).split("\n"):
        if raw.startswith("#"):
            hashes, _, rest = raw.partition(" ")
            for i, piece in enumerate(wrap(rest, COLS - len(hashes) - 1)):
                out.append([(hashes + " " if i == 0 else " " * (len(hashes) + 1), False, True), (piece, True, False)])
        elif raw.startswith("- "):
            for i, piece in enumerate(wrap(raw[2:], COLS - 2)):
                out.append([("- " if i == 0 else "  ", False, True), (piece, False, False)])
        elif raw.startswith("**"):
            _, head, rest = raw.split("**", 2)
            out.append([("**", False, True), (head, True, False), ("**", False, True)])
            out.extend([[(p, False, False)] for p in wrap(rest.strip(), COLS)])
        elif raw.startswith("Source: "):
            out.append([("Source: ", False, False)])
            out.extend([[(raw[8:], False, True)]])
        elif not raw.strip():
            out.append([])
        else:
            out.extend([[(p, False, False)] for p in wrap(raw, COLS)])
    return out


def draw_sheet():
    lines = doc_runs(open(doc_md, encoding="utf-8").read())
    h = PAD + len(lines) * DOC_LEAD + PAD
    sheet = Image.new("RGBA", (DOC_W, h), (0, 0, 0, 0))
    g = ImageDraw.Draw(sheet)
    g.rounded_rectangle((0, 0, DOC_W - 1, h + 40), radius=26, fill=SHEET + (255,))
    for i, runs in enumerate(lines):
        x, y = PAD, PAD + i * DOC_LEAD
        for text, bold, marked in runs:
            font = BOLD if bold else REG
            g.text((x, y), text, font=font, fill=MARK if marked else INK)
            x += REG.getlength("M") * len(text)
    return sheet


SHEET_IMG = draw_sheet()
TITLE = open(doc_md, encoding="utf-8").readline().lstrip("# ").strip() + ".md"
VISIBLE = CH - DOC_Y
SCROLL_BY = min(9 * DOC_LEAD, SHEET_IMG.height - VISIBLE)


def doc_layer(t):
    """The file at time t, or None: its name above it, coming in from the right and going out again."""
    if t < DOC_IN[0] or t >= DOC_OUT[1]:
        return None
    k_in = smooth((t - DOC_IN[0]) / (DOC_IN[1] - DOC_IN[0]))
    k_out = smooth((t - DOC_OUT[0]) / (DOC_OUT[1] - DOC_OUT[0]))
    k = k_in * (1 - k_out)
    scroll = SCROLL_BY * smooth((t - SCROLL[0]) / (SCROLL[1] - SCROLL[0]))
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    view = SHEET_IMG.crop((0, round(scroll), DOC_W, round(scroll) + VISIBLE))
    dx = round(140 * (1 - k))
    layer.alpha_composite(view, (DOC_X + dx, DOC_Y))
    g = ImageDraw.Draw(layer)
    g.text((DOC_X + dx + 6, DOC_Y - 62), TITLE, font=LABEL, fill=(150, 160, 172, 255))
    g.text((DOC_X + dx + DOC_W - 6, DOC_Y - 62), "3 KB", font=LABEL, fill=(110, 118, 128, 255), anchor="ra")
    arr = np.asarray(layer).astype(np.float32)
    arr[..., 3] *= k
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def phone_screen(t):
    s = source_time(t)
    frame = phone.at(s)
    for at, length in CUTS:
        if at - length <= t < at:
            # The frame the cut lands on, faded in over the last of the run before it.
            before = [k for k in KEYS if k[0] == at]
            land = phone_cut.at(before[-1][1] - (at - t) * 0)
            return Image.blend(frame, land, smooth((t - (at - length)) / length))
    return frame


def tap_groups():
    """The taps in runs the thumb stays for: it leaves when the next tap is more than 2.5 s away."""
    groups = [[TAPS[0]]]
    for tap in TAPS[1:]:
        (groups[-1].append(tap) if tap[0] - groups[-1][-1][0] < 2.5 else groups.append([tap]))
    return groups


GROUPS = tap_groups()


def hands_and_marks(t):
    hands, arcs, bursts = [], [], []
    # The right thumb: in before a run's first tap, from tap to tap, out after its last.
    for taps in GROUPS:
        come, leave = taps[0][0] - 0.75, taps[-1][0] + 0.12
        if not come <= t < leave + 0.4:
            continue
        # Where its pad is: resting short of the next target, on it at the tap, then moving on.
        touch = None
        for i, (tt, p) in enumerate(taps):
            prev_t, prev_p = (taps[i - 1][0], taps[i - 1][1]) if i else (come, None)
            if t < tt + 0.12 or i == len(taps) - 1:
                rest = (p[0] + 10, p[1] + 14)
                if prev_p is None or t >= prev_t + 0.12 + 0.5:
                    k = smooth((t - (tt - 0.14)) / 0.14)
                    touch = (rest[0] + (p[0] - rest[0]) * k, rest[1] + (p[1] - rest[1]) * k)
                else:
                    k = smooth((t - (prev_t + 0.12)) / 0.5)
                    touch = (prev_p[0] + (rest[0] - prev_p[0]) * k, prev_p[1] + (rest[1] - prev_p[1]) * k)
                break
        if t < come + 0.5:
            hands.append(("right", touch, (t - come) / 0.5, True))
        elif t < leave:
            hands.append(("right", touch, 1.0, True))
        else:
            hands.append(("right", touch, 1 - (t - leave) / 0.35, False))
    for tt, p in TAPS:
        if 0 <= t - tt < BURST:
            cx, cy = screen_pt(*p)
            bursts.append((cx, cy, t - tt, 46, 22, (-165, -120, -75)))
    return hands, arcs, bursts


back = Image.new("RGBA", (CW, CH), BG + (255,))


def render(t):
    canvas = back.copy()
    phone_layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    phone_layer.paste(phone_screen(t).resize((SW, SH)), (SX, SY), mask)
    phone_layer.alpha_composite(bezel, (round(BX), round(BY)))
    hands, arcs, bursts = hands_and_marks(t)
    mark = marks_layer(arcs, bursts)
    if mark:
        phone_layer.alpha_composite(mark[0], mark[1])
    for side, touch, presence, arriving in hands:
        if presence > 0:
            phone_layer.alpha_composite(hand_layer(side, touch, min(presence, 1), arriving))
    dx = round(phone_dx(t))
    canvas.alpha_composite(phone_layer.crop((0, 0, CW - dx, CH)), (dx, 0))
    doc = doc_layer(t)
    if doc:
        canvas.alpha_composite(doc)
    return canvas.convert("RGB")


FIRST = None


def frame_at(t):
    """The loop's last XF seconds fade into its first frame."""
    global FIRST
    if FIRST is None:
        FIRST = render(0.0)
    if t >= TOTAL_T - XF:
        return Image.blend(render(t), FIRST, smooth((t - (TOTAL_T - XF)) / (XF - 1 / FPS)))
    return render(t)


writer = None
if not still:
    writer = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{CW}x{CH}",
                               "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
                               "-movflags", "+faststart", out], stdin=subprocess.PIPE)
for n in range(TOTAL):
    t = n / FPS
    if still:
        frame_at(still[0]).save(still[1])
        break
    writer.stdin.write(frame_at(t).tobytes())
if writer:
    writer.stdin.close()
    writer.wait()
print("frames", TOTAL)
