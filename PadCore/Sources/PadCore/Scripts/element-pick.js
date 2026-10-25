// Pick an element on the page, as the developer tools' inspector does.
// Run in the app's own world with callAsyncJavaScript: outlines the element
// under the pointer or the finger in a closed shadow root (never part of the
// page's own styles or queries), and resolves with its client rectangle on a
// click or tap, or null on Escape. While it runs it takes the click and Esc
// from the page, and nothing else.

let current = null;
const host = document.createElement("div");
const root = host.attachShadow({ mode: "closed" });
const style = document.createElement("style");
style.textContent =
  "div{position:fixed;display:none;box-sizing:border-box;border:2px solid #007aff;" +
  "background:rgba(0,122,255,.14);border-radius:2px;pointer-events:none;z-index:2147483647}";
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
  const point = event.touches && event.touches[0] ? event.touches[0] : event;
  show(point.clientX, point.clientY);
};

const done = new Promise((resolve) => {
  const finish = (value) => {
    document.removeEventListener("mousemove", move, true);
    document.removeEventListener("touchmove", move, true);
    document.removeEventListener("click", click, true);
    document.removeEventListener("touchend", click, true);
    document.removeEventListener("keydown", key, true);
    host.remove();
    resolve(value);
  };
  const click = (event) => {
    // The click that picks is never the page's.
    event.preventDefault();
    event.stopPropagation();
    if (event.type === "touchend") {
      const touch = event.changedTouches && event.changedTouches[0];
      if (touch) show(touch.clientX, touch.clientY);
    }
    if (!current) return finish(null);
    const rect = current.getBoundingClientRect();
    finish({ x: rect.x, y: rect.y, width: rect.width, height: rect.height });
  };
  const key = (event) => {
    if (event.key !== "Escape") return;
    event.preventDefault();
    event.stopPropagation();
    finish(null);
  };
  document.addEventListener("mousemove", move, true);
  document.addEventListener("touchmove", move, { capture: true, passive: true });
  document.addEventListener("click", click, true);
  document.addEventListener("touchend", click, { capture: true });
  document.addEventListener("keydown", key, true);
});

return await done;
