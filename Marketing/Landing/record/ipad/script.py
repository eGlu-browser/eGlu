"""The iPad Figma take's pointer, in the web view's points, at 60 steps a second.

python script.py OUT.json  (also prints the plan: each move and press, for the video's finger)
"""
import json
import math
import sys

HZ = 60
steps, plan = [], []


def min_jerk(u):
    u = min(max(u, 0), 1)
    return u * u * u * (10 - 15 * u + 6 * u * u)


def glide(a, b, t0, dur, bow=0.0, held=False):
    n = max(int(dur * HZ), 1)
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = max(math.hypot(dx, dy), 1)
    for i in range(1, n + 1):
        s = min_jerk(i / n)
        side = bow * math.sin(math.pi * s)
        steps.append({"t": round(t0 + i / HZ, 4), "x": round(a[0] + dx * s - dy / length * side, 2),
                      "y": round(a[1] + dy * s + dx / length * side, 2), "type": "move"})
    plan.append(("glide", t0, dur, a, b, held))


def hold(p, t0, t1):
    t = t0
    while t < t1:
        steps.append({"t": round(t, 4), "x": p[0], "y": p[1], "type": "move"})
        t += 0.25


def press(kind, p, t):
    steps.append({"t": t, "x": p[0], "y": p[1], "type": kind})
    plan.append((kind, t, p))


A = (26, 470)            # on the tool rail: the iPadOS dot
RECT, HAND = (26, 172), (26, 365)   # the Rectangle and Hand tools
P1, P2, P3 = (760, 230), (1010, 400), (1060, 460)   # the rectangle drawn, then its corner pulled
M = (910, 345)           # inside it: the move cursor
Q, Q2 = (640, 650), (520, 560)      # the canvas grabbed and panned


def click(p, t):
    press("down", p, t)
    press("up", p, t + 0.1)


def key(k, t):
    steps.append({"t": t, "x": A[0], "y": A[1], "type": "key", "key": k})
    plan.append(("key", t, k))


hold(A, 0.0, 0.6)
glide(A, RECT, 0.6, 0.7, bow=-10)
hold(RECT, 1.3, 1.45)
click(RECT, 1.45)
glide(RECT, P1, 1.6, 0.9, bow=-40)
hold(P1, 2.5, 2.9)
press("down", P1, 2.9)
glide(P1, P2, 2.95, 1.2, bow=6, held=True)
press("up", P2, 4.25)
hold(P2, 4.25, 4.9)
press("down", P2, 4.9)
glide(P2, P3, 4.95, 0.95, bow=-5, held=True)
press("up", P3, 6.0)
glide(P3, M, 6.0, 0.8, bow=20)
hold(M, 6.8, 7.2)
glide(M, HAND, 7.2, 0.8, bow=30)
hold(HAND, 8.0, 8.1)
click(HAND, 8.1)
glide(HAND, Q, 8.25, 0.75, bow=-30)
hold(Q, 9.0, 9.3)
press("down", Q, 9.3)
glide(Q, Q2, 9.35, 1.0, bow=10, held=True)
press("up", Q2, 10.45)
glide(Q2, A, 10.45, 0.85, bow=-20)
hold(A, 11.3, 12.4)
key("z", 11.4)

steps.sort(key=lambda s: (s["t"], s["type"] != "move"))
json.dump(steps, open(sys.argv[1], "w"))
json.dump(plan, open(sys.argv[1].replace(".json", "-plan.json"), "w"))
print(len(steps), "steps;", steps[-1]["t"], "s")
