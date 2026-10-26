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

  // A number JavaScript can't hold as it is written (an id past 2^53, more
  // digits than a double keeps, 1e400) would be drawn as another number:
  // a page with one stays raw, as it came, rather than show the wrong value.
  const faithful = (source) => {
    const number = /-?(\d+)(?:\.(\d+))?(?:[eE][+-]?\d+)?/y;
    for (let i = 0; i < source.length; i += 1) {
      const c = source.charCodeAt(i);
      if (c === 34) {
        // A string, to its closing quote: what is in it is text.
        for (i += 1; i < source.length; i += 1) {
          const d = source.charCodeAt(i);
          if (d === 92) i += 1;
          else if (d === 34) break;
        }
      } else if (c === 45 || (c >= 48 && c <= 57)) {
        number.lastIndex = i;
        const found = number.exec(source);
        if (!found) continue;
        const value = Number(found[0]);
        const whole = found[2] === undefined && !/[eE]/.test(found[0]);
        const digits = (found[1] + (found[2] || "").replace(/0+$/, "")).replace(/^0+/, "").length;
        if (!isFinite(value) || (whole && !Number.isSafeInteger(value)) || digits > 17) return false;
        i = number.lastIndex - 1;
      }
    }
    return true;
  };
  if (!faithful(text)) return;

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
      font: 12px/1.6 ui-monospace, "SF Mono", Menlo, monospace;
      color: #1d1d1f; background: #ffffff;
    }
    .row { padding-left: 14px; }
    .row > .key { color: #881391; }
    .string { color: #c41a16; }
    .number { color: #1c00cf; }
    .boolean { color: #0b7500; }
    .null { color: #6e6e73; }
    details > summary { cursor: default; color: #6e6e73; list-style: none; border-radius: 4px; }
    details > summary::-webkit-details-marker { display: none; }
    /* A chevron that turns as the branch opens, rather than a character swapped. */
    details > summary::before {
      content: ""; display: inline-block; width: 6px; height: 6px; margin: 0 7px 1px 1px;
      border-right: 1.5px solid currentColor; border-bottom: 1.5px solid currentColor;
      transform: rotate(45deg); transition: transform 150ms cubic-bezier(0.23, 1, 0.32, 1);
    }
    details:not([open]) > summary::before { transform: rotate(-45deg); }
    @media (hover: hover) { details > summary:hover { background: rgba(0,0,0,.05); } }
    details > .children { margin-left: 8px; }
    .bar { position: sticky; top: 0; text-align: right; pointer-events: none; }
    .bar button {
      pointer-events: auto;
      font: 500 12px -apple-system, system-ui; cursor: default;
      padding: 5px 14px; border: 0; border-radius: 999px;
      background: rgba(0,0,0,.07); color: #1d1d1f;
      transition: transform 100ms ease-out, background-color 120ms ease;
    }
    .bar button:active { transform: scale(0.96); }
    @media (hover: hover) { .bar button:hover { background: rgba(0,0,0,.12); } }
    @media (pointer: coarse) {
      .bar button { min-width: 44px; min-height: 44px; padding: 10px 16px; }
    }
    @media (prefers-reduced-motion: reduce) { details > summary::before { transition: none; } }
    @media (prefers-color-scheme: dark) {
      .view { color: #e8e8ed; background: #1c1c1e; }
      .row > .key { color: #c88bf0; }
      .string { color: #ff8170; }
      .number { color: #9989ff; }
      .boolean { color: #7cd888; }
      .null { color: #98989d; }
      details > summary { color: #aeaeb2; }
      .bar button { background: rgba(255,255,255,.12); color: #e8e8ed; }
      @media (hover: hover) {
        .bar button:hover { background: rgba(255,255,255,.18); }
        details > summary:hover { background: rgba(255,255,255,.07); }
      }
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
