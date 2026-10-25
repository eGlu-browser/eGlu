// Pick an element on the page, as the developer tools' inspector does.
// Run in the app's own world with callAsyncJavaScript: outlines the element
// under the pointer or the finger in a closed shadow root (never part of the
// page's own styles or queries), and resolves with its client rectangle on a
// click or tap, or null on Escape. While it runs it takes the click (with
// the presses that make it) and Esc from the page, and nothing else.
//
// The rectangle comes with the visual viewport (where it sits and how wide
// it is in CSS pixels), which the app needs to find it in its own points:
// a desktop page scaled to fit, a page zoomed or pinched (DeveloperMode).

let current = null;
const host = document.createElement("div");
// The host's own style, so the page's rules for a div never move or hide it.
host.style.cssText =
  "all:initial!important;position:fixed!important;inset:0!important;" +
  "pointer-events:none!important;z-index:2147483647!important";
const root = host.attachShadow({ mode: "closed" });
const style = document.createElement("style");
style.textContent =
  ":host{all:initial}" +
  "div{position:fixed;display:none;box-sizing:border-box;border:2px solid #007aff;" +
  "box-shadow:0 0 0 1px rgba(255,255,255,.7);background:rgba(0,122,255,.14);" +
  "border-radius:2px;pointer-events:none}";
const box = document.createElement("div");
root.append(style, box);
document.documentElement.appendChild(host);

const show = (x, y) => {
  const element = document.elementFromPoint(x, y);
  if (!element || element === host) return;
  current = element;
  const rect = element.getBoundingClientRect();
  box.style.display = "block";
  box.style.left = rect.left + "px";
  box.style.top = rect.top + "px";
  box.style.width = rect.width + "px";
  box.style.height = rect.height + "px";
};

const move = (event) => {
  show(event.clientX, event.clientY);
};

// A finger that moved or a second finger is a scroll or a pinch, not a tap.
let touch = null;
const touched = (event) => {
  const first = event.touches[0];
  touch = event.touches.length === 1 && first ? { x: first.clientX, y: first.clientY, moved: false } : null;
  if (touch) show(touch.x, touch.y);
};
const touchMoved = (event) => {
  const first = event.touches[0];
  if (!touch || !first || event.touches.length > 1) {
    touch = null;
    return;
  }
  if (Math.hypot(first.clientX - touch.x, first.clientY - touch.y) > 10) touch.moved = true;
};

const done = new Promise((resolve) => {
  // Listened for on the window, capturing, which comes before the document
  // and every element: a listener of the page's there or later along never
  // hears what is taken (only one the page put on the window before this
  // started can, and nothing in a page can come before that).
  const listeners = [];
  const listen = (type, handler, options) => {
    window.addEventListener(type, handler, options);
    listeners.push([type, handler, options]);
  };
  const finish = (value) => {
    for (const [type, handler, options] of listeners) window.removeEventListener(type, handler, options);
    host.remove();
    resolve(value);
  };
  const take = (event) => {
    event.preventDefault();
    event.stopImmediatePropagation();
  };
  const viewport = () => {
    const vv = window.visualViewport;
    return {
      viewportX: vv ? vv.offsetLeft : 0,
      viewportY: vv ? vv.offsetTop : 0,
      viewportWidth: vv ? vv.width : window.innerWidth,
    };
  };
  const pick = (x, y) => {
    // Where the click is, not where the pointer last moved: a pick begun
    // from the keyboard can come with no move at all.
    show(x, y);
    if (!current) return finish(null);
    const rect = current.getBoundingClientRect();
    finish(Object.assign({ x: rect.x, y: rect.y, width: rect.width, height: rect.height }, viewport()));
  };
  const click = (event) => {
    // The click that picks is never the page's.
    take(event);
    pick(event.clientX, event.clientY);
  };
  const ended = (event) => {
    const one = event.changedTouches && event.changedTouches[0];
    const tapped = touch && !touch.moved && one;
    touch = null;
    if (!tapped) return;
    take(event);
    pick(one.clientX, one.clientY);
  };
  const key = (event) => {
    if (event.key !== "Escape") return;
    take(event);
    finish(null);
  };
  listen("mousemove", move, true);
  // The presses that make the click are the tool's too: a canvas would
  // start a drag on them. A finger's are left, so the page still scrolls.
  for (const type of ["pointerdown", "pointerup", "mousedown", "mouseup", "auxclick", "dblclick"]) {
    listen(type, (event) => { if (event.pointerType !== "touch") take(event); }, true);
  }
  listen("click", click, true);
  listen("touchstart", touched, { capture: true, passive: true });
  listen("touchmove", touchMoved, { capture: true, passive: true });
  listen("touchend", ended, { capture: true, passive: false });
  listen("keydown", key, true);
  // A page that goes away ends it: nothing is left waiting.
  listen("pagehide", () => finish(null), true);
});

return await done;
