/**
 * Magic Keyboard: an iPad floating on its Magic Keyboard, seen from the front. The deck carries its
 * key rows and the trackpad; the iPad hangs on the back panel, tilted back by the camera's own 30°,
 * so its screen faces the reader square. The pointer on the trackpad sets the finger there, and the
 * iPad's pointer, a dot on the screen, follows it; the read-out is where the dot is, in the iPad's
 * points. The slider is the tracking speed.
 *
 * The pattern: a position (a field without the falloff): one spring per axis for the finger, the dot
 * mapped from it. The camera is turned to face the screen, because the figure stands under a flat
 * screen recording: the camera is the concept here.
 */
const {
  Cam, clamp, circ, fit, poly, proj, ringAt, rrect, rings, prism, facing, unproj,
  spring, stepS, disposer, mk, solid, put, register, pointer,
} = HL;

// The deck, in millimetres: x across, y from the hinge (0) to the front edge, z up.
const DX = 148, DY = 230, DZ = 6, DR = 14;
// The trackpad, set into the deck below the keys.
const PX = 58, PY0 = 142, PY1 = 212, PR = 7;
// The iPad: 281.6 × 215.5, its foot floating forward of the hinge, tilted back 30°.
const IW = 140.8, IH = 215.5, IY = 26, IZ = 38, IR = 18, BEZ = 7.5;
const SIN = 0.5, COS = Math.sqrt(3) / 2;
// The screen, in iPad points (13-inch, landscape).
const SW = 1376, SH = 1032;
// Key rows, front of the function row first; each row is a list of key widths in units.
const U = 18.6, KG = 3.1, ROWS = [
  { y: 16, h: 9, keys: Array(14).fill(14.5 / 14) },
  { y: 28.2, h: 15.5, keys: [...Array(13).fill(1), 1.5] },
  { y: 46.9, h: 15.5, keys: [1.5, ...Array(12).fill(1), 1] },
  { y: 65.6, h: 15.5, keys: [1.75, ...Array(11).fill(1), 1.75] },
  { y: 84.3, h: 15.5, keys: [2.25, ...Array(10).fill(1), 2.25] },
  { y: 103, h: 15.5, keys: [1, 1, 1, 1.25, 5, 1.25, 1, 1, 1, 1] },
];
const REST = [-0.34, 0.28];   // the finger at rest, in the trackpad's own -1..1

/** A point on the iPad's face: u across from its middle, v up from its foot. */
const onPad = (P, u, v) => P(u, IY - v * SIN, IZ + v * COS);

function keys(P) {
  return ROWS.map((row) => {
    let x = -(14.5 * U) / 2;
    return row.keys.map((w) => {
      const k = rrect(x + KG / 2, row.y, x + w * U - KG / 2, row.y + row.h, 2.4, 3);
      x += w * U;
      return poly(ringAt(P, k, DZ));
    }).join("");
  });
}

function mount({ stage, svg, read }, value) {
  const bag = disposer();
  let speed = value;

  const C = Cam(0, 0.5, 0.86);
  fit(C, [[-DX, DY, 0], [DX, DY, 0], [-IW, IY - IH * SIN, IZ + IH * COS], [IW, IY - IH * SIN, IZ + IH * COS]], 200, 162);
  const P = proj(C), front = facing(C);
  const g = mk("g", {}, svg);

  // The back panel, from the hinge up behind the iPad: only its foot shows, between hinge and iPad.
  const att = (u) => P(u, IY - IH * 0.45 * SIN, IZ + IH * 0.45 * COS);
  mk("path", { d: poly([P(-IW + 6, 3, 10), P(IW - 6, 3, 10), att(IW - 6), att(-IW + 6)]), class: "lo" }, g);
  // The hinge: a rounded bar along the deck's back edge.
  mk("path", { d: poly(rrect(-DX + 18, 2, DX - 18, 13, 5.5, 4).map((q) => P(q.u, 3, q.v))), class: "sil" }, g);

  // The iPad: one plate facing the camera, its screen, and the camera on its long top edge.
  const pad = rrect(-IW, 0, IW, IH, IR, 6), scr = rrect(-IW + BEZ, BEZ, IW - BEZ, IH - BEZ, IR - BEZ, 6);
  mk("path", { d: poly(pad.map((q) => onPad(P, q.u, q.v))), class: "sil" }, g);
  mk("path", { d: poly(scr.map((q) => onPad(P, q.u, q.v))), class: "nf lo" }, g);
  const cam = mk("circle", { r: 1.3, class: "dot off" }, g);
  const cp = onPad(P, 0, IH - BEZ / 2);
  cam.setAttribute("cx", cp[0]); cam.setAttribute("cy", cp[1]);

  // The deck: a rounded slab, its key rows, and the trackpad below them.
  const [ring, inner] = rings(-DX, 0, DX, DY, DR, 2);
  put(solid(g), prism(P, front, ring, inner, 0, DZ));
  for (const d of keys(P)) mk("path", { d, class: "nf lo" }, g);
  mk("path", { d: poly(ringAt(P, rrect(-PX, PY0, PX, PY1, PR, 5), DZ)), class: "nf" }, g);

  // The finger on the glass: its touch, and the middle of it.
  const touch = mk("path", { class: "nf hi" }, g);
  const pressd = mk("circle", { r: 1.4, class: "dot m" }, g);
  // The iPad's pointer, on the screen.
  const dot = mk("circle", { r: 3.1, class: "dot m" }, g);

  const fx = spring(REST[0]), fy = spring(REST[1]);
  const pcx = 0, pcy = (PY0 + PY1) / 2, phx = PX - 9, phy = (PY1 - PY0) / 2 - 9;
  const disc = circ(8.5, 16);
  let drawn = "";

  function screenAt(u, v) {
    return [clamp(SW / 2 + u * speed * SW / 2, 0, SW), clamp(SH / 2 + v * speed * SH / 2, 0, SH)];
  }

  function draw() {
    const x = pcx + fx.x * phx, y = pcy + fy.x * phy;
    const key = `${x.toFixed(2)},${y.toFixed(2)},${speed}`;
    if (key === drawn) return;
    drawn = key;
    touch.setAttribute("d", poly(disc.map((q) => P(x + q.u, y + q.v, DZ + 0.4))));
    const c = P(x, y, DZ + 0.4);
    pressd.setAttribute("cx", c[0]); pressd.setAttribute("cy", c[1]);
    const [sx, sy] = screenAt(fx.x, fy.x);
    const p = onPad(P, -IW + BEZ + (sx / SW) * (2 * (IW - BEZ)), IH - BEZ - (sy / SH) * (IH - 2 * BEZ));
    dot.setAttribute("cx", p[0]); dot.setAttribute("cy", p[1]);
  }

  const B = register(stage, (dt) => {
    const a = stepS(fx, dt), b = stepS(fy, dt);
    draw();
    return a || b;
  });
  bag.add(B.unregister);
  draw();

  /** The trackpad under the pointer, from the deck's top plane, which never moves; null off it. */
  function hit([sx, sy]) {
    const [x, y] = unproj(C, sx, sy, DZ);
    if (Math.abs(x - pcx) > PX + 4 || y < PY0 - 4 || y > PY1 + 4) return null;
    return [clamp((x - pcx) / phx, -1, 1), clamp((y - pcy) / phy, -1, 1)];
  }

  function aim(t) {
    const [u, v] = t || REST;
    fx.t = u; fy.t = v;
    if (t) {
      const [sx, sy] = screenAt(u, v);
      read.textContent = `${Math.round(sx)}·${Math.round(sy)}`;
    } else {
      read.textContent = "rest";
    }
    B.wake();
  }

  bag.add(pointer(stage, { move: (p) => aim(hit(p)), down: (p) => aim(hit(p)), leave: () => aim(null) }));
  bag.add(() => svg.replaceChildren());
  read.textContent = "rest";

  return {
    set: (v) => { speed = v; drawn = ""; draw(); },
    destroy: bag.dispose,
  };
}

hairline({
  name: "magic-keyboard",
  means: "An iPad on its Magic Keyboard: a finger on the trackpad, and the iPad's pointer following it on the screen.",
  rules: [1, 5, 8, 9],
  range: [0.6, 1, 1.4],
  mount,
});
