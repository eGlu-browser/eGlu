// eGlu's measuring tool, grown from element-pick.js. Run once in the app's
// own world with callAsyncJavaScript: everything it draws is one canvas in a
// closed shadow root over the page (never part of the page's styles or
// queries), and everything it says goes through the egluMeasure handler to
// the app's panel. It resolves when the tool ends, and while it runs it takes
// the click and Esc, ⌥ held, G, R and X from the page, and nothing else.
// The app's guide and ruler settings come in as the `guides` argument; in a
// test there may be none.
const cfg = typeof guides === "undefined" ? {} : guides;

let selected = null;
let hover = null;
let alt = false;
let guidesOn = false;
let rulersOn = !!cfg.rulers;
let xrayOn = false;
let tapping = 0; // the click a touchend brings is not another tap
let frame = 0;
let observer = null;
const pins = new Map(); // note id -> {element, number}
const refs = new Map(); // ref -> element the panel can pin a note to
let refCount = 0;
const tell = (message) => {
  const handlers = window.webkit && window.webkit.messageHandlers;
  if (handlers && handlers.egluMeasure) handlers.egluMeasure.postMessage(message);
};

const host = document.createElement("div");
const root = host.attachShadow({ mode: "closed" });
const style = document.createElement("style");
style.textContent =
  "canvas{position:fixed;inset:0;pointer-events:none;z-index:2147483647}";
const canvas = document.createElement("canvas");
root.append(style, canvas);
document.documentElement.appendChild(host);

// The element under a point, never the overlay's (its pointer-events are none).
const under = (x, y) => {
  const element = document.elementFromPoint(x, y);
  return element && element !== host ? element : null;
};

// The name a note's element is known by: its #id, or up to four levels of
// tag.class:nth-of-type(n) from the nearest ancestor with an id, or from body.
const nameOf = (element) => {
  if (!element) return "";
  if (element.id) return "#" + element.id;
  const parts = [];
  let node = element;
  while (node && node !== document.documentElement && parts.length < 4) {
    if (node.id) { parts.unshift("#" + node.id); break; }
    if (node === document.body) { parts.unshift("body"); break; }
    let part = node.tagName.toLowerCase();
    const first = typeof node.className === "string" ? node.className.trim().split(/\s+/)[0] : "";
    if (first) part += "." + first;
    const parent = node.parentElement;
    if (parent) {
      const siblings = Array.from(parent.children).filter((each) => each.tagName === node.tagName);
      if (siblings.length > 1) part += ":nth-of-type(" + (siblings.indexOf(node) + 1) + ")";
    }
    parts.unshift(part);
    node = parent;
  }
  return parts.join(" ");
};

const edges = (box) => {
  const style = getComputedStyle(box);
  const px = (name) => parseFloat(style[name]) || 0;
  const border = box.getBoundingClientRect();
  const margin = {
    top: px("marginTop"), right: px("marginRight"), bottom: px("marginBottom"), left: px("marginLeft"),
  };
  const padding = {
    top: px("paddingTop"), right: px("paddingRight"), bottom: px("paddingBottom"), left: px("paddingLeft"),
  };
  const line = {
    top: px("borderTopWidth"), right: px("borderRightWidth"), bottom: px("borderBottomWidth"), left: px("borderLeftWidth"),
  };
  return { style, border, margin, padding, line };
};

// What the panel shows of the selected element (1.2): its boxes, layout,
// type and colours, its name, and its first words for the note an assistant gets.
const detailsOf = (element) => {
  const { style, border, margin, padding, line } = edges(element);
  const family = (style.fontFamily || "").split(",")[0].replace(/^["']|["']$/g, "").trim();
  return {
    kind: "details",
    tag: element.tagName.toLowerCase(),
    id: element.id || "",
    classes: String(element.className && element.className.baseVal === undefined ? element.className : "")
      .trim().split(/\s+/).filter(Boolean).slice(0, 3),
    width: border.width, height: border.height,
    x: border.x, y: border.y,
    margin, padding, border: line,
    display: style.display,
    gap: { row: style.rowGap, column: style.columnGap },
    font: {
      family, size: style.fontSize, weight: style.fontWeight,
      lineHeight: style.lineHeight, letterSpacing: style.letterSpacing,
    },
    color: style.color,
    background: style.backgroundColor,
    radius: style.borderRadius,
    name: nameOf(element),
    text: (element.innerText || "").trim().replace(/\s+/g, " ").slice(0, 40),
    ref: (refCount += 1),
  };
};

// The distances between two boxes: between their facing sides, or the four
// insets when one holds the other.
const distanceBetween = (a, b) => {
  const one = a.getBoundingClientRect();
  const two = b.getBoundingClientRect();
  const inner = (p, q) =>
    p.left >= q.left && p.right <= q.right && p.top >= q.top && p.bottom <= q.bottom;
  if (inner(one, two) || inner(two, one)) {
    const inside = inner(one, two) ? one : two;
    const outside = inner(one, two) ? two : one;
    return {
      inside: true,
      insets: {
        top: inside.top - outside.top, right: outside.right - inside.right,
        bottom: outside.bottom - inside.bottom, left: inside.left - outside.left,
      },
    };
  }
  const dx = two.left >= one.right ? two.left - one.right : (one.left >= two.right ? one.left - two.right : 0);
  const dy = two.top >= one.bottom ? two.top - one.bottom : (one.top >= two.bottom ? one.top - two.bottom : 0);
  return { inside: false, dx, dy };
};

// A container's gaps between its children, to fill in purple: for each pair
// of siblings that are beside each other, the strip between their boxes.
const gapBoxes = (element) => {
  const { style } = edges(element);
  if (!/flex|grid/.test(style.display)) return [];
  const boxes = Array.from(element.children).map((each) => each.getBoundingClientRect());
  const row = parseFloat(style.rowGap) || 0;
  const column = parseFloat(style.columnGap) || 0;
  const widest = Math.max(row, column, 4) * 3 + 8;
  const found = [];
  for (let i = 0; i < boxes.length; i += 1) {
    for (let j = i + 1; j < boxes.length; j += 1) {
      const a = boxes[i];
      const b = boxes[j];
      // Beside each other in a row: the horizontal strip between them where they overlap.
      if (b.left > a.right && b.left - a.right <= widest) {
        const top = Math.max(a.top, b.top);
        const bottom = Math.min(a.bottom, b.bottom);
        if (bottom > top) found.push({ x: a.right, y: top, w: b.left - a.right, h: bottom - top });
      }
      // One above the other: the vertical strip.
      if (b.top > a.bottom && b.top - a.bottom <= widest) {
        const left = Math.max(a.left, b.left);
        const right = Math.min(a.right, b.right);
        if (right > left) found.push({ x: left, y: a.bottom, w: right - left, h: b.top - a.bottom });
      }
    }
  }
  return found;
};

let distant = null; // the element the distance lines reach, while shown

const postDistance = (other) => {
  if (!selected || !other || other === selected) { distant = null; return; }
  const said = distanceBetween(selected, other);
  distant = { element: other, said };
  tell(Object.assign({ kind: "distance", target: nameOf(other) }, said));
};

const schedule = () => {
  if (frame) return;
  frame = requestAnimationFrame(() => {
    frame = 0;
    draw();
  });
};

const box = (context, rect, fill, line) => {
  if (fill) {
    context.fillStyle = fill;
    context.fillRect(rect.left, rect.top, rect.width, rect.height);
  }
  if (line) {
    context.strokeStyle = line;
    context.lineWidth = 2;
    context.strokeRect(rect.left, rect.top, rect.width, rect.height);
  }
};

const label = (context, text, x, y) => {
  context.font = "11px -apple-system, sans-serif";
  const width = context.measureText(text).width;
  context.fillStyle = "#0a84ff";
  context.fillRect(x - 4, y - 14, width + 8, 16);
  context.fillStyle = "#fff";
  context.fillText(text, x, y - 3);
};

const draw = () => {
  const ratio = window.devicePixelRatio || 1;
  const w = window.innerWidth;
  const h = window.innerHeight;
  if (canvas.width !== Math.round(w * ratio) || canvas.height !== Math.round(h * ratio)) {
    canvas.width = Math.round(w * ratio);
    canvas.height = Math.round(h * ratio);
    canvas.style.width = w + "px";
    canvas.style.height = h + "px";
  }
  const context = canvas.getContext("2d");
  context.setTransform(ratio, 0, 0, ratio, 0, 0);
  context.clearRect(0, 0, w, h);

  // The column and row guides, from the app's settings (G).
  if (guidesOn) {
    const count = Math.max(1, Math.round(cfg.columns || 12));
    const gutter = Math.max(0, cfg.gutter || 0);
    const margin = Math.max(0, cfg.margin || 0);
    const width = (w - margin * 2 - gutter * (count - 1)) / count;
    context.fillStyle = "rgba(255,59,48,.10)";
    for (let i = 0; i < count; i += 1) {
      const x = margin + i * (width + gutter);
      if (width > 0) context.fillRect(x, 0, width, h);
      if (gutter > 0 && i < count - 1) {
        context.fillStyle = "rgba(255,59,48,.18)";
        context.fillRect(x + width, 0, gutter, h);
        context.fillStyle = "rgba(255,59,48,.10)";
      }
    }
    const every = Math.max(1, cfg.row || 8);
    context.strokeStyle = "rgba(255,59,48,.35)";
    context.lineWidth = 1;
    context.setLineDash([4, 3]);
    for (let y = every; y < h; y += every) {
      context.beginPath();
      context.moveTo(0, y + 0.5);
      context.lineTo(w, y + 0.5);
      context.stroke();
    }
    context.setLineDash([]);
  }

  // X-ray: every element's box drawn thinly, so the structure shows (X).
  if (xrayOn) {
    context.strokeStyle = "rgba(175,82,222,.6)";
    context.lineWidth = 1;
    let drawn = 0;
    for (const element of document.querySelectorAll("*")) {
      if (element === host || drawn > 2000) continue;
      drawn += 1;
      const rect = element.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) context.strokeRect(rect.left, rect.top, rect.width, rect.height);
    }
  }

  // The selected element's margin, padding and content boxes, and its gaps.
  if (selected && selected.isConnected) {
    const { border, margin, padding, line } = edges(selected);
    box(context, {
      left: border.left - margin.left, top: border.top - margin.top,
      width: border.width + margin.left + margin.right, height: border.height + margin.top + margin.bottom,
    }, "rgba(246,178,107,.45)", null);
    box(context, {
      left: border.left + line.left, top: border.top + line.top,
      width: border.width - line.left - line.right, height: border.height - line.top - line.bottom,
    }, "rgba(147,196,125,.45)", null);
    box(context, {
      left: border.left + line.left + padding.left, top: border.top + line.top + padding.top,
      width: border.width - line.left - line.right - padding.left - padding.right,
      height: border.height - line.top - line.bottom - padding.top - padding.bottom,
    }, "rgba(111,168,220,.35)", null);
    box(context, border, null, "#0a84ff");
    context.fillStyle = "rgba(175,82,222,.5)";
    for (const gap of gapBoxes(selected)) context.fillRect(gap.x, gap.y, gap.w, gap.h);
    label(context, Math.round(border.width) + " × " + Math.round(border.height),
          Math.max(4, border.left), Math.max(18, border.top - 6));
  }

  // The distance lines, to the element under the pointer with ⌥ held, or to
  // the last element tapped (distant is set by postDistance).
  if (selected && distant && distant.element && distant.element.isConnected) {
    const one = selected.getBoundingClientRect();
    const two = distant.element.getBoundingClientRect();
    const said = distant.said;
    context.strokeStyle = "#ff2d55";
    context.fillStyle = "#ff2d55";
    context.lineWidth = 1;
    context.setLineDash([3, 3]);
    const line = (x1, y1, x2, y2, text) => {
      context.beginPath();
      context.moveTo(x1, y1);
      context.lineTo(x2, y2);
      context.stroke();
      label(context, text, (x1 + x2) / 2, (y1 + y2) / 2);
    };
    if (said.inside) {
      const top = said.insets.top, right = said.insets.right, bottom = said.insets.bottom, left = said.insets.left;
      const inner = one.left >= two.left && one.top >= two.top ? one : two;
      const outer = inner === one ? two : one;
      if (top > 0) line(inner.left + inner.width / 2, outer.top, inner.left + inner.width / 2, inner.top, Math.round(top) + "px");
      if (bottom > 0) line(inner.left + inner.width / 2, inner.bottom, inner.left + inner.width / 2, outer.bottom, Math.round(bottom) + "px");
      if (left > 0) line(outer.left, inner.top + inner.height / 2, inner.left, inner.top + inner.height / 2, Math.round(left) + "px");
      if (right > 0) line(inner.right, inner.top + inner.height / 2, outer.right, inner.top + inner.height / 2, Math.round(right) + "px");
    } else {
      if (said.dx > 0) {
        const from = two.left >= one.right ? one.right : two.right;
        const to = two.left >= one.right ? two.left : one.left;
        line(from, Math.min(one.top, two.top) + Math.min(one.height, two.height) / 2,
             to, Math.min(one.top, two.top) + Math.min(one.height, two.height) / 2, Math.round(said.dx) + "px");
      }
      if (said.dy > 0) {
        const from = two.top >= one.bottom ? one.bottom : two.bottom;
        const to = two.top >= one.bottom ? two.top : one.top;
        line(Math.min(one.left, two.left) + Math.min(one.width, two.width) / 2, from,
             Math.min(one.left, two.left) + Math.min(one.width, two.width) / 2, to, Math.round(said.dy) + "px");
      }
    }
    context.setLineDash([]);
  }

  // The element under the pointer, outlined with its size.
  if (hover && hover.isConnected && hover !== selected) {
    const rect = hover.getBoundingClientRect();
    box(context, rect, "rgba(10,132,255,.10)", "#0a84ff");
    label(context, Math.round(rect.width) + " × " + Math.round(rect.height),
          Math.max(4, rect.left), Math.max(18, rect.top - 6));
  }

  // The notes pinned to their elements: a numbered dot at each one's top left.
  context.setLineDash([]);
  for (const pin of pins.values()) {
    if (!pin.element.isConnected) continue;
    const rect = pin.element.getBoundingClientRect();
    context.fillStyle = "#ff9f0a";
    context.beginPath();
    context.arc(rect.left, rect.top, 9, 0, Math.PI * 2);
    context.fill();
    context.fillStyle = "#fff";
    context.font = "bold 10px -apple-system, sans-serif";
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillText(String(pin.number), rect.left, rect.top + 0.5);
    context.textAlign = "start";
    context.textBaseline = "alphabetic";
  }

  // The rulers, top and left: ticks every 10 CSS pixels, numbers every 100,
  // counted from the page's own left and top edge at the current scroll.
  if (rulersOn) {
    context.fillStyle = "rgba(30,30,30,.82)";
    context.fillRect(0, 0, w, 18);
    context.fillRect(0, 0, 18, h);
    context.fillStyle = "#fff";
    context.strokeStyle = "rgba(255,255,255,.7)";
    context.lineWidth = 1;
    context.font = "9px -apple-system, sans-serif";
    const left = Math.floor(window.scrollX);
    const top = Math.floor(window.scrollY);
    for (let x = 0; x < w; x += 2) {
      const at = left + x;
      const unit = ((at % 10) + 10) % 10;
      if (unit !== 0) continue;
      const tall = ((at % 100) + 100) % 100 === 0;
      context.beginPath();
      context.moveTo(x + 0.5, tall ? 6 : 12);
      context.lineTo(x + 0.5, 18);
      context.stroke();
      if (tall && at >= 0) context.fillText(String(at), x + 3, 8);
    }
    for (let y = 0; y < h; y += 2) {
      const at = top + y;
      const unit = ((at % 10) + 10) % 10;
      if (unit !== 0) continue;
      const tall = ((at % 100) + 100) % 100 === 0;
      context.beginPath();
      context.moveTo(tall ? 6 : 12, y + 0.5);
      context.lineTo(18, y + 0.5);
      context.stroke();
      if (tall && at >= 0) {
        context.save();
        context.translate(9, y + 3);
        context.rotate(-Math.PI / 2);
        context.fillText(String(at), 0, 0);
        context.restore();
      }
    }
  }
};

const watch = () => {
  if (observer) observer.disconnect();
  observer = null;
  if (selected && selected.parentElement) {
    observer = new MutationObserver(schedule);
    observer.observe(selected.parentElement, { childList: true, subtree: true, attributes: true });
  }
};

const move = (event) => {
  const point = event.touches && event.touches[0] ? event.touches[0] : event;
  hover = under(point.clientX, point.clientY);
  if (alt && selected) postDistance(hover);
  schedule();
};

const pick = (element) => {
  selected = element;
  distant = null;
  const details = detailsOf(element);
  refs.set(details.ref, element);
  watch();
  tell(details);
  schedule();
};

const click = (event) => {
  // While the tool runs a click selects, never reaching the page.
  event.preventDefault();
  event.stopPropagation();
  if (event.type === "click" && Date.now() - tapping < 500) return;
  const point = event.changedTouches && event.changedTouches[0] ? event.changedTouches[0] : event;
  if (event.type === "touchend") tapping = Date.now();
  const element = under(point.clientX, point.clientY);
  if (!element) return;
  // On touch the next element tapped after a selection gives the distance;
  // tapped again it takes the selection.
  if (event.type === "touchend" && selected && element !== selected && (!distant || distant.element !== element)) {
    postDistance(element);
    schedule();
    return;
  }
  pick(element);
};

const key = (event) => {
  if (event.key === "Escape") {
    event.preventDefault();
    event.stopPropagation();
    finish();
    return;
  }
  if (event.key === "Alt") {
    alt = true;
    if (selected && hover) { postDistance(hover); schedule(); }
    return;
  }
  if (event.ctrlKey || event.metaKey || event.altKey) return;
  const lower = event.key.toLowerCase();
  if (lower !== "g" && lower !== "r" && lower !== "x") return;
  event.preventDefault();
  event.stopPropagation();
  if (lower === "g") guidesOn = !guidesOn;
  if (lower === "r") rulersOn = !rulersOn;
  if (lower === "x") xrayOn = !xrayOn;
  schedule();
};

const lift = (event) => {
  if (event.key !== "Alt") return;
  alt = false;
  distant = null;
  tell({ kind: "distance", gone: true });
  schedule();
};

const finish = () => {
  document.removeEventListener("mousemove", move, true);
  document.removeEventListener("touchmove", move, true);
  document.removeEventListener("click", click, true);
  document.removeEventListener("touchend", click, true);
  document.removeEventListener("keydown", key, true);
  document.removeEventListener("keyup", lift, true);
  document.removeEventListener("scroll", schedule, true);
  window.removeEventListener("resize", schedule);
  if (observer) observer.disconnect();
  if (frame) cancelAnimationFrame(frame);
  host.remove();
  if (window.__egluMeasure) window.__egluMeasure = undefined;
  tell({ kind: "ended" });
  resolve();
};

let resolve;
const done = new Promise((end) => { resolve = end; });

// The app's handle on a running tool: stop it, give it new guide settings,
// or pin a note to an element it has seen (notes, pinned by their number).
window.__egluMeasure = {
  stop: finish,
  // What the tool is showing, as __egluJSON.drawn() says the JSON view's:
  // for its tests, which cannot look inside a closed shadow root.
  state: () => ({
    on: true, guides: guidesOn, rulers: rulersOn, xray: xrayOn,
    selected: !!selected, hover: !!hover, pins: pins.size, alt,
  }),
  settings: (next) => {
    Object.assign(cfg, next);
    schedule();
  },
  pin: (id, ref, number) => {
    const element = refs.get(ref);
    if (element) pins.set(id, { element, number });
    schedule();
  },
  unpin: (id) => {
    pins.delete(id);
    schedule();
  },
};

document.addEventListener("mousemove", move, true);
document.addEventListener("touchmove", move, { capture: true, passive: true });
document.addEventListener("click", click, true);
document.addEventListener("touchend", click, { capture: true });
document.addEventListener("keydown", key, true);
document.addEventListener("keyup", lift, true);
document.addEventListener("scroll", schedule, { capture: true, passive: true });
window.addEventListener("resize", schedule);
schedule();

return await done;
