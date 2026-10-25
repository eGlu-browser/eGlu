// The JSON view: when a page's whole body is one <pre> of JSON, draw it as a
// tree over the page in a closed shadow root, and leave the <pre> itself
// untouched. Folding objects and arrays; strings, numbers, booleans and null
// in their colours; light and dark as the page's person prefers; monospaced;
// a Raw button puts the overlay away. Runs in the app's own world, injected
// at document end only where the main frame's MIME type says JSON (Page).

(() => {
  // The app's words for the button, in the person's language (Scripts.jsonView).
  const words = /*WORDS*/null || { raw: "Raw" };
  const limit = 10 * 1024 * 1024;
  const pre = document.body && document.body.children.length === 1 &&
    document.body.firstElementChild &&
    document.body.firstElementChild.tagName === "PRE"
    ? document.body.firstElementChild
    : null;
  if (!pre) return;
  const text = pre.textContent || "";
  // Over ten megabytes the raw page stays: parsing a whole tree costs more
  // than reading a blob does. Megabytes of the text as it came, UTF-8: a
  // Korean character is three bytes and one unit of the string. A string is
  // never longer in units than in bytes, so the long ones need no count.
  if (text.length > limit || new Blob([text]).size > limit) return;
  let root;
  try {
    root = JSON.parse(text);
  } catch (_) {
    return;
  }

  const quote = (s) => JSON.stringify(s);
  const short = (value) => {
    if (value === null) return "null";
    if (Array.isArray(value)) return "Array(" + value.length + ")";
    if (typeof value === "object") return "Object(" + Object.keys(value).length + ")";
    if (typeof value === "string") return quote(value.length > 120 ? value.slice(0, 120) + "…" : value);
    return String(value);
  };

  const scalar = (value) => {
    const node = document.createElement("span");
    node.className = value === null ? "null" : typeof value;
    node.textContent = typeof value === "string" ? quote(value) : String(value);
    return node;
  };

  const row = (key, value) => {
    const line = document.createElement("div");
    line.className = "row";
    if (key !== null) {
      const name = document.createElement("span");
      name.className = "key";
      name.textContent = quote(String(key)) + ": ";
      line.appendChild(name);
    }
    if (value !== null && typeof value === "object") {
      const fold = document.createElement("details");
      fold.open = true;
      const head = document.createElement("summary");
      head.textContent = short(value);
      fold.appendChild(head);
      const children = document.createElement("div");
      children.className = "children";
      if (Array.isArray(value)) {
        for (const item of value) children.appendChild(row(null, item));
      } else {
        for (const [name, item] of Object.entries(value)) children.appendChild(row(name, item));
      }
      fold.appendChild(children);
      line.appendChild(fold);
    } else {
      line.appendChild(scalar(value));
    }
    return line;
  };

  const host = document.createElement("div");
  // The host's own style, so no rule of the page's for a div reaches it.
  host.style.cssText = "all:initial!important";
  const shadow = host.attachShadow({ mode: "closed" });
  const style = document.createElement("style");
  style.textContent = `
    :host { all: initial; color-scheme: light dark; }
    .view {
      position: fixed; inset: 0; z-index: 2147483647; overflow: auto;
      box-sizing: border-box; padding: 16px 20px;
      font: 12px/1.55 ui-monospace, Menlo, monospace;
      color: #1d1d1f; background: #ffffff;
    }
    .row { padding-left: 14px; }
    .row > .key { color: #881391; }
    .string { color: #c41a16; }
    .number { color: #1c00cf; }
    .boolean { color: #0b7500; }
    .null { color: #6e6e73; }
    details > summary { cursor: pointer; color: #5f6368; list-style: none; }
    details > summary::before { content: "\\25BE "; }
    details:not([open]) > summary::before { content: "\\25B8 "; }
    details > .children { margin-left: 8px; }
    .bar { position: sticky; top: 0; text-align: right; pointer-events: none; }
    .bar button {
      pointer-events: auto;
      font: 12px ui-monospace, Menlo, monospace; cursor: pointer;
      padding: 2px 10px; border: 1px solid rgba(0,0,0,.18); border-radius: 4px;
      background: #f2f2f2; color: #1d1d1f;
    }
    @media (pointer: coarse) {
      .bar button { min-width: 44px; min-height: 44px; padding: 10px 14px; }
    }
    @media (prefers-color-scheme: dark) {
      .view { color: #e8e8ed; background: #1c1c1e; }
      .row > .key { color: #c88bf0; }
      .string { color: #ff8170; }
      .number { color: #9989ff; }
      .boolean { color: #7cd888; }
      .null { color: #98989d; }
      details > summary { color: #aeaeb2; }
      .bar button { background: #2c2c2e; color: #e8e8ed; border-color: rgba(255,255,255,.22); }
    }`;
  const view = document.createElement("div");
  view.className = "view";
  const bar = document.createElement("div");
  bar.className = "bar";
  const raw = document.createElement("button");
  raw.textContent = words.raw;
  bar.appendChild(raw);
  view.appendChild(bar);
  view.appendChild(row(null, root));
  shadow.append(style, view);
  document.documentElement.appendChild(host);

  // What the bar asks of it: drawn() for whether it is up, toggle() to put it
  // away or back (which is what Raw says), and nothing else.
  window.__egluJSON = {
    drawn() { return view.isConnected; },
    toggle() {
      if (view.isConnected) {
        view.remove();
        return false;
      }
      shadow.appendChild(view);
      return true;
    },
  };
  raw.addEventListener("click", () => window.__egluJSON.toggle());
})();
