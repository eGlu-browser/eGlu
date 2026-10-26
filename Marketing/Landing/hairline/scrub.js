/**
 * Scrub: a card of five glass rows, a pinned-tab list, and a hand whose index
 * finger rests on one. The pointer slides the finger along the rows on a
 * spring; the row under its pad lifts on the 700ms curve, its neighbours less,
 * staggered out from it, and takes the bright edge. The finger rides the rows'
 * tops. The slider is the lift, in world units.
 *
 * The finger and the hand are rounded solids lying at a slant, so each is the
 * hull of a few balls, not a prism: a silhouette, and the marks a hand has
 * (the nail, the joints' creases, the curled fingers' seams).
 */
const {
  Cam, clamp, facing, fit, lerp, open, poly, proj, prism, rings, unproj, hull,
  spring, stepS, tween, tset, tval, tdone, mk, put, solid, pointer, register, disposer,
} = HL;

const N = 5, RL = 70, RW = 21, PITCH = 26, T = 3.5, X0 = -7, X1 = RL + 7, Y0 = -7, Y1 = (N - 1) * PITCH + RW + 7;
const REST = [1, 2.2, 4.5, 2.6, 1.2], HOME = 2, TIPX = 17, TIP = 5.4;

const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a) => mul(a, 1 / Math.hypot(a[0], a[1], a[2]));
const at = (o, u, v, w, a, b, c) => add(add(add(o, mul(u, a)), mul(v, b)), mul(w, c));

/** Points on a ball's surface: hulled together, balls make capsules and rounded slabs. */
function ball(c, r) {
  const pts = [add(c, [0, 0, r]), add(c, [0, 0, -r])];
  for (let i = 1; i < 8; i++) for (let j = 0; j < 18; j++) {
    const th = (i / 8) * Math.PI, ph = (j / 18) * 2 * Math.PI;
    pts.push(add(c, [r * Math.sin(th) * Math.cos(ph), r * Math.sin(th) * Math.sin(ph), r * Math.cos(th)]));
  }
  return pts;
}

/** The hand at the finger's tip [x, y, z]: its parts, back to front, each {sil, marks}. */
function hand(P, V, tip) {
  // The finger runs across the view, not toward it, so it is seen at its length; it rises
  // from its tip toward the hand, a little steeper at each joint.
  const d1 = norm([1, -0.25, 0.22]), d2 = norm([1, -0.27, 0.3]), d3 = norm([1, -0.3, 0.38]);
  const A0 = tip, A1 = add(A0, mul(d1, 16)), A2 = add(A1, mul(d2, 15)), A3 = add(A2, mul(d3, 18));
  const u = norm([1, -0.3, 0.3]), v = norm([-u[1], u[0], 0]), w = cross(u, v);
  const shell = (balls) => poly(hull([].concat(...balls.map(([c, r]) => ball(c, r))).map((p) => P(...p))));
  /** The visible half of a ring round the axis a at c: a joint's crease, a seam. */
  const arc = (c, a, r) => {
    const e1 = norm(cross(a, [0, 0, 1])), e2 = cross(a, e1), pts = [];
    for (let k = 0; k <= 36; k++) {
      const t = (k / 36) * 2 * Math.PI, n = add(mul(e1, Math.cos(t)), mul(e2, Math.sin(t)));
      if (dot(n, V) > 0.12) pts.push(P(...add(c, mul(n, r))));
    }
    return open(pts);
  };
  // The nail: a rounded patch on the top of the last joint, near its tip.
  const up = norm(cross(cross(d1, [0, 0, 1]), d1)), side = cross(d1, up), nail = [];
  for (let k = 0; k < 24; k++) {
    const t = (k / 24) * 2 * Math.PI, s = 0.5 + 0.4 * Math.cos(t), f = 0.66 * Math.sin(t);
    nail.push(P(...add(add(A0, mul(d1, 0.6 + s * 8)), add(mul(up, TIP * 1.03 * Math.cos(f)), mul(side, TIP * 1.03 * Math.sin(f))))));
  }
  // The back of the hand, in line with the knuckle; the three other fingers curled under
  // its front, and the thumb along its near side, under the finger.
  const H = at(A3, u, v, w, 14, -8, -2), slab = [];
  for (const a of [-9, 10]) for (const b of [-10, 9]) for (const c of [-3, 3]) slab.push([at(H, u, v, w, a, b, c), 8]);
  // A curled finger: its knuckle up at the hand's far edge, curling down under the palm.
  const curl = (b, r) => shell([[at(H, u, v, w, -17, b, 4), r], [at(H, u, v, w, -20, b, -8), r * 0.92]]);
  return [
    { sil: shell([[A0, TIP], [A1, 5.6]]), marks: [[poly(nail), "nf"], [arc(A1, d1, 5.6), "nf lo"]] },
    { sil: shell([[A1, 5.6], [A2, 6]]), marks: [[arc(A2, d2, 6), "nf lo"]] },
    { sil: shell([[A2, 6], [A3, 6.6]]), marks: [] },
    { sil: curl(-23, 5.4), marks: [] },
    { sil: curl(-15.5, 6.2), marks: [] },
    { sil: curl(-8, 6.5), marks: [] },
    { sil: shell(slab), marks: [[arc(A3, d3, 6.7), "nf lo"]] },
    { sil: shell([[at(H, u, v, w, -2, 17, -7), 6.2], [at(H, u, v, w, -19, 15, -13), 5.4]]), marks: [] },
  ];
}

function mount({ stage, svg, read }, value) {
  const bag = disposer();
  let lift = value;
  const C = Cam(45, 0.5, 1.9), centre = (i) => i * PITCH + RW / 2;
  // Fitted to the card and to the hand at both ends of the row, lifted all the way: a recording
  // P collects every world point the hand is drawn from.
  const ext = [[X0, Y0, -4], [X1, Y1, -4], [X1, Y0, -4], [X0, Y1, -4]];
  const record = (x, y, z) => { ext.push([x, y, z]); return [x, y]; };
  for (const i of [0, N - 1]) hand(record, view(proj(Cam(45, 0.5, 1))), [TIPX, centre(i), T + 16 + TIP]);
  fit(C, ext, 200, 166);
  const P = proj(C), V = view(P), fr = facing(C);

  const g = mk("g", {}, svg);
  const [cr, ci] = rings(X0, Y0, X1, Y1, 9, 2);
  put(solid(g), prism(P, fr, cr, ci, -4, 0));
  const rows = [];
  for (let i = 0; i < N; i++) {
    const [ring, inner] = rings(0, i * PITCH, RL, i * PITCH + RW, 6, 1.4);
    rows.push({ ring, inner, el: solid(g), tw: tween(REST[i]), drawn: NaN });
  }
  const fg = mk("g", { "data-part": "hand" }, g), parts = [];
  const fy = spring(centre(HOME), { eps: 0.02 });
  let act = -1, drawnFinger = "";

  /** The rows' height under the finger: between the two rows it lies across, so it never jumps. */
  const topAt = (y, now) => {
    const s = clamp((y - RW / 2) / PITCH, 0, N - 1), i = Math.floor(s), j = Math.min(i + 1, N - 1);
    return T + lerp(tval(rows[i].tw, now), tval(rows[j].tw, now), s - i);
  };

  const B = register(stage, (dt, now) => {
    let moving = stepS(fy, dt);
    rows.forEach((r) => {
      const h = tval(r.tw, now);
      if (!tdone(r.tw, now)) moving = true;
      if (h === r.drawn) return;
      r.drawn = h;
      put(r.el, prism(P, fr, r.ring, r.inner, 0, T + h));
    });
    const tip = [TIPX, fy.x, topAt(fy.x, now) + TIP], key = tip.map((n) => n.toFixed(2)).join();
    if (key !== drawnFinger) {
      drawnFinger = key;
      fg.replaceChildren();
      for (const part of hand(P, V, tip)) {
        mk("path", { d: part.sil, class: "sil" }, fg);
        for (const [d, cls] of part.marks) mk("path", { d, class: cls }, fg);
      }
    }
    return moving;
  });
  bag.add(B.unregister);

  /** Row a under the finger (-1: at rest on the home row). The lift spreads out from it. */
  function choose(a) {
    const now = performance.now(), from = a >= 0 ? a : HOME;
    rows.forEach((r, i) => {
      const d = Math.abs(i - from), h = a < 0 ? REST[i] : d === 0 ? lift : d === 1 ? lift * 0.35 : 0.6;
      tset(r.tw, h, now, d * 45);
      r.el.sil.classList.toggle("hi", i === from);
    });
    act = a;
    read.textContent = a < 0 ? "rest" : `tile ${a + 1}`;
    B.wake();
  }
  choose(-1);

  // The pointer is read on the plane of the rows' resting tops, which never moves.
  bag.add(pointer(stage, {
    move: (p) => {
      const [x, y] = unproj(C, p[0], p[1], T + 2);
      if (x < X0 - 10 || x > X1 + 30 || y < Y0 - 10 || y > Y1 + 10) { fy.t = centre(HOME); choose(-1); return; }
      fy.t = clamp(y, centre(0), centre(N - 1));
      const a = clamp(Math.round((y - RW / 2) / PITCH), 0, N - 1);
      if (a !== act) choose(a); else B.wake();
    },
    leave: () => { fy.t = centre(HOME); choose(-1); },
  }));
  bag.add(() => svg.replaceChildren());

  return {
    set: (v) => { lift = v; const a = act; act = -2; choose(a); },
    destroy: bag.dispose,
  };
}

/** The direction toward the camera, from how P maps the three axes: the one it flattens. */
function view(P) {
  const o = P(0, 0, 0), ax = [P(1, 0, 0), P(0, 1, 0), P(0, 0, 1)].map((q) => [q[0] - o[0], q[1] - o[1]]);
  const r1 = [ax[0][0], ax[1][0], ax[2][0]], r2 = [ax[0][1], ax[1][1], ax[2][1]], n = norm(cross(r1, r2));
  return n[2] < 0 ? mul(n, -1) : n;
}

hairline({
  name: "scrub",
  means: "A finger slides along a list of glass rows; the row under its pad lifts, and its neighbours lift less.",
  rules: [1, 2, 8, 9],
  range: [5, 10, 16],
  mount,
});
