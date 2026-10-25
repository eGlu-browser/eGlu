// Grammar and spelling in a page's own fields, with Harper on the Mac
// (WritingChecker.swift, WritingHandler.swift).
//
// It runs at document end in the app's own content world, in the main frame
// only, and only where Settings › Writing is on and the site isn't off.
// It underlines problems on the page's own text — WebKit's Custom Highlights
// in a contenteditable, boxes over a field's words in a textarea or input —
// and opens a card beside the word with the fixes: choosing one writes the
// text the way the page's own Undo still takes back. Its approach and
// several parts follow Harper's lint-framework (Apache-2.0).
//
// What the page gets back through the "egluWriting" handler is English it
// typed: nothing else leaves this world, and nothing of the page's is read
// but the focused field's text.
window.__egluWriting = (() => {
'use strict';
if (window.__egluWriting) return window.__egluWriting;

const config = /*__EGLU_WRITING__*/{};
const strings = config.strings || {};

// MARK: Colours, by Harper's lint kind (lintKindColor.ts).

const KIND_COLORS = {
  Agreement: '#228B22', BoundaryError: '#8B4513', Capitalization: '#540D6E',
  Eggcorn: '#FF8C00', Enhancement: '#0EAD69', Formatting: '#7D3C98',
  Grammar: '#9B59B6', Malapropism: '#C71585', Miscellaneous: '#3BCEAC',
  Nonstandard: '#008B8B', Punctuation: '#D4850F', Readability: '#2E8B57',
  Redundancy: '#4682B4', Regionalism: '#C061CB', Repetition: '#00A67C',
  Spelling: '#EE4266', Style: '#FFD23F', Typo: '#FF6B35', Usage: '#1E90FF',
  WordChoice: '#228B22', WordOrder: '#4D4DFF',
};
const kindColor = (kind) => KIND_COLORS[kind] || '#808080';
const kindName = (kind) => strings['kind.' + kind] || kind;

// MARK: Which elements are checked (Decided 1).

// Fields that never hold the kind of English Harper is for, whatever the
// type attribute says.
const PRIVATE_TYPES = /^(password|email|url|tel|number|hidden|checkbox|radio|submit|button|file|image|range|color|date|datetime-local|month|time|week|search-.*)$/i;
const PRIVATE_AUTOCOMPLETE = /^(cc-|one-time-code|username|email|current-password|new-password|webauthn)/i;
const CODE_EDITORS = '.CodeMirror, .cm-editor, .monaco-editor, .ace_editor';

function checkable(el) {
  if (!el || el.nodeType !== 1) return null;
  if (el.closest(CODE_EDITORS)) return null;
  // spellcheck="false" on the field or anything it sits in.
  for (let node = el; node && node.nodeType === 1; node = node.parentElement) {
    if (node.spellcheck === false) return null;
  }
  const name = el.localName;
  if (name === 'textarea') {
    if (el.readOnly || el.disabled) return null;
    return 'form';
  }
  if (name === 'input') {
    const type = (el.getAttribute('type') || 'text').toLowerCase();
    if (!['text', 'search', ''].includes(type)) return null;
    if (PRIVATE_TYPES.test(type)) return null;
    if (el.readOnly || el.disabled) return null;
    const ac = el.getAttribute('autocomplete') || '';
    if (PRIVATE_AUTOCOMPLETE.test(ac.trim())) return null;
    return 'form';
  }
  const editable = el.isContentEditable === true ||
    (el.getAttribute('contenteditable') || '').toLowerCase();
  if (editable === true || editable === '' || editable === 'plaintext-only') {
    return 'rich';
  }
  return null;
}

// The kind of rich-text editor a contenteditable belongs to, for how a fix
// is written back so its own Undo takes it (Decided 10).
function editorKind(el) {
  if (el.localName === 'textarea' || el.localName === 'input') return 'form';
  if (el.closest('[data-lexical-editor]')) return 'lexical';
  if (el.closest('.public-DraftEditor-content')) return 'draft';
  if (el.closest('[data-slate-editor]')) return 'slate';
  if (el.closest('.ck-editor__editable')) return 'ckeditor';
  return 'rich';
}

// The element the boxes and the card hang in: the nearest ancestor of the
// field that isn't itself editable (the boxes' offsets are from it).
function renderAncestor(field) {
  let node = field.parentElement;
  while (node && node.isContentEditable) node = node.parentElement;
  return node || document.body;
}

// MARK: A field's text, and a span in it back as a Range.

// The text of a contenteditable as one string the linter sees: text nodes
// as they are, "\n" for a <br> and where a block ends, the way the words
// read on screen.
function richText(root) {
  const breaks = [];
  let text = '';
  const BLOCK = /^(address|article|aside|blockquote|dd|details|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hgroup|hr|li|main|nav|ol|p|pre|section|summary|table|tbody|td|tfoot|th|thead|tr|ul)$/;
  const walk = (node) => {
    for (let child = node.firstChild; child; child = child.nextSibling) {
      if (child.nodeType === 3) { text += child.data; continue; }
      if (child.nodeType !== 1) continue;
      if (child.localName === 'br') { text += '\n'; breaks.push(child); continue; }
      if (['script', 'style', 'noscript', 'template'].includes(child.localName)) continue;
      walk(child);
      if (BLOCK.test(child.localName) && !text.endsWith('\n')) { text += '\n'; breaks.push(child); }
    }
  };
  walk(root);
  return { text, breaks };
}

// The range covering `start` to `end` (UTF-16 offsets in richText's text)
// in the contenteditable. Newlines from <br> or a block's end line up with
// the position just past the node that made them.
function rangeFor(root, start, end) {
  const range = document.createRange();
  let offset = 0;
  let began = false, ended = false;
  const visit = (node) => {
    if (ended) return;
    if (node.nodeType === 3) {
      const next = offset + node.data.length;
      if (!began && start <= next) { range.setStart(node, start - offset); began = true; }
      if (!ended && end <= next) { range.setEnd(node, end - offset); ended = true; }
      offset = next;
      lastWasBreak = node.data.endsWith('\n');
      return;
    }
    if (node.nodeType !== 1) return;
    if (['script', 'style', 'noscript', 'template'].includes(node.localName)) return;
    for (let child = node.firstChild; child; child = child.nextSibling) {
      visit(child);
      if (ended) return;
      if (child.nodeType === 1) {
        const isBreak = child.localName === 'br';
        const isBlockEnd = !isBreak && BLOCK_END.test(child.localName);
        if (isBreak || (isBlockEnd && !lastWasBreak)) {
          offset += 1;
          lastWasBreak = true;
          const parent = child.parentNode;
          const after = [parent, indexOfNode(child) + 1];
          if (!began && start < offset) { range.setStart(...after); began = true; }
          if (!ended && end < offset) { range.setEnd(...after); ended = true; }
        }
      }
    }
  };
  const BLOCK_END = /^(address|article|aside|blockquote|dd|details|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hgroup|hr|li|main|nav|ol|p|pre|section|summary|table|tbody|td|tfoot|th|thead|tr|ul)$/;
  let lastWasBreak = false;
  const indexOfNode = (node) => Array.prototype.indexOf.call(node.parentNode.childNodes, node);
  visit(root);
  if (!began) range.setStart(root, 0);
  if (!ended) range.setEnd(root, root.childNodes.length);
  return range;
}

function fieldText(field, kind) {
  if (kind === 'form') return { text: field.value, breaks: [] };
  return richText(field);
}

// MARK: Remapping a lint over the edit between two texts (spanMapping.ts).

// The single change from `before` to `after`: how much of each end they
// share. Answers null when they differ in more than one stretch, where a
// lint can't be placed safely.
function singleEdit(before, after) {
  if (before === after) return { start: 0, removed: 0, inserted: 0 };
  let start = 0;
  const limit = Math.min(before.length, after.length);
  while (start < limit && before[start] === after[start]) start++;
  let back = 0;
  while (back < Math.min(before.length, after.length) - start &&
         before[before.length - 1 - back] === after[after.length - 1 - back]) back++;
  const removed = before.length - start - back;
  const inserted = after.length - start - back;
  if (removed < 0 || inserted < 0) return null;
  return { start, removed, inserted };
}

// `span` ([start, end) in `before`) as it sits in `after` once `edit` is
// made: shifted, or widened where the edit lands inside it, or null where
// the edit took the span's own words.
function remapSpan(span, edit) {
  const [start, end] = span;
  if (end <= edit.start) return span;
  const editEnd = edit.start + edit.removed;
  if (start >= editEnd) return [start - edit.removed + edit.inserted, end - edit.removed + edit.inserted];
  if (editEnd <= end && edit.start >= start) return [start, end - edit.removed + edit.inserted];
  return null;
}

// MARK: The lints and where they are drawn.

let lints = [];
let lintedText = '';
// The text as the person left it when the last answer was remapped to.
let shownText = '';
let asking = 0;
let askedSeq = 0;

const post = (message) => {
  try { return window.webkit.messageHandlers.egluWriting.postMessage(message); }
  catch (_) { return Promise.resolve(null); }
};

// MARK: Asking the Mac to lint, and keeping the answer over typing.

// One ask in flight. An answer for text the field no longer holds is
// remapped over the edit between then and now, or asked again where a lint
// can't be placed.
function ask(text) {
  const seq = ++askedSeq;
  asking = seq;
  post({ kind: 'lint', seq, text }).then((answer) => {
    if (asking !== seq || stopped) return;
    asking = 0;
    lintedText = text;
    shownText = field ? fieldText(field, fieldKind).text : text;
    lints = (answer || []).map((lint) => ({
      start: lint.start, end: lint.end, kind: lint.kind, rule: lint.rule,
      message: lint.message, context: lint.context, word: lint.word,
      suggestions: lint.suggestions || [],
      problem: text.slice(lint.start, lint.end),
    })).sort((a, b) => a.start - b.start);
    draw();
  });
}

// The lints moved over the single edit that took `lintedText` to `now`:
// where one can't be placed, the field is linted again.
function remapOverEdit(now) {
  const edit = singleEdit(lintedText, now);
  if (!edit) return false;
  const kept = [];
  for (const lint of lints) {
    const span = remapSpan([lint.start, lint.end], edit);
    if (!span) continue;
    const [start, end] = span;
    lint.start = start;
    lint.end = end;
    lint.problem = now.slice(start, end);
    kept.push(lint);
  }
  lints = kept;
  shownText = now;
  return true;
}

// The field's text changed under the lints: they move with it, and where
// any moved, the problem words are checked again against the text now there.
function textEdited(now) {
  if (now === shownText) { draw(); return; }
  if (shownText === lintedText && singleEdit(shownText, now)) {
    if (remapOverEdit(now)) { draw(); return; }
  }
  ask(now);
}

// MARK: The style the page gets, and the underlines.

let styleEl = null;
let useHighlights = false;

// Custom Highlights paint where a page lets them: probed once (the API is
// there, and it can take a range), the way lint-framework checks, minus its
// automated-driver check — eGlu's pages are never driven.
function probeHighlights() {
  try {
    if (!('highlights' in CSS) || typeof Highlight !== 'function') return false;
    const probe = new Highlight();
    CSS.highlights.set('eglu-probe', probe);
    CSS.highlights.delete('eglu-probe');
    return true;
  } catch (_) {
    return false;
  }
}

function addStyle() {
  if (styleEl) return;
  styleEl = document.createElement('style');
  styleEl.id = 'eglu-writing';
  let css = '';
  for (const kind of Object.keys(KIND_COLORS)) {
    const color = KIND_COLORS[kind];
    const name = 'eglu-' + kind.toLowerCase();
    css += `::highlight(${name}){text-decoration: underline ${color} solid 2px;` +
      `text-underline-offset: 3px;background-color: ${color}1f;}`;
  }
  styleEl.textContent = css;
  (document.head || document.documentElement).appendChild(styleEl);
}

// The lints' ranges under each kind, for CSS.highlights; the highlight
// name is eglu-<kind> lowercased (Decided 4).
function paintHighlights() {
  for (const name of Array.from(CSS.highlights.keys())) {
    if (name.startsWith('eglu-')) CSS.highlights.delete(name);
  }
  if (!field || fieldKind !== 'rich') return;
  const byKind = new Map();
  for (const lint of lints) {
    const range = rangeFor(field, lint.start, lint.end);
    if (range.collapsed) continue;
    const name = 'eglu-' + lint.kind.toLowerCase();
    if (!byKind.has(name)) byKind.set(name, []);
    byKind.get(name).push(range);
  }
  for (const [name, ranges] of byKind) {
    CSS.highlights.set(name, new Highlight(...ranges));
  }
}

function clearHighlights() {
  if (!('highlights' in CSS)) return;
  for (const name of Array.from(CSS.highlights.keys())) {
    if (name.startsWith('eglu-')) CSS.highlights.delete(name);
  }
}

// MARK: The boxes (textarea and input, and contenteditable without
// highlights), the mirror and the host they are drawn in (Decided 5-6).

// One eglu-writing element in the field's nearest non-editable ancestor,
// closed root; everything in it is pointer-events: none but the card.
let hostEl = null;
let hostRoot = null;
let boxLayer = null;
let cardAnchor = null;
let cardEl = null;

function renderHost() {
  if (hostEl) return hostRoot;
  hostEl = document.createElement('eglu-writing');
  hostEl.style.cssText = 'all:initial;position:absolute;left:0;top:0;width:0;height:0;z-index:2147483646;';
  hostRoot = hostEl.attachShadow({ mode: 'closed' });
  hostRoot.innerHTML =
    '<div id="layer" style="position:absolute;inset:0;pointer-events:none;"></div>' +
    '<div id="anchor" style="position:absolute;visibility:hidden;anchor-name:--eglu-word;"></div>' +
    '<div id="card" popover="manual" style="position-anchor:--eglu-word;position-area:block-end span-inline-end;' +
    'position-try-fallbacks:flip-block, flip-inline;margin:0;margin-block-start:6px;' +
    'max-height:var(--eglu-card-room, none);overflow-y:auto;pointer-events:auto;"></div>';
  boxLayer = hostRoot.getElementById('layer');
  cardAnchor = hostRoot.getElementById('anchor');
  cardEl = hostRoot.getElementById('card');
  (renderAncestor(field) || document.body).appendChild(hostEl);
  return hostRoot;
}

// Where the host element's boxes sit: the ancestor it was appended to, in
// the coordinates Decided 5 names (its rect, border and scroll, and any
// scale it is under).
function hostOrigin() {
  const container = hostEl.parentElement || document.body;
  const rect = container.getBoundingClientRect();
  const scale = container.offsetWidth ? rect.width / container.offsetWidth : 1;
  return { container, rect, scale };
}

// A lint's boxes in a form field, measured on a hidden mirror of the field
// (TextFieldRange): the same font and wrap, the same scroll, a <span> at the
// lint's words, its client rects the lint's underline segments.
let mirror = null;
function mirrorOf(field) {
  if (!mirror) {
    mirror = document.createElement('div');
    mirror.setAttribute('aria-hidden', 'true');
    document.body.appendChild(mirror);
  }
  const view = getComputedStyle(field);
  const copy = [
    'fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'fontVariant', 'fontStretch',
    'letterSpacing', 'lineHeight', 'textAlign', 'textTransform', 'textIndent',
    'wordSpacing', 'whiteSpace', 'overflowWrap', 'wordBreak', 'tabSize', 'direction',
    'boxSizing', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
    'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth',
    'borderTopStyle', 'borderRightStyle', 'borderBottomStyle', 'borderLeftStyle',
  ];
  let css = 'position:absolute;visibility:hidden;overflow:hidden;pointer-events:none;' +
    `top:${field.offsetTop}px;left:${field.offsetLeft}px;` +
    `width:${view.width};height:${view.height};`;
  for (const name of copy) css += `${name.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase())}:${view[name]};`;
  mirror.style.cssText = css;
  // Inside the field's own offsetParent so offsetTop/offsetLeft mean the
  // same; the mirror never scrolls — the inner text is shifted instead.
  if (mirror.parentElement !== field.offsetParent) {
    (field.offsetParent || document.body).appendChild(mirror);
  }
  return mirror;
}

// The rects a lint covers in a form field, in the host's coordinates.
function formRects(lint) {
  const field = /** @type {HTMLTextAreaElement|HTMLInputElement} */ (fieldEl());
  const text = field.value;
  const node = mirrorOf(field);
  node.textContent = '';
  const before = document.createTextNode(text.slice(0, lint.start));
  const mark = document.createElement('span');
  mark.textContent = text.slice(lint.start, lint.end) || '​';
  const after = document.createTextNode(text.slice(lint.end));
  const inner = document.createElement('div');
  inner.append(before, mark, after);
  inner.style.transform = `translate(${-field.scrollLeft}px, ${-field.scrollTop}px)`;
  node.appendChild(inner);
  const rects = Array.from(mark.getClientRects());
  const { rect, scale } = hostOrigin();
  return rects
    .filter((r) => r.width > 0 && r.height > 0)
    .map((r) => ({
      left: (r.left - rect.left - containerClientLeft() + (hostEl.parentElement || document.body).scrollLeft) / scale,
      top: (r.top - rect.top - containerClientTop() + (hostEl.parentElement || document.body).scrollTop) / scale,
      width: r.width / scale,
      height: r.height / scale,
    }));
}

function containerClientLeft() { return (hostEl.parentElement || document.body).clientLeft; }
function containerClientTop() { return (hostEl.parentElement || document.body).clientTop; }

// A lint's boxes in a contenteditable, from its Range's client rects.
function richRects(lint) {
  const range = rangeFor(field, lint.start, lint.end);
  const { rect, scale } = hostOrigin();
  const container = hostEl.parentElement || document.body;
  return Array.from(range.getClientRects())
    .filter((r) => r.width > 0 && r.height > 0)
    .map((r) => ({
      left: (r.left - rect.left - container.clientLeft + container.scrollLeft) / scale,
      top: (r.top - rect.top - container.clientTop + container.scrollTop) / scale,
      width: r.width / scale,
      height: r.height / scale,
    }));
}

function fieldEl() { return field; }

// Draw the underlines for the lints now held.
function draw() {
  if (stopped) return;
  if (useHighlights && field && fieldKind === 'rich') {
    paintHighlights();
    clearBoxes();
    return;
  }
  clearHighlights();
  drawBoxes();
}

function drawBoxes() {
  if (!field || !document.contains(field)) { clearBoxes(); return; }
  renderHost();
  boxLayer.textContent = '';
  for (const lint of lints) {
    const rects = fieldKind === 'form' ? formRects(lint) : richRects(lint);
    lint.boxes = rects;
    for (const r of rects) {
      const box = document.createElement('div');
      box.style.cssText = `position:absolute;pointer-events:none;left:${r.left}px;top:${r.top}px;` +
        `width:${r.width}px;height:${r.height}px;` +
        `border-bottom:2px solid ${kindColor(lint.kind)};background:${kindColor(lint.kind)}1f;`;
      boxLayer.appendChild(box);
    }
  }
}

function clearBoxes() {
  if (boxLayer) boxLayer.textContent = '';
  if (mirror) { mirror.textContent = ''; }
}

// MARK: The card (Decided 7-9): the kind, the message, the fixes.

// Harper's messages are English Markdown; only inline code and emphasis
// are drawn, as elements — never innerHTML.
function renderMarkdown(text, into) {
  const parts = text.split(/(`[^`]+`|\*[^*]+\*)/g);
  for (const part of parts) {
    if (!part) continue;
    if (part.length > 2 && part.startsWith('`') && part.endsWith('`')) {
      const code = document.createElement('code');
      code.textContent = part.slice(1, -1);
      into.appendChild(code);
    } else if (part.length > 2 && part.startsWith('*') && part.endsWith('*')) {
      const em = document.createElement('em');
      em.textContent = part.slice(1, -1);
      into.appendChild(em);
    } else {
      into.appendChild(document.createTextNode(part));
    }
  }
}

const str = (key, fallback) => strings[key] || fallback;

function suggestionLabel(lint, suggestion) {
  const flagged = lint.problem;
  const visible = (text) => text.trim().length > 0;
  if (suggestion.replace !== undefined) {
    return { text: visible(suggestion.replace) ? suggestion.replace : suggestion.description || '', strike: false };
  }
  if (suggestion.insert !== undefined) {
    return { text: visible(suggestion.insert) ? flagged + suggestion.insert : suggestion.description || '', strike: false };
  }
  // A removal: the word, struck through.
  return { text: visible(flagged) ? flagged : suggestion.description || '', strike: true };
}

const CARD_CSS =
  ':host{all:initial;}' +
  '.eglu-card{width:320px;max-width:calc(100vw - 24px);border-radius:16px;overflow:hidden;' +
  'border:0.5px solid rgb(0 0 0 / 0.12);box-shadow:0 12px 32px rgb(0 0 0 / 0.18), 0 2px 8px rgb(0 0 0 / 0.10);' +
  'background:rgb(255 255 255 / 0.72);-webkit-backdrop-filter:blur(24px) saturate(180%);backdrop-filter:blur(24px) saturate(180%);' +
  'font:13px/1.35 -apple-system, system-ui;color:rgb(0 0 0 / 0.85);}' +
  '.eglu-head{display:flex;align-items:center;gap:6px;padding:7px 7px 0 14px;}' +
  '.eglu-dot{width:8px;height:8px;border-radius:50%;}' +
  '.eglu-kind{font-size:11px;font-weight:600;color:rgb(0 0 0 / 0.5);}' +
  '.eglu-close{margin-left:auto;width:22px;height:22px;border:0;border-radius:50%;background:transparent;' +
  'font-size:10px;font-weight:600;color:rgb(0 0 0 / 0.5);cursor:default;}' +
  '.eglu-close:hover{background:rgb(0 0 0 / 0.08);color:rgb(0 0 0 / 0.85);}' +
  '.eglu-body{padding:4px 14px 14px;}' +
  '.eglu-msg{margin:0 0 12px;line-height:1.4;}' +
  '.eglu-msg code{font-weight:600;}' +
  '.eglu-sugs{display:flex;flex-wrap:wrap;gap:6px;}' +
  '.eglu-sug{min-width:40px;max-width:100%;padding:5px 12px;border:0;border-radius:999px;' +
  'background:rgb(0 0 0 / 0.08);font-size:13px;color:rgb(0 0 0 / 0.85);white-space:nowrap;' +
  'overflow:hidden;text-overflow:ellipsis;cursor:default;}' +
  '.eglu-sug:hover{background:rgb(0 0 0 / 0.12);}' +
  '.eglu-sug.eglu-first{background:rgb(0 0 0 / 0.85);color:#fff;font-weight:600;}' +
  '.eglu-foot{display:flex;align-items:center;gap:0;padding:7px;' +
  'border-top:0.5px solid rgb(0 0 0 / 0.10);}' +
  '.eglu-act{padding:4px 7px;border:0;border-radius:999px;background:transparent;font-size:12px;' +
  'color:rgb(0 0 0 / 0.5);white-space:nowrap;cursor:default;}' +
  '.eglu-act:hover{background:rgb(0 0 0 / 0.08);color:rgb(0 0 0 / 0.85);}' +
  '.eglu-gap{flex:1;}' +
  '@media (prefers-color-scheme: dark){' +
  '.eglu-card{background:rgb(40 40 44 / 0.72);border-color:rgb(255 255 255 / 0.14);color:rgb(255 255 255 / 0.85);}' +
  '.eglu-kind,.eglu-act{color:rgb(255 255 255 / 0.55);}' +
  '.eglu-close{color:rgb(255 255 255 / 0.55);}' +
  '.eglu-sug{background:rgb(255 255 255 / 0.14);color:rgb(255 255 255 / 0.9);}' +
  '.eglu-sug.eglu-first{background:rgb(255 255 255 / 0.92);color:#000;}' +
  '.eglu-foot{border-top-color:rgb(255 255 255 / 0.14);}' +
  '.eglu-close:hover,.eglu-act:hover,.eglu-sug:hover{background:rgb(255 255 255 / 0.18);color:#fff;}' +
  '}';

// The lint the card is open on, or null.
let cardLint = null;

function buildCard(lint) {
  const card = document.createElement('div');
  card.className = 'eglu-card';
  const style = document.createElement('style');
  style.textContent = CARD_CSS;
  card.appendChild(style);

  const head = document.createElement('div');
  head.className = 'eglu-head';
  const dot = document.createElement('span');
  dot.className = 'eglu-dot';
  dot.style.background = kindColor(lint.kind);
  const kind = document.createElement('span');
  kind.className = 'eglu-kind';
  kind.textContent = kindName(lint.kind);
  kind.title = lint.rule || '';
  const close = document.createElement('button');
  close.className = 'eglu-close';
  close.textContent = '✕';
  close.setAttribute('aria-label', str('card.close', 'Close'));
  close.addEventListener('click', () => closeCard());
  head.append(dot, kind, close);

  const body = document.createElement('div');
  body.className = 'eglu-body';
  const message = document.createElement('p');
  message.className = 'eglu-msg';
  renderMarkdown(lint.message || '', message);
  body.appendChild(message);
  if (lint.suggestions.length) {
    const sugs = document.createElement('div');
    sugs.className = 'eglu-sugs';
    lint.suggestions.slice(0, 5).forEach((suggestion, index) => {
      const button = document.createElement('button');
      button.className = 'eglu-sug' + (index === 0 ? ' eglu-first' : '');
      const label = suggestionLabel(lint, suggestion);
      button.textContent = label.text;
      if (label.strike) button.style.textDecoration = 'line-through';
      if (suggestion.description) button.title = suggestion.description;
      button.addEventListener('click', () => apply(lints.indexOf(lint), index));
      sugs.appendChild(button);
    });
    body.appendChild(sugs);
  }

  const foot = document.createElement('div');
  foot.className = 'eglu-foot';
  const ignore = document.createElement('button');
  ignore.className = 'eglu-act';
  ignore.textContent = str('card.ignore', 'Ignore');
  ignore.addEventListener('click', () => actOn(lint, 'ignore'));
  foot.appendChild(ignore);
  if (lint.kind === 'Spelling' && lint.word) {
    const add = document.createElement('button');
    add.className = 'eglu-act';
    add.textContent = str('card.addToDictionary', 'Add to Dictionary');
    add.addEventListener('click', () => actOn(lint, 'addWord'));
    foot.appendChild(add);
  }
  const gap = document.createElement('span');
  gap.className = 'eglu-gap';
  const off = document.createElement('button');
  off.className = 'eglu-act';
  off.textContent = str('card.disableRule', 'Turn Off This Rule');
  off.title = lint.rule || '';
  off.addEventListener('click', () => actOn(lint, 'disableRule'));
  foot.append(gap, off);

  card.append(head, body, foot);
  return card;
}

// The boxes a lint is under, for a click's hit-test: the drawn ones, or
// measured fresh where highlights did the drawing.
function boxesOf(lint) {
  if (lint.boxes) return lint.boxes;
  try {
    // Highlights draw nothing: the host is made here for the measuring.
    renderHost();
    return fieldKind === 'form' ? formRects(lint) : richRects(lint);
  } catch (_) {
    return [];
  }
}

const supportsAnchors = CSS.supports('anchor-name: --a') && CSS.supports('position-area: block-end span-inline-end');
const supportsPopover = typeof HTMLElement.prototype.showPopover === 'function';

// The part of the window the page shows in: the visual viewport, which
// iOS's keyboard takes part of, or the window itself where there is none
// (every desktop browser). Card placement stays inside it (Decided 4).
function viewportBox() {
  const vv = window.visualViewport;
  return vv
    ? { left: vv.offsetLeft, top: vv.offsetTop, width: vv.width, height: vv.height }
    : { left: 0, top: 0, width: innerWidth, height: innerHeight };
}

// The card's tallest height is what the visual viewport leaves of the
// page: the anchor-positioned card is bound to it by the
// --eglu-card-room variable, and the keyboard's coming or going changes
// it again (Decided 4).
function syncViewportRoom() {
  if (cardEl) cardEl.style.setProperty('--eglu-card-room', Math.max(viewportBox().height - 12, 0) + 'px');
}

// While the card is open the viewport is listened to as the scroll is:
// the keyboard, and the page sliding under it, move the card.
let viewportWatched = false;
function onViewport() {
  syncViewportRoom();
  onScrollOrResize();
}
function watchViewport(on) {
  const vv = window.visualViewport;
  if (!vv || viewportWatched === on) return;
  viewportWatched = on;
  const method = on ? 'addEventListener' : 'removeEventListener';
  vv[method]('resize', onViewport);
  vv[method]('scroll', onViewport);
}

function openCard(lint) {
  if (cardLint === lint) { return; }
  closeCard();
  const rects = boxesOf(lint);
  if (!rects.length) return;
  renderHost();
  const first = rects[0];
  cardAnchor.style.left = first.left + 'px';
  cardAnchor.style.top = first.top + 'px';
  cardAnchor.style.width = first.width + 'px';
  cardAnchor.style.height = first.height + 'px';
  cardEl.textContent = '';
  cardEl.appendChild(buildCard(lint));
  // The card never takes the field's focus: its presses are cancelled
  // before the page hears of a blur (Decided 9).
  if (!cardEl.dataset.wired) {
    cardEl.dataset.wired = '1';
    cardEl.addEventListener('pointerdown', (event) => event.preventDefault());
  }
  syncViewportRoom();
  watchViewport(true);
  // Placed by hand where there is no anchor positioning or no popover:
  // sized and shown first so its measure is taken, then put under the
  // word inside the visual viewport, or above it.
  const byHand = !supportsAnchors || !supportsPopover;
  if (byHand && supportsPopover) cardEl.style.positionAnchor = 'none';
  if (byHand && !supportsPopover) cardEl.style.display = 'block';
  if (supportsPopover) cardEl.showPopover();
  if (byHand) placeCardBelow(first);
  cardLint = lint;
  post({ kind: 'card', open: true });
}

// Under the word's line, inside the visual viewport (the part of the page
// a touch keyboard leaves), and above the word where that part has no
// room below. Where both would reach outside it, below is kept.
function placeCardBelow(rect) {
  cardEl.style.position = 'absolute';
  const view = viewportBox();
  const { rect: host, scale } = hostOrigin();
  const container = hostEl.parentElement || document.body;
  // The word measured the way the viewport is, in client coordinates.
  const wordLeft = rect.left * scale + host.left + container.clientLeft - container.scrollLeft;
  const wordTop = rect.top * scale + host.top + container.clientTop - container.scrollTop;
  const wordBottom = wordTop + rect.height * scale;
  const gap = 6;
  const cardWidth = cardEl.offsetWidth || 320;
  const cardHeight = cardEl.offsetHeight || 160;
  const below = wordBottom + gap + cardHeight <= view.top + view.height;
  const above = wordTop - gap - cardHeight >= view.top;
  const clientTop = below || !above ? wordBottom + gap : wordTop - gap - cardHeight;
  const clientLeft = Math.min(Math.max(wordLeft, view.left + gap),
    Math.max(view.left + gap, view.left + view.width - cardWidth - gap));
  if (cardEl.matches(':popover-open')) {
    // A popover is placed against the window itself, in client coordinates.
    cardEl.style.left = clientLeft + 'px';
    cardEl.style.top = clientTop + 'px';
  } else {
    cardEl.style.left = (clientLeft - host.left - container.clientLeft + container.scrollLeft) / scale + 'px';
    cardEl.style.top = (clientTop - host.top - container.clientTop + container.scrollTop) / scale + 'px';
  }
}

function closeCard() {
  if (!cardLint) return;
  cardLint = null;
  watchViewport(false);
  try { if (cardEl && cardEl.matches(':popover-open')) cardEl.hidePopover(); } catch (_) {}
  if (cardEl) { cardEl.style.display = ''; cardEl.textContent = ''; }
  post({ kind: 'card', open: false });
}

// MARK: Ignore, Add to Dictionary, Turn Off This Rule.

function actOn(lint, action) {
  if (action === 'ignore') {
    post({ kind: 'ignore', lint: { context: lint.context } });
    lints = lints.filter((l) => l !== lint);
  } else if (action === 'addWord') {
    post({ kind: 'addWord', word: lint.word });
    lints = lints.filter((l) => l !== lint);
  } else if (action === 'disableRule') {
    post({ kind: 'disableRule', rule: lint.rule });
    lints = lints.filter((l) => l.rule !== lint.rule);
  }
  closeCard();
  draw();
}

// MARK: Applying a fix so the page's own Undo takes it (Decided 10).

// Write `text` over the field's selection the way a person would: the
// command the page's own undo stack knows. Answers whether it went.
function insertText(field, text) {
  try {
    field.focus();
    return document.execCommand('insertText', false, text);
  } catch (_) {
    return false;
  }
}

// The value setter the element was made with, for where execCommand says
// no: set as the prototype does, then an input event of the kind a fix
// produces.
function replaceFormValue(field, start, end, text) {
  const proto = field.localName === 'textarea' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
  const next = field.value.slice(0, start) + text + field.value.slice(end);
  setter.call(field, next);
  const point = start + text.length;
  field.setSelectionRange(point, point);
  field.dispatchEvent(new InputEvent('input', { inputType: 'insertReplacementText', data: text, bubbles: true }));
}

// A beforeinput event with the replacement spelled out, as Slate and
// CKEditor5 listen for; the range it means in targetRanges where the
// engine builds them.
function dispatchBeforeInput(root, inputType, text, range) {
  const options = { inputType, data: text, bubbles: true, cancelable: true, composed: true };
  if (range && typeof StaticRange === 'function') {
    try {
      options.targetRanges = [new StaticRange({ startContainer: range.startContainer, startOffset: range.startOffset, endContainer: range.endContainer, endOffset: range.endOffset })];
    } catch (_) {}
  }
  return root.dispatchEvent(new InputEvent('beforeinput', options));
}

// The range's own words changed, for where no better way was heard: the
// DOM written directly, then an input event so the editor learns of it.
function replaceRangeContents(range, text) {
  range.deleteContents();
  range.insertNode(document.createTextNode(text));
  range.collapse(false);
}

function apply(lintIndex, suggestionIndex) {
  const lint = lints[lintIndex];
  if (!lint || !field) { closeCard(); return false; }
  const suggestion = lint.suggestions[suggestionIndex];
  if (!suggestion) { closeCard(); return false; }
  const now = fieldText(field, fieldKind).text;
  // Only where the words the lint was raised on are still the words there;
  // anything else asks for a fresh pass (Decided 10).
  if (now.slice(lint.start, lint.end) !== lint.problem) {
    closeCard();
    ask(now);
    return false;
  }
  const replacement = suggestion.replace !== undefined ? suggestion.replace
    : suggestion.insert !== undefined ? lint.problem + suggestion.insert
    : '';
  const kind = editorKind(field);
  let done = false;
  if (kind === 'form') {
    field.focus();
    field.setSelectionRange(lint.start, lint.end);
    done = insertText(field, replacement);
    if (!done) { replaceFormValue(field, lint.start, lint.end, replacement); done = true; }
  } else {
    const range = rangeFor(field, lint.start, lint.end);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    if (kind === 'lexical' || kind === 'slate' || kind === 'ckeditor') {
      const unhandled = dispatchBeforeInput(field, 'insertReplacementText', replacement, range);
      if (unhandled) {
        replaceRangeContents(range, replacement);
        field.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertReplacementText', data: replacement }));
      }
      done = true;
    } else if (kind === 'draft') {
      const unhandled = dispatchBeforeInput(field, 'insertText', replacement, null);
      if (unhandled) {
        replaceRangeContents(range, replacement);
        field.dispatchEvent(new InputEvent('input', { bubbles: true }));
      }
      done = true;
    } else {
      // ProseMirror, Quill, Notion and the rest: the page's own insert, so
      // its undo history holds the change.
      done = insertText(field, replacement);
      if (!done) {
        replaceRangeContents(range, replacement);
        field.dispatchEvent(new InputEvent('input', { bubbles: true }));
        done = true;
      }
    }
  }
  closeCard();
  if (done) {
    // The field holds the fix: what remains is linted again once the page
    // has settled it, and the stale lints are dropped at once.
    lints = lints.filter((l) => l !== lint);
    lintedText = '';
    draw();
    setTimeout(() => { if (field && document.contains(field)) lintNow(); }, 60);
  }
  return done;
}

function acceptFirst() {
  if (!cardLint || !cardLint.suggestions.length) return false;
  return apply(lints.indexOf(cardLint), 0);
}

// MARK: The field on the page, and when it is linted (Decided 3).

let field = null;
let fieldKind = null;
let lintTimer = 0;
let restTimer = 0;
let pollTimer = 0;
let scrollTick = false;
let stopped = false;
let fieldObserver = null;

function currentText() {
  return field ? fieldText(field, fieldKind).text : '';
}

function lintNow() {
  if (!field || stopped) return;
  const text = currentText();
  if (!text.trim()) { lints = []; lintedText = text; shownText = text; draw(); return; }
  ask(text);
}

function lintSoon() {
  clearTimeout(lintTimer);
  lintTimer = setTimeout(lintNow, 300);
}

// The 1s check while the field is focused, for edits no input event
// reported and for the boxes to follow a rewrap or a zoom.
function poll() {
  if (!field || stopped) return;
  if (!document.contains(field)) { blur(); return; }
  const now = currentText();
  if (now !== shownText) {
    textEdited(now);
    return;
  }
  if (fieldKind !== 'form' || !useHighlights) {
    // No text change: the boxes only move (scroll, rewrap, resize).
    draw();
  }
}

function focus(target) {
  if (stopped) return;
  const kind = checkable(target);
  if (!kind) return;
  if (field === target) return;
  blur();
  field = target;
  fieldKind = kind;
  shownText = currentText();
  lintNow();
  clearInterval(pollTimer);
  pollTimer = setInterval(poll, 1000);
  if (fieldObserver) fieldObserver.disconnect();
  fieldObserver = new ResizeObserver(onScrollOrResize);
  fieldObserver.observe(field);
}

function blur() {
  field = null;
  fieldKind = null;
  lints = [];
  lintedText = '';
  shownText = '';
  asking = 0;
  clearTimeout(lintTimer);
  clearTimeout(restTimer);
  clearInterval(pollTimer);
  if (fieldObserver) { fieldObserver.disconnect(); fieldObserver = null; }
  closeCard();
  clearHighlights();
  clearBoxes();
  if (hostEl) { hostEl.remove(); hostEl = null; hostRoot = null; boxLayer = null; cardAnchor = null; cardEl = null; }
}

// MARK: Events (Decided 3, 9).

const INPUT_EVENTS = ['focus', 'keyup', 'keydown', 'paste', 'change', 'scroll', 'input'];
const PAGE_EVENTS = ['resize', 'scroll', 'keyup', 'keydown', 'input', 'compositionend', 'selectionchange'];

// Where the caret rests: a selection sitting in a lint's span 150ms opens
// its card. Any move or type cancels the wait.
function caretRest() {
  clearTimeout(restTimer);
  restTimer = setTimeout(() => {
    if (!field || cardLint) return;
    const selection = getSelection();
    let caret = -1;
    if (fieldKind === 'form') {
      if (document.activeElement !== field || field.selectionStart !== field.selectionEnd) return;
      caret = field.selectionStart;
    } else {
      if (!selection.rangeCount || !selection.isCollapsed) return;
      const node = selection.anchorNode;
      if (!field.contains(node)) return;
      // The caret's offset in the text the linter saw: walk as rangeFor does.
      caret = offsetOfCaret(node, selection.anchorOffset);
      if (caret < 0) return;
    }
    const lint = lints.find((l) => l.start <= caret && caret <= l.end);
    if (lint) openCard(lint);
  }, 150);
}

// The caret's text offset in a contenteditable, walking as richText does.
function offsetOfCaret(node, nodeOffset) {
  let offset = 0;
  let found = -1;
  const BLOCK_END = /^(address|article|aside|blockquote|dd|details|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hgroup|hr|li|main|nav|ol|p|pre|section|summary|table|tbody|td|tfoot|th|thead|tr|ul)$/;
  const walk = (el) => {
    if (found >= 0) return;
    for (let child = el.firstChild; child; child = child.nextSibling) {
      if (child === node && node.nodeType === 3) { found = offset + nodeOffset; return; }
      if (child.nodeType === 3) { offset += child.data.length; continue; }
      if (child.nodeType !== 1) continue;
      if (['script', 'style', 'noscript', 'template'].includes(child.localName)) continue;
      if (child === node) { found = offset + nodeOffset; return; }
      if (child.contains(node)) { walk(child); if (found >= 0) return; continue; }
      if (child.localName === 'br') { offset += 1; continue; }
      walk(child);
      if (BLOCK_END.test(child.localName)) offset += 1;
    }
  };
  if (node === field) { found = nodeOffset === 0 ? 0 : -1; return found; }
  walk(field);
  return found;
}

function onPointerDown(event) {
  if (!field) return;
  // A press in the card is its own: the field keeps focus and it stays open.
  if (cardEl && event.composedPath().includes(hostEl)) return;
  // Highlights draw no boxes: the host is made here so the hit-test has one.
  if (!hostEl) renderHost();
  const { rect, scale } = hostOrigin();
  const container = hostEl ? (hostEl.parentElement || document.body) : null;
  const lint = lints.find((l) => boxesOf(l).some((box) => {
    const left = box.left * scale + rect.left + container.clientLeft - container.scrollLeft;
    const top = box.top * scale + rect.top + container.clientTop - container.scrollTop;
    return event.clientX >= left && event.clientX <= left + box.width * scale &&
      event.clientY >= top && event.clientY <= top + box.height * scale;
  }));
  if (lint) { openCard(lint); return; }
  // Anywhere else is an outside click: the card goes.
  closeCard();
}

function onKeyDown(event) {
  // Esc is swallowed only while the card is open (Decided 9).
  if (event.key === 'Escape' && cardLint) {
    event.preventDefault();
    event.stopPropagation();
    closeCard();
    return;
  }
  clearTimeout(restTimer);
}

function onScrollOrResize() {
  if (!field) return;
  if (scrollTick) return;
  scrollTick = true;
  requestAnimationFrame(() => {
    scrollTick = false;
    if (!field || stopped) return;
    if (!useHighlights || fieldKind === 'form') draw();
    // A card whose word went off the screen closes (Decided 9).
    if (cardLint) {
      const rects = boxesOf(cardLint);
      const view = viewportBox();
      const onScreen = rects.some((r) => {
        const { rect, scale } = hostOrigin();
        const container = hostEl.parentElement || document.body;
        const top = r.top * scale + rect.top + container.clientTop - container.scrollTop;
        return top > view.top - r.height && top < view.top + view.height;
      });
      if (!onScreen) closeCard();
      else if (!supportsAnchors || !supportsPopover) placeCardBelow(rects[0]);
    }
  });
}

function install() {
  if (stopped) return;
  if (useHighlights = probeHighlights()) addStyle();
  document.addEventListener('focusin', (event) => focus(event.target), { capture: true, passive: true });
  document.addEventListener('focusout', (event) => {
    if (event.target === field) blur();
  }, { capture: true, passive: true });
  for (const name of PAGE_EVENTS) {
    const listener = {
      resize: onScrollOrResize,
      scroll: onScrollOrResize,
      keyup: () => {},
      keydown: onKeyDown,
      input: (event) => {
        if (field && event.target === field) { closeCard(); lintSoon(); }
      },
      compositionend: (event) => { if (field && event.target === field) lintSoon(); },
      selectionchange: caretRest,
    }[name];
    document.addEventListener(name, (event) => listener(event), { capture: true, passive: true });
  }
  document.addEventListener('pointerdown', onPointerDown, { capture: true, passive: true });
  // Fonts arriving later change where the words sit: the boxes move then.
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(() => { if (field && !stopped) draw(); });
  }
}

function stop() {
  stopped = true;
  blur();
  if (styleEl) { styleEl.remove(); styleEl = null; }
  if (mirror) { mirror.remove(); mirror = null; }
  // Everything Decided 16 allowed is gone: the style, the hosts, the mirror.
}

install();

return {
  apply,
  acceptFirst,
  stop,
  // For the app's checks and the tests'.
  lints: () => lints,
  field: () => field,
  cardOpen: () => cardLint != null,
  // The card's rect as the viewport sees it: the tests' measure of
  // placement (writing.mjs).
  cardRect: () => {
    if (!cardEl || !cardLint) return null;
    const r = cardEl.getBoundingClientRect();
    return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height };
  },
};
})();
