// Grammar and spelling in a page's own fields, with Harper on the Mac
// (WritingChecker.swift, WritingHandler.swift).
//
// It runs at document end in the app's own content world, in the main frame
// only, and only where Settings › Writing is on and the site isn't off.
// It underlines problems on the page's own text (WebKit's Custom Highlights
// in a contenteditable, boxes over a field's words in a textarea or input)
// and opens a card beside the word with the fixes: choosing one writes the
// text the way the page's own Undo still takes back. Its approach and
// several parts follow Harper's lint-framework (Apache-2.0).
//
// What the page gets back through the "egluWriting" handler is English it
// typed: nothing else leaves this world, and nothing of the page's is read
// but the focused field's text.
window.__egluWriting = (() => {
'use strict';
// Put in again by the app (checking turned back on with the page open):
// the one already here starts again instead of a second beside it.
if (window.__egluWriting) {
  window.__egluWriting.start();
  return window.__egluWriting;
}

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

// A contenteditable's editing host: the outermost editable element, whose
// parent is not. The focus can land on an editable element inside it, and
// the field is always the whole host (Decided 1).
function editingHost(el) {
  let host = el;
  while (host.parentElement && host.parentElement.isContentEditable) host = host.parentElement;
  return host;
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
// field that isn't itself editable.
function renderAncestor(field) {
  let node = field.parentElement;
  while (node && node.isContentEditable) node = node.parentElement;
  return node || document.body;
}

// MARK: A field's text, and a span in it back as a Range.

// Elements whose text is never on screen as the person's words.
const SKIPPED = /^(script|style|noscript|template)$/;
// Computed displays that put an element on lines of its own (Decided 3's
// block elements): the text breaks before and after it, as it reads.
const LINE_DISPLAYS = /^(block|flow-root|list-item|table|table-row|table-caption|flex|grid)$/;

// One walk of a contenteditable, for its text and for every place in it:
// text nodes as they are, "\n" for a <br> and around an element on lines
// of its own, nothing for what isn't shown. The text the linter sees, a
// lint's Range and the caret's offset all come from the same walk, so
// they always agree.
function richMap(root) {
  const textStart = new Map();
  const texts = [];
  // Where each "\n" sits in the DOM: before or after the element that made it.
  const breaks = [];
  const elementStart = new Map();
  const elementEnd = new Map();
  let text = '';
  const lineBreak = (container, offset) => {
    breaks.push({ start: text.length, container, offset });
    text += '\n';
  };
  const walk = (el) => {
    let index = 0;
    for (let child = el.firstChild; child; child = child.nextSibling, index++) {
      if (child.nodeType === 3) {
        textStart.set(child, text.length);
        texts.push(child);
        text += child.data;
        continue;
      }
      if (child.nodeType !== 1 || SKIPPED.test(child.localName)) continue;
      if (child.localName === 'br') {
        elementStart.set(child, text.length);
        lineBreak(el, index + 1);
        elementEnd.set(child, text.length);
        continue;
      }
      const display = getComputedStyle(child).display;
      if (display === 'none') continue;
      const block = LINE_DISPLAYS.test(display);
      if (block && text && !text.endsWith('\n')) lineBreak(el, index);
      elementStart.set(child, text.length);
      walk(child);
      elementEnd.set(child, text.length);
      if (block && text && !text.endsWith('\n')) lineBreak(el, index + 1);
    }
  };
  walk(root);
  return { root, text, texts, textStart, breaks, elementStart, elementEnd };
}

// The DOM place of a text offset: in the text node holding it (a start in
// the node it begins, an end in the node it closes), else at the line
// break there, else the root's edge.
function placeOf(map, offset, isEnd) {
  for (const node of map.texts) {
    const start = map.textStart.get(node);
    const end = start + node.data.length;
    if (isEnd ? offset > start && offset <= end : offset >= start && offset < end) return [node, offset - start];
  }
  for (const line of map.breaks) {
    if (line.start === offset || (isEnd && line.start + 1 === offset)) return [line.container, line.offset];
  }
  return offset <= 0 ? [map.root, 0] : [map.root, map.root.childNodes.length];
}

// The range covering `start` to `end` (UTF-16 offsets in the map's text).
function rangeFor(map, start, end) {
  const range = document.createRange();
  try {
    range.setStart(...placeOf(map, start, false));
    range.setEnd(...placeOf(map, end, true));
  } catch (_) {
    range.selectNodeContents(map.root);
    range.collapse(true);
  }
  return range;
}

// The text offset of a DOM place (the caret's) in the map's text: in a text
// node, its own; between an element's children, where the next child's
// text begins, or the element's own end; -1 where it is in nothing walked.
function offsetOf(map, node, nodeOffset) {
  if (node.nodeType === 3) {
    const start = map.textStart.get(node);
    return start === undefined ? -1 : start + Math.min(nodeOffset, node.data.length);
  }
  if (node.nodeType !== 1) return -1;
  const children = node.childNodes;
  for (let i = nodeOffset; i < children.length; i++) {
    const child = children[i];
    const start = child.nodeType === 3 ? map.textStart.get(child) : map.elementStart.get(child);
    if (start !== undefined) return start;
  }
  if (node === map.root) return map.text.length;
  const end = map.elementEnd.get(node);
  return end === undefined ? -1 : end;
}

function fieldText(field, kind) {
  if (kind === 'form') return { text: field.value, map: null };
  const map = richMap(field);
  return { text: map.text, map };
}

// MARK: Keeping lints on their words over an edit (spanMapping.ts).

// The one stretch that differs between `before` and `after`: how much of
// each end they share. Several edits collapse into one wider one, so the
// lints between them are dropped till the next answer.
function singleEdit(before, after) {
  if (before === after) return null;
  let start = 0;
  const shortest = Math.min(before.length, after.length);
  while (start < shortest && before[start] === after[start]) start++;
  let back = 0;
  while (back < before.length - start && back < after.length - start &&
         before[before.length - 1 - back] === after[after.length - 1 - back]) back++;
  const oldEnd = before.length - back;
  const newEnd = after.length - back;
  return { oldStart: start, oldEnd, delta: (newEnd - start) - (oldEnd - start) };
}

// A lint's span over the edit: the same before it, shifted after it, and
// none where the edit touches its words, whose message and fixes no longer
// hold.
function remapSpan(start, end, edit) {
  if (!edit || end <= edit.oldStart) return [start, end];
  if (start >= edit.oldEnd) return [start + edit.delta, end + edit.delta];
  return null;
}

// The lints placed for `now`, from the text each was placed for: those the
// edit touched, or whose words aren't the ones flagged any more, are gone.
function remapLints(now) {
  const kept = [];
  for (const lint of lints) {
    const span = lint.source === now ? [lint.start, lint.end]
      : remapSpan(lint.start, lint.end, singleEdit(lint.source, now));
    if (!span || now.slice(span[0], span[1]) !== lint.problem) continue;
    lint.start = span[0];
    lint.end = span[1];
    lint.source = now;
    kept.push(lint);
  }
  lints = kept;
  shownText = now;
}

// MARK: The lints, and asking the app for them (Decided 3).

let lints = [];
// The text the lints held now are placed for.
let shownText = '';
let asking = 0;
let askedSeq = 0;

const post = (message) => {
  try { return window.webkit.messageHandlers.egluWriting.postMessage(message); }
  catch (_) { return Promise.resolve(null); }
};

// The newest ask is the one answered: an answer to an older one is
// dropped. One for text the field no longer holds is placed over the edit
// made meanwhile, where its lints' words are still there.
function ask(text) {
  const seq = ++askedSeq;
  asking = seq;
  post({ kind: 'lint', seq, text }).then((answer) => {
    if (asking !== seq || stopped || !field) return;
    asking = 0;
    lints = (answer || []).map((lint) => ({
      start: lint.start, end: lint.end, kind: lint.kind, rule: lint.rule,
      message: lint.message, context: lint.context, word: lint.word,
      suggestions: lint.suggestions || [],
      problem: text.slice(lint.start, lint.end),
      source: text,
    })).sort((a, b) => a.start - b.start);
    const now = currentText();
    remapLints(now);
    draw();
    if (now !== text) lintSoon();
  });
}

// The field's text changed under the lints: they move with it, or go where
// the edit took their words; the field is linted again once typing stops.
function textEdited(now) {
  if (now !== shownText) remapLints(now);
  draw();
  lintSoon();
}

// MARK: The style the page gets, and the underlines.

let styleEl = null;
let useHighlights = false;

// Custom Highlights paint where a page lets them: probed once (the API is
// there, and it can take a range), the way lint-framework checks, minus its
// automated-driver check, as eGlu's pages are never driven.
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
function paintHighlights(map) {
  clearHighlights();
  if (!field || fieldKind !== 'rich') return;
  const byKind = new Map();
  for (const lint of lints) {
    const range = rangeFor(map, lint.start, lint.end);
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
  // The card is a popover: the UA's own popover style (a border, padding,
  // the canvas colour, scrolling) is undone, so only .eglu-card is seen.
  // The anchor is see-through, not hidden: a card anchored to a hidden box
  // is hidden with it (position-visibility's anchors-visible).
  hostRoot.innerHTML =
    '<style>' + CARD_CSS + '</style>' +
    '<div id="layer" style="position:absolute;inset:0;pointer-events:none;"></div>' +
    '<div id="anchor" style="position:absolute;opacity:0;pointer-events:none;anchor-name:--eglu-word;"></div>' +
    '<div id="card" popover="manual" style="position-anchor:--eglu-word;position-area:block-end span-inline-end;' +
    'position-try-fallbacks:flip-block, flip-inline;margin:6px 0;padding:0;border:0;background:transparent;' +
    'overflow:visible;pointer-events:auto;"></div>';
  boxLayer = hostRoot.getElementById('layer');
  cardAnchor = hostRoot.getElementById('anchor');
  cardEl = hostRoot.getElementById('card');
  // The card never takes the field's focus: its presses are cancelled
  // before the page hears of a blur (Decided 9).
  cardEl.addEventListener('pointerdown', (event) => event.preventDefault());
  cardEl.addEventListener('mousedown', (event) => event.preventDefault());
  (renderAncestor(field) || document.body).appendChild(hostEl);
  return hostRoot;
}

// Where the host's boxes are measured from: the host itself, wherever its
// containing block puts it (a static ancestor puts it at the next
// positioned one), and the scale it is drawn at under a transform.
function hostOrigin() {
  const rect = hostEl.getBoundingClientRect();
  const parent = hostEl.offsetParent || document.documentElement;
  const scale = parent.offsetWidth ? parent.getBoundingClientRect().width / parent.offsetWidth : 1;
  return { rect, scale: scale || 1 };
}

// A rectangle in the window's coordinates as a box in the host's, and back.
function toHost(r, origin) {
  return {
    left: (r.left - origin.rect.left) / origin.scale,
    top: (r.top - origin.rect.top) / origin.scale,
    width: r.width / origin.scale,
    height: r.height / origin.scale,
  };
}
function toClient(box, origin) {
  const left = box.left * origin.scale + origin.rect.left;
  const top = box.top * origin.scale + origin.rect.top;
  const width = box.width * origin.scale;
  const height = box.height * origin.scale;
  return { left, top, width, height, right: left + width, bottom: top + height };
}

// A lint's boxes in a form field, measured on a hidden mirror of the field
// (TextFieldRange): the same font and wrap, the same scroll, a <span> at the
// lint's words, its client rects the lint's underline segments, kept to the
// part of the field that shows text (the rest is scrolled out of it).
let mirror = null;
function mirrorOf(field) {
  if (!mirror) {
    mirror = document.createElement('div');
    mirror.setAttribute('aria-hidden', 'true');
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
  // An input keeps its text on one line, whatever its white-space says.
  if (field.localName === 'input') css += 'white-space:pre;';
  mirror.style.cssText = css;
  // Inside the field's own offsetParent so offsetTop/offsetLeft mean the
  // same; the mirror never scrolls, as the inner text is shifted instead.
  const parent = field.offsetParent || document.body;
  if (mirror.parentElement !== parent) parent.appendChild(mirror);
  return mirror;
}

// The rects a lint covers in a form field, in the host's coordinates.
function formRects(lint, origin) {
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
  // Where offsetTop misplaces the mirror (an offsetParent that isn't the
  // containing block, a table cell), the difference is taken off.
  const shown = field.getBoundingClientRect();
  const placed = node.getBoundingClientRect();
  const dx = shown.left - placed.left;
  const dy = shown.top - placed.top;
  const fieldScale = field.offsetWidth ? shown.width / field.offsetWidth : 1;
  const clip = {
    left: shown.left + field.clientLeft * fieldScale,
    top: shown.top + field.clientTop * fieldScale,
  };
  clip.right = clip.left + field.clientWidth * fieldScale;
  clip.bottom = clip.top + field.clientHeight * fieldScale;
  const rects = [];
  for (const r of mark.getClientRects()) {
    const left = Math.max(r.left + dx, clip.left);
    const top = Math.max(r.top + dy, clip.top);
    const right = Math.min(r.right + dx, clip.right);
    const bottom = Math.min(r.bottom + dy, clip.bottom);
    if (right - left > 0 && bottom - top > 0) {
      rects.push(toHost({ left, top, width: right - left, height: bottom - top }, origin));
    }
  }
  node.textContent = '';
  return rects;
}

// A lint's boxes in a contenteditable, from its Range's client rects.
function richRects(lint, map, origin) {
  return Array.from(rangeFor(map, lint.start, lint.end).getClientRects())
    .filter((r) => r.width > 0 && r.height > 0)
    .map((r) => toHost(r, origin));
}

// Draw the underlines for the lints now held.
function draw() {
  if (stopped) return;
  const map = field && fieldKind === 'rich' ? richMap(field) : null;
  if (useHighlights && map) {
    paintHighlights(map);
    clearBoxes();
    return;
  }
  clearHighlights();
  drawBoxes(map);
}

function drawBoxes(map) {
  if (!field || !document.contains(field)) { clearBoxes(); return; }
  renderHost();
  boxLayer.textContent = '';
  const origin = hostOrigin();
  for (const lint of lints) {
    const rects = fieldKind === 'form' ? formRects(lint, origin) : richRects(lint, map, origin);
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
  for (const lint of lints) lint.boxes = null;
}

// MARK: The card (Decided 7-9): the kind, the message, the fixes.

// Harper's messages are English Markdown; only inline code and emphasis
// are drawn, as elements, never innerHTML.
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

// HarperPopup's look (Decided 8). The boxes are border-box, as the page's
// CSS can't reach in to say otherwise; hovers only where a pointer
// hovers, so a tap leaves no button lit.
const CARD_CSS =
  ':host{all:initial;}' +
  '.eglu-card,.eglu-card *{box-sizing:border-box;}' +
  '.eglu-card{width:320px;max-width:calc(100vw - 24px);border-radius:16px;overflow:hidden;' +
  'border:0.5px solid rgb(0 0 0 / 0.08);box-shadow:0 12px 32px rgb(0 0 0 / 0.18), 0 2px 8px rgb(0 0 0 / 0.10);' +
  'background:rgb(255 255 255 / 0.72);-webkit-backdrop-filter:blur(24px) saturate(180%);backdrop-filter:blur(24px) saturate(180%);' +
  'font:13px/1.35 -apple-system, system-ui;color:rgb(0 0 0 / 0.85);}' +
  '.eglu-head{display:flex;align-items:center;gap:6px;padding:7px 7px 0 14px;}' +
  '.eglu-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;}' +
  '.eglu-kind{font-size:11px;font-weight:600;color:rgb(0 0 0 / 0.6);}' +
  '.eglu-close{margin-left:auto;width:22px;height:22px;border:0;border-radius:50%;background:transparent;' +
  'font-size:10px;font-weight:600;color:rgb(0 0 0 / 0.6);cursor:default;}' +
  '.eglu-body{padding:4px 14px 14px;}' +
  '.eglu-msg{margin:0 0 12px;line-height:1.4;}' +
  '.eglu-msg code{font-weight:600;}' +
  '.eglu-sugs{display:flex;flex-wrap:wrap;gap:6px;}' +
  '.eglu-sug{min-width:40px;max-width:100%;padding:5px 12px;border:0;border-radius:999px;' +
  'background:rgb(0 0 0 / 0.08);font-size:13px;color:rgb(0 0 0 / 0.85);white-space:nowrap;' +
  'overflow:hidden;text-overflow:ellipsis;cursor:default;}' +
  '.eglu-sug.eglu-first{background:rgb(0 0 0 / 0.85);color:#fff;font-weight:600;}' +
  '.eglu-key{margin-left:6px;font-weight:400;opacity:0.65;}' +
  '.eglu-foot{display:flex;align-items:center;gap:0;padding:7px;' +
  'border-top:0.5px solid rgb(0 0 0 / 0.10);}' +
  '.eglu-act{padding:4px 7px;border:0;border-radius:999px;background:transparent;font-size:12px;' +
  'color:rgb(0 0 0 / 0.6);white-space:nowrap;cursor:default;}' +
  '.eglu-gap{flex:1;}' +
  '@media (hover: hover){' +
  '.eglu-close:hover,.eglu-act:hover{background:rgb(0 0 0 / 0.08);color:rgb(0 0 0 / 0.85);}' +
  '.eglu-sug:hover{background:rgb(0 0 0 / 0.12);}' +
  '.eglu-sug.eglu-first:hover{background:rgb(0 0 0 / 0.78);}' +
  '}' +
  '@media (prefers-color-scheme: dark){' +
  '.eglu-card{background:rgb(40 40 44 / 0.72);border-color:rgb(255 255 255 / 0.12);color:rgb(255 255 255 / 0.85);}' +
  '.eglu-kind,.eglu-act,.eglu-close{color:rgb(255 255 255 / 0.65);}' +
  '.eglu-sug{background:rgb(255 255 255 / 0.14);color:rgb(255 255 255 / 0.9);}' +
  '.eglu-sug.eglu-first{background:rgb(255 255 255 / 0.92);color:#000;}' +
  '.eglu-foot{border-top-color:rgb(255 255 255 / 0.14);}' +
  '}' +
  '@media (prefers-color-scheme: dark) and (hover: hover){' +
  '.eglu-close:hover,.eglu-act:hover,.eglu-sug:hover{background:rgb(255 255 255 / 0.18);color:#fff;}' +
  '.eglu-sug.eglu-first:hover{background:rgb(255 255 255 / 0.82);color:#000;}' +
  '}';

// The lint the card is open on, or null.
let cardLint = null;

function buildCard(lint) {
  const card = document.createElement('div');
  card.className = 'eglu-card';

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
      // The first one's key, as a menu shows it beside its item: the key
      // is the app's, so it says which (config.keys.accept).
      if (index === 0 && config.keys && config.keys.accept) {
        const key = document.createElement('span');
        key.className = 'eglu-key';
        key.textContent = config.keys.accept;
        key.setAttribute('aria-hidden', 'true');
        button.appendChild(key);
        if (config.keys.acceptShortcut) button.setAttribute('aria-keyshortcuts', config.keys.acceptShortcut);
      }
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

// The boxes a lint is under, for a click's hit-test and the card's anchor:
// the drawn ones, or measured fresh where highlights did the drawing.
function boxesOf(lint) {
  if (lint.boxes) return lint.boxes;
  try {
    // Highlights draw nothing: the host is made here for the measuring.
    renderHost();
    const origin = hostOrigin();
    return fieldKind === 'form' ? formRects(lint, origin) : richRects(lint, richMap(field), origin);
  } catch (_) {
    return [];
  }
}

const supportsAnchors = CSS.supports('anchor-name: --a') && CSS.supports('position-area: block-end span-inline-end');
const supportsPopover = typeof HTMLElement.prototype.showPopover === 'function';

// The part of the window the page shows in, which the card stays inside.
function viewportBox() {
  return { left: 0, top: 0, width: innerWidth, height: innerHeight };
}

// The invisible box the card is anchored to, at the word (Decided 7).
function placeAnchor(box) {
  cardAnchor.style.left = box.left + 'px';
  cardAnchor.style.top = box.top + 'px';
  cardAnchor.style.width = box.width + 'px';
  cardAnchor.style.height = box.height + 'px';
}

function openCard(lint) {
  if (cardLint === lint) { return; }
  closeCard();
  const rects = boxesOf(lint);
  if (!rects.length) return;
  renderHost();
  placeAnchor(rects[0]);
  cardEl.textContent = '';
  cardEl.appendChild(buildCard(lint));
  // Placed by hand where there is no anchor positioning (Decided 7's
  // fallback): shown first, so its size can be measured, then put under
  // the word or above it.
  const byHand = !supportsAnchors || !supportsPopover;
  if (byHand && supportsPopover) cardEl.style.positionAnchor = 'none';
  if (byHand && !supportsPopover) cardEl.style.display = 'block';
  if (supportsPopover) cardEl.showPopover();
  cardLint = lint;
  if (byHand) placeCardBy(rects[0]);
  post({ kind: 'opened' });
}

// The card under the word's line, or above it where there is no room
// below; where there is room on neither side, on the side with more, as
// tall as that room lets it be and scrolling inside, so its buttons are
// always on screen.
function placeCardBy(box) {
  const origin = hostOrigin();
  const word = toClient(box, origin);
  const view = viewportBox();
  const gap = 6;
  cardEl.style.maxHeight = '';
  cardEl.style.overflowY = '';
  const width = cardEl.offsetWidth || 320;
  const height = cardEl.offsetHeight || 160;
  const roomBelow = view.top + view.height - word.bottom - 2 * gap;
  const roomAbove = word.top - view.top - 2 * gap;
  let top;
  if (height <= roomBelow) {
    top = word.bottom + gap;
  } else if (height <= roomAbove) {
    top = word.top - gap - height;
  } else {
    const below = roomBelow >= roomAbove;
    const room = Math.max(below ? roomBelow : roomAbove, 0);
    cardEl.style.maxHeight = room + 'px';
    cardEl.style.overflowY = 'auto';
    top = below ? word.bottom + gap : word.top - gap - room;
  }
  top = Math.max(view.top + gap, Math.min(top, view.top + view.height - gap - Math.min(height, cardEl.offsetHeight || height)));
  const left = Math.min(Math.max(word.left, view.left + gap),
    Math.max(view.left + gap, view.left + view.width - width - gap));
  // Its gap to the word is in `top`, not in a margin.
  cardEl.style.margin = '0';
  if (supportsPopover) {
    // In the top layer the card is placed against the window itself.
    cardEl.style.position = 'fixed';
    cardEl.style.inset = 'auto';
    cardEl.style.left = left + 'px';
    cardEl.style.top = top + 'px';
  } else {
    const at = toHost({ left, top, width: 0, height: 0 }, origin);
    cardEl.style.position = 'absolute';
    cardEl.style.left = at.left + 'px';
    cardEl.style.top = at.top + 'px';
  }
}

function closeCard() {
  if (!cardLint) return;
  cardLint = null;
  try { if (cardEl && cardEl.matches(':popover-open')) cardEl.hidePopover(); } catch (_) {}
  if (cardEl) { cardEl.style.display = ''; cardEl.textContent = ''; }
  post({ kind: 'closed' });
}

// MARK: Ignore, Add to Dictionary, Turn Off This Rule.

// The app is told, the lint goes, and once the app has taken the change
// the field is linted again, so its other words are checked as Harper now
// stands (another use of a word just added, say) (Decided 11).
function actOn(lint, action) {
  let told = null;
  if (action === 'ignore') {
    told = post({ kind: 'ignore', context: lint.context });
    lints = lints.filter((l) => l !== lint);
  } else if (action === 'addWord') {
    told = post({ kind: 'addWord', word: lint.word });
    lints = lints.filter((l) => l !== lint);
  } else if (action === 'disableRule') {
    told = post({ kind: 'disableRule', rule: lint.rule });
    lints = lints.filter((l) => l.rule !== lint.rule);
  }
  closeCard();
  draw();
  Promise.resolve(told).then(() => { if (field && !stopped) lintNow(); });
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
  const { text: now, map } = fieldText(field, fieldKind);
  // Only where the words the lint was raised on are still the words there;
  // anything else asks for a fresh pass (Decided 10).
  if (lint.source !== now || now.slice(lint.start, lint.end) !== lint.problem) {
    closeCard();
    textEdited(now);
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
    const range = rangeFor(map, lint.start, lint.end);
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
    // The fix's lint goes at once; the others move over the edit, and the
    // field is linted again once the page has settled it.
    lints = lints.filter((l) => l !== lint);
    remapLints(currentText());
    draw();
    clearTimeout(lintTimer);
    lintTimer = setTimeout(() => { if (field && document.contains(field)) lintNow(); }, 60);
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
// The document listeners, all taken away at once by stop().
let listening = null;

function currentText() {
  return field ? fieldText(field, fieldKind).text : '';
}

function lintNow() {
  if (!field || stopped) return;
  clearTimeout(lintTimer);
  const text = currentText();
  if (!text.trim()) { lints = []; shownText = text; asking = 0; draw(); return; }
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
  if (fieldKind === 'form' || !useHighlights) {
    // No text change: the boxes only move (scroll, rewrap, resize).
    draw();
  }
}

function focus(target) {
  if (stopped) return;
  let kind = checkable(target);
  if (kind === 'rich') {
    target = editingHost(target);
    kind = checkable(target);
  }
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
  closeCard();
  field = null;
  fieldKind = null;
  lints = [];
  shownText = '';
  asking = 0;
  clearTimeout(lintTimer);
  clearTimeout(restTimer);
  clearInterval(pollTimer);
  if (fieldObserver) { fieldObserver.disconnect(); fieldObserver = null; }
  clearHighlights();
  if (hostEl) { hostEl.remove(); hostEl = null; hostRoot = null; boxLayer = null; cardAnchor = null; cardEl = null; }
  // The mirror goes with the field it copied (Decided 16).
  if (mirror) { mirror.remove(); mirror = null; }
}

// MARK: Events (Decided 3, 9).

// Where the caret rests: a selection sitting in a lint's span 150ms opens
// its card. Any move or type cancels the wait.
function caretRest() {
  clearTimeout(restTimer);
  restTimer = setTimeout(() => {
    if (!field || cardLint) return;
    let caret = -1;
    if (fieldKind === 'form') {
      if (document.activeElement !== field || field.selectionStart !== field.selectionEnd) return;
      caret = field.selectionStart;
    } else {
      const selection = getSelection();
      if (!selection.rangeCount || !selection.isCollapsed) return;
      const node = selection.anchorNode;
      if (!node || !field.contains(node)) return;
      // The caret's offset in the text the linter saw, from the same walk.
      caret = offsetOf(richMap(field), node, selection.anchorOffset);
      if (caret < 0) return;
    }
    const lint = lints.find((l) => l.start <= caret && caret <= l.end);
    if (lint) openCard(lint);
  }, 150);
}

function onPointerDown(event) {
  if (!field) return;
  // A press in the card is its own: the field keeps focus and it stays open.
  if (hostEl && event.composedPath().includes(hostEl)) return;
  // Highlights draw no boxes: the host is made here so the hit-test has one.
  if (!hostEl) renderHost();
  const origin = hostOrigin();
  const lint = lints.find((l) => boxesOf(l).some((box) => {
    const r = toClient(box, origin);
    return event.clientX >= r.left && event.clientX <= r.right &&
      event.clientY >= r.top && event.clientY <= r.bottom;
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
    // A card whose word went off the screen closes (Decided 9); one that
    // stays follows it, the anchor too, for a field that scrolls inside.
    if (cardLint) {
      const rects = boxesOf(cardLint);
      const origin = hostOrigin();
      const view = viewportBox();
      const onScreen = rects.some((box) => {
        const r = toClient(box, origin);
        return r.bottom > view.top && r.top < view.top + view.height;
      });
      if (!onScreen) { closeCard(); return; }
      placeAnchor(rects[0]);
      if (!supportsAnchors || !supportsPopover) placeCardBy(rects[0]);
    }
  });
}

function install() {
  listening = new AbortController();
  const passive = { capture: true, passive: true, signal: listening.signal };
  if ((useHighlights = probeHighlights())) addStyle();
  document.addEventListener('focusin', (event) => focus(event.target), passive);
  document.addEventListener('focusout', (event) => {
    if (event.target !== field) return;
    // The focus moving into the card is no blur of the field's.
    if (hostEl && event.relatedTarget === hostEl) return;
    blur();
  }, passive);
  document.addEventListener('scroll', onScrollOrResize, passive);
  window.addEventListener('resize', onScrollOrResize, passive);
  // Esc is the card's while it is open, so this one listener can cancel it.
  document.addEventListener('keydown', onKeyDown, { capture: true, signal: listening.signal });
  // Typing closes the card, moves the underlines with their words (or
  // drops those it touched) and lints once it stops.
  document.addEventListener('input', (event) => {
    if (field && event.target === field) { closeCard(); textEdited(currentText()); }
  }, passive);
  document.addEventListener('compositionend', (event) => { if (field && event.target === field) lintSoon(); }, passive);
  document.addEventListener('selectionchange', caretRest, passive);
  document.addEventListener('pointerdown', onPointerDown, passive);
  // Fonts arriving later change where the words sit: the boxes move then.
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(() => { if (field && !stopped) draw(); });
  }
  // The field already focused when the script came in.
  if (document.activeElement) focus(document.activeElement);
}

// Everything Decided 16 allowed goes: the style, the hosts, the mirror,
// and the listeners with them.
function stop() {
  if (stopped) return;
  stopped = true;
  blur();
  if (listening) { listening.abort(); listening = null; }
  if (styleEl) { styleEl.remove(); styleEl = null; }
}

function start() {
  if (!stopped) return;
  stopped = false;
  install();
}

install();

return {
  apply,
  acceptFirst,
  stop,
  start,
  // For the app's checks and the tests'.
  lints: () => lints,
  field: () => field,
  cardOpen: () => cardLint != null,
  // A card's action on a lint, as its button does, and where the card is
  // as the window sees it: for the tests (writing.mjs), which can't reach
  // into the closed root.
  act: (index, action) => { if (lints[index]) actOn(lints[index], action); },
  cardRect: () => {
    if (!cardEl || !cardLint) return null;
    const r = cardEl.getBoundingClientRect();
    return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height };
  },
};
})();
