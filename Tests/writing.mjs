#!/usr/bin/env node
// Runs Tests/writing.html in a real browser engine with a stand-in for the
// app's "egluWriting" handler, the way Tests/bridge.mjs stands in for the
// bridge's. Trusted focus, typing and clicks are the engine's own.
//
//   node Tests/writing.mjs              Chromium
//   node Tests/writing.mjs webkit       Playwright's WebKit, closest to eGlu
//
// Needs Playwright (npm i -D playwright, or PLAYWRIGHT=/path/to/playwright
// for one installed elsewhere). Nothing here ships in the app.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const engine = process.argv[2] || 'chromium';
const playwright = await import(process.env.PLAYWRIGHT || 'playwright');

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.mjs': 'text/javascript' };
const server = http.createServer((request, response) => {
  const file = path.join(root, decodeURIComponent(new URL(request.url, 'http://x').pathname));
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(response);
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;

const results = [];
const check = (name, ok, detail = '') => results.push({ name, ok: !!ok, detail: String(detail) });
const browser = await playwright[engine].launch();
const LINT = { start: 0, end: 7, kind: 'Spelling', rule: 'RepeatingWords', message: 'Did you mean to repeat “the”?', context: 'the the', word: 'the the', suggestions: [{ replace: 'the' }] };


try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 800 } });
  page.on('pageerror', (error) => check('no errors on the page', false, error.message));
  await page.goto(`${base}/Tests/writing.html`);
  const lintsAre = async () => page.evaluate(() => window.__egluWriting.lints().map((l) => [l.start, l.end, l.kind]));
  const wait = (ms) => page.waitForTimeout(ms);
  // A lint's first box in the window's coordinates: the host element is
  // where its boxes are measured from.
  const firstBox = async () => page.evaluate(() => {
    const lint = window.__egluWriting.lints()[0];
    const r = lint && lint.boxes && lint.boxes[0];
    if (!r) return null;
    const host = document.querySelector('eglu-writing').getBoundingClientRect();
    return { left: r.left + host.left, top: r.top + host.top, width: r.width, height: r.height,
             x: r.left + host.left + 2, y: r.top + host.top + 2 };
  });
  const fieldRect = async (id) => page.evaluate((id) => {
    const r = document.getElementById(id).getBoundingClientRect();
    return { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
  }, id);

  // MARK: Which fields are checked (Decided 1).

  await page.evaluate(() => { window.__lints = []; window.__sent = []; });
  await page.locator('#pw').click();
  await wait(100);
  check('a password field is never checked', await page.evaluate(() => !window.__egluWriting.field()));
  await page.locator('#em').click();
  await wait(100);
  check('an email field is never checked', await page.evaluate(() => !window.__egluWriting.field()));
  await page.locator('#ro').click();
  await wait(100);
  check('a readonly field is never checked', await page.evaluate(() => !window.__egluWriting.field()));
  await page.locator('#otp').click();
  await wait(100);
  check('a one-time-code field is never checked', await page.evaluate(() => !window.__egluWriting.field()));
  await page.locator('#cm-inner').focus().catch(() => {});
  await page.locator('#cm-inner').click().catch(() => {});
  await wait(100);
  check('a code editor is never checked', await page.evaluate(() => !window.__egluWriting.field()));
  await page.locator('#nospell-ta').click();
  await wait(100);
  check('a field under spellcheck="false" is never checked', await page.evaluate(() => !window.__egluWriting.field()));
  await page.evaluate(() => document.getElementById('inner').focus());
  await wait(100);
  check('an element focused inside a contenteditable checks its editing host',
    await page.evaluate(() => window.__egluWriting.field() === document.getElementById('outer')));

  // MARK: The text and the lint.

  await page.evaluate((lint) => { window.__lints = [lint]; }, LINT);
  await page.locator('#ta').click();
  await wait(600);
  check('a textarea is linted on focus', (await lintsAre()).length === 1);
  check('the lint keeps its span', JSON.stringify(await lintsAre()) === JSON.stringify([[0, 7, 'Spelling']]),
    JSON.stringify(await lintsAre()));
  const boxCount = await page.evaluate(() => {
    const host = document.querySelector('eglu-writing');
    return host && host.shadowRoot ? -1 : document.querySelectorAll('eglu-writing').length;
  });
  check('the host is a closed root in the page', boxCount >= 1);
  const taBox = await firstBox();
  const taRect = await fieldRect('ta');
  check('the box sits on the field’s first line',
    taBox && taBox.left >= taRect.left && taBox.top >= taRect.top && taBox.top < taRect.top + 30,
    JSON.stringify({ taBox, taRect }));

  // MARK: The card (Decided 7-9).

  await page.evaluate(() => {
    window.__escSeen = 0;
    document.getElementById('ta').addEventListener('keydown', (e) => { if (e.key === 'Escape') window.__escSeen += 1; });
  });
  await page.mouse.click(taBox.x, taBox.y);
  await wait(300);
  check('a click in a lint box opens the card', await page.evaluate(() => window.__egluWriting.cardOpen()));
  check('and the card tells the app it is open',
    await page.evaluate(() => window.__sent.some((m) => m.kind === 'opened')));
  const below = await page.evaluate(() => window.__egluWriting.cardRect());
  check('the card opens below the word', below && below.top >= taBox.top + taBox.height,
    JSON.stringify({ below, taBox }));
  const focusKept = await page.evaluate(() => document.activeElement && document.activeElement.id);
  check('the card never takes the field’s focus', focusKept === 'ta', focusKept);
  if (below) {
    // On the kind's name, which is no button.
    await page.mouse.click(below.left + 60, below.top + 12);
    await wait(100);
    const afterPress = await page.evaluate(() => document.activeElement && document.activeElement.id);
    check('a press on the card leaves the focus in the field', afterPress === 'ta', afterPress);
    check('and the card open', await page.evaluate(() => window.__egluWriting.cardOpen()));
  }
  await page.keyboard.press('Escape');
  await wait(100);
  check('Esc closes the card', !(await page.evaluate(() => window.__egluWriting.cardOpen())));
  check('and the page does not hear that Esc', (await page.evaluate(() => window.__escSeen)) === 0);
  check('and tells the app it closed',
    await page.evaluate(() => window.__sent.some((m) => m.kind === 'closed')));
  await page.keyboard.press('Escape');
  await wait(50);
  check('Esc with no card open reaches the page', (await page.evaluate(() => window.__escSeen)) === 1);

  // MARK: A fix the field's own undo takes back (Decided 10).

  await page.locator('#ta').click();
  await wait(300);
  const before = await page.locator('#ta').inputValue();
  const applied = await page.evaluate(() => window.__egluWriting.apply(0, 0));
  check('apply() answers true', applied === true);
  await wait(100);
  const after = await page.locator('#ta').inputValue();
  check('the suggestion is written in', after === 'the quick brown fox jumps over', after);
  await page.locator('#ta').click();
  await page.evaluate(() => document.execCommand('undo'));
  await wait(100);
  check('the page’s own Undo takes it back', (await page.locator('#ta').inputValue()) === before);

  // MARK: A range that moved is linted again instead of fixed (Decided 10).

  await page.evaluate((lint) => { window.__lints = [lint]; }, LINT);
  await page.locator('#plain').click();
  await wait(600);
  // The text changed since the lint was answered, with no event to start
  // another pass: applying checks the words are still the lint's.
  await page.evaluate(() => { document.getElementById('plain').value = 'changed plain words here'; });
  const refused = await page.evaluate(() => window.__egluWriting.apply(0, 0));
  check('a fix on words that moved is not written', refused === false);

  // MARK: contenteditable text and the highlights.

  await page.evaluate(() => {
    window.__lints = [{ start: 1, end: 8, kind: 'Spelling', rule: 'R', message: 'm', context: 'x', word: 'problem', suggestions: [] }];
  });
  await page.locator('#ed').click();
  await wait(500);
  check('a contenteditable is linted', (await lintsAre()).length === 1);
  const painted = await page.evaluate(() => {
    if ('highlights' in CSS) {
      const h = CSS.highlights.get('eglu-spelling');
      return h ? Array.from(h).map((r) => r.toString()) : [];
    }
    const lint = window.__egluWriting.lints()[0];
    return lint.boxes && lint.boxes.length ? ['problem'] : [];
  });
  check('the highlight holds one range, over the word', JSON.stringify(painted) === '["problem"]', JSON.stringify(painted));
  await page.locator('#plain').click();
  await wait(200);
  const cleared = await page.evaluate(() => {
    const inCss = 'highlights' in CSS && Array.from(CSS.highlights.keys()).some((k) => k.startsWith('eglu-'));
    return !inCss;
  });
  check('the underlines go on blur', cleared);

  await page.evaluate(() => { window.__lints = []; window.__asked = []; });
  await page.locator('#blocks').click();
  await wait(500);
  const blocksText = await page.evaluate(() => window.__asked[window.__asked.length - 1]);
  check('a contenteditable’s lines follow its elements’ computed display, hidden text left out',
    blocksText === 'alpha\nbeta\ngamma', JSON.stringify(blocksText));

  // MARK: A fix after an emoji, in a generic contenteditable, and its Undo.

  await page.evaluate(() => {
    // "😀 emoji the the fox": the emoji is two UTF-16 units.
    window.__lints = [{ start: 9, end: 16, kind: 'Repetition', rule: 'R', message: 'm', context: 'x', word: 'the the', suggestions: [{ replace: 'the' }] }];
  });
  await page.locator('#em2').click();
  await wait(500);
  const emojiRange = await page.evaluate(() => {
    if (!('highlights' in CSS)) return 'the the';
    const h = CSS.highlights.get('eglu-repetition');
    return h ? Array.from(h)[0].toString() : '';
  });
  check('a lint after an emoji covers the right words', emojiRange === 'the the', emojiRange);
  await page.evaluate(() => window.__egluWriting.apply(0, 0));
  await wait(100);
  const emojiFixed = await page.evaluate(() => document.getElementById('em2').textContent);
  check('the fix is written in a generic contenteditable', emojiFixed === '😀 emoji the fox', emojiFixed);
  await page.evaluate(() => document.execCommand('undo'));
  await wait(100);
  const emojiUndone = await page.evaluate(() => document.getElementById('em2').textContent);
  check('and the page’s Undo takes it back', emojiUndone === '😀 emoji the the fox', emojiUndone);

  // MARK: The caret resting in a lint opens its card, after an empty line.

  await page.evaluate(() => {
    // "one\n\nthe the end": "the the" at 5 to 12.
    window.__lints = [{ start: 5, end: 12, kind: 'Repetition', rule: 'R', message: 'm', context: 'x', word: 'the the', suggestions: [{ replace: 'the' }] }];
  });
  await page.locator('#lines').click();
  await wait(500);
  const putCaret = (at) => page.evaluate((at) => {
    const text = document.getElementById('lines').children[2].firstChild;
    const range = document.createRange();
    range.setStart(text, at);
    range.collapse(true);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
  }, at);
  // At 15 in the text ("the t|he" is 5 + 5): inside the lint.
  await putCaret(5);
  await wait(400);
  check('a caret resting in a lint after an empty line opens its card',
    await page.evaluate(() => window.__egluWriting.cardOpen()));
  await page.keyboard.press('Escape');
  // Two past the lint's end (12, in "end").
  await putCaret(9);
  await wait(400);
  check('a caret past the lint opens nothing', !(await page.evaluate(() => window.__egluWriting.cardOpen())));
  await page.keyboard.press('Escape');

  // MARK: An edit keeps the lints where they still fit (spanMapping).

  await page.evaluate((lint) => { window.__lints = [lint]; }, LINT);
  await page.locator('#ta').click();
  await wait(500);
  // An edit no input event reports: the 1s check remaps the lints over it,
  // and the next ask is held so the remapped lint is the one seen.
  await page.evaluate(() => {
    window.__holdLints = true;
    const field = document.getElementById('ta');
    field.value = 'ok, ' + field.value;
  });
  await wait(1200);
  const moved = await lintsAre();
  check('a lint still fitting the edit moves with it', JSON.stringify(moved) === JSON.stringify([[4, 11, 'Spelling']]),
    JSON.stringify(moved));
  await page.evaluate(() => { window.__holdLints = false; window.__held.forEach((h) => h.resolve([])); window.__held = []; });

  await page.evaluate((lint) => { window.__lints = [lint]; }, LINT);
  await page.locator('#sw').click();
  await wait(500);
  await page.evaluate(() => { window.__holdLints = true; });
  // Typed inside the flagged words: "the the" becomes "the Xthe".
  await page.evaluate(() => {
    const field = document.getElementById('sw');
    field.setSelectionRange(4, 4);
    document.execCommand('insertText', false, 'X');
  });
  await wait(100);
  check('an edit inside a lint’s words drops it', (await lintsAre()).length === 0, JSON.stringify(await lintsAre()));
  check('and its fix can’t be applied', (await page.evaluate(() => window.__egluWriting.apply(0, 0))) === false);
  await page.evaluate(() => { window.__holdLints = false; window.__held.forEach((h) => h.resolve([])); window.__held = []; });

  // MARK: Answers: a stale one is dropped, one for older text moves over the edit.

  await page.evaluate(() => { window.__lints = []; window.__holdLints = true; window.__held = []; });
  await page.locator('#st').click();
  await wait(200);
  await page.evaluate(() => {
    const field = document.getElementById('st');
    field.value = 'retyped the the words';
    field.dispatchEvent(new InputEvent('input', { bubbles: true }));
  });
  await wait(450);
  const seqs = await page.evaluate(() => window.__held.map((h) => h.seq));
  await page.evaluate((seqs) => {
    // The first ask's answer, with a lint in it, lands after the second
    // ask was made: dropped.
    window.__lints = [{ start: 0, end: 3, kind: 'Spelling', rule: 'R', message: 'm', context: 'x', word: 'the', suggestions: [] }];
    window.__release(seqs[0]);
  }, seqs);
  await wait(100);
  const dropped = await lintsAre();
  check('an answer to an older ask is dropped', seqs.length >= 2 && JSON.stringify(dropped) === JSON.stringify([]),
    JSON.stringify({ seqs, dropped }));
  await page.evaluate((seqs) => {
    window.__lints = [{ start: 8, end: 15, kind: 'Spelling', rule: 'R', message: 'm', context: 'x', word: 'the the', suggestions: [] }];
    window.__holdLints = false;
    window.__release(seqs[seqs.length - 1]);
  }, seqs);
  await wait(100);
  check('the newest ask’s answer is kept', JSON.stringify(await lintsAre()) === JSON.stringify([[8, 15, 'Spelling']]),
    JSON.stringify(await lintsAre()));

  await page.evaluate(() => { window.__lints = []; window.__holdLints = true; window.__held = []; });
  await page.locator('#plain').click();
  await page.locator('#st').click();
  await wait(100);
  await page.evaluate(() => {
    // Text put before the flagged words while the answer is on its way,
    // with no input event to ask again first.
    const field = document.getElementById('st');
    field.value = 'now ' + field.value;
  });
  await page.evaluate(() => {
    window.__lints = [{ start: 8, end: 15, kind: 'Spelling', rule: 'R', message: 'm', context: 'x', word: 'the the', suggestions: [] }];
    window.__holdLints = false;
    const last = window.__held[window.__held.length - 1];
    window.__release(last.seq);
  });
  await wait(100);
  check('an answer for text changed meanwhile is placed over the edit',
    JSON.stringify(await lintsAre()) === JSON.stringify([[12, 19, 'Spelling']]), JSON.stringify(await lintsAre()));

  // MARK: Boxes: a static wrapper, and text scrolled out of its field.

  await page.evaluate((lint) => { window.__lints = [lint]; window.__holdLints = false; }, LINT);
  await page.locator('#sw').click();
  await page.evaluate(() => { document.getElementById('sw').value = 'the the static wrapper'; });
  await page.locator('#plain').click();
  await page.locator('#sw').click();
  await wait(600);
  const swBox = await firstBox();
  const swRect = await fieldRect('sw');
  check('in a static wrapper below other content the box is on the field',
    swBox && swBox.top >= swRect.top && swBox.top < swRect.top + 30 && swBox.left >= swRect.left,
    JSON.stringify({ swBox, swRect }));

  await page.evaluate(() => {
    // The flagged words on the first line, the field scrolled to its last.
    window.__lints = [{ start: 0, end: 7, kind: 'Spelling', rule: 'R', message: 'm', context: 'x', word: 'the the', suggestions: [] }];
  });
  await page.locator('#scrolled').click();
  await page.evaluate(() => { const f = document.getElementById('scrolled'); f.scrollTop = f.scrollHeight; });
  await wait(600);
  const hidden = await page.evaluate(() => {
    const lint = window.__egluWriting.lints()[0];
    return lint ? (lint.boxes || []).length : -1;
  });
  check('words scrolled out of a field draw no box outside it', hidden === 0, hidden);

  // MARK: The boxes stay on the words as a scrolling container and the page scroll.

  await page.evaluate((lint) => { window.__lints = [lint]; }, LINT);
  await page.evaluate(() => { document.getElementById('st').value = 'the the inside scrolled'; });
  await page.locator('#st').click();
  await wait(600);
  const offsetFromField = async () => {
    const box = await firstBox();
    const r = await fieldRect('st');
    return box ? [Math.round(box.left - r.left), Math.round(box.top - r.top)] : null;
  };
  const beforeScroll = await offsetFromField();
  await page.evaluate(() => { document.getElementById('scrolly').scrollTop = 30; window.scrollBy(0, 20); });
  await wait(100);
  const afterScroll = await offsetFromField();
  check('the box keeps its place on the words over scrolling',
    beforeScroll && JSON.stringify(beforeScroll) === JSON.stringify(afterScroll), JSON.stringify({ beforeScroll, afterScroll }));
  await page.evaluate(() => window.scrollTo(0, 0));

  // MARK: Slate and Draft hear the fix the way they listen (Decided 10).

  await page.evaluate(() => {
    window.__lints = [{ start: 6, end: 13, kind: 'Spelling', rule: 'R', message: 'm', context: 'x', word: 'the the', suggestions: [{ replace: 'the' }] }];
    window.__seen = [];
    // A stand-in Slate: it takes the input itself, as Slate does, writing
    // the replacement where the selection (or the target range) says.
    document.getElementById('slate').addEventListener('beforeinput', (e) => {
      const ranges = e.getTargetRanges ? e.getTargetRanges() : [];
      window.__seen.push({ type: e.inputType, data: e.data, ranges: ranges.length });
      e.preventDefault();
      const target = ranges[0] || getSelection().getRangeAt(0);
      const range = document.createRange();
      range.setStart(target.startContainer, target.startOffset);
      range.setEnd(target.endContainer, target.endOffset);
      range.deleteContents();
      range.insertNode(document.createTextNode(e.data));
    });
  });
  await page.locator('#slate').click();
  await wait(500);
  await page.evaluate(() => window.__egluWriting.apply(0, 0));
  const slateSeen = await page.evaluate(() => window.__seen);
  // WebKit passes no targetRanges through a synthetic InputEvent; the
  // selection is set to the same range for it.
  check('Slate gets insertReplacementText with targetRanges',
    slateSeen.length === 1 && slateSeen[0].type === 'insertReplacementText' && slateSeen[0].data === 'the' &&
    (slateSeen[0].ranges >= 1 || engine === 'webkit'),
    JSON.stringify(slateSeen));
  const slateText = await page.evaluate(() => document.getElementById('slate').textContent);
  check('and its own handling writes the fix, once', slateText === 'slate the words', slateText);

  await page.evaluate(() => {
    window.__lints = [{ start: 6, end: 13, kind: 'Spelling', rule: 'R', message: 'm', context: 'x', word: 'the the', suggestions: [{ replace: 'the' }] }];
    window.__seen = [];
    document.getElementById('draft').addEventListener('beforeinput', (e) => {
      window.__seen.push(e.inputType);
    });
  });
  await page.locator('#draft').click();
  await wait(500);
  await page.evaluate(() => window.__egluWriting.apply(0, 0));
  const draftSeen = await page.evaluate(() => window.__seen);
  check('Draft gets beforeinput insertText', draftSeen.length === 1 && draftSeen[0] === 'insertText', JSON.stringify(draftSeen));

  // MARK: Ignore, the dictionary, a rule off (Decided 11).

  await page.evaluate((lint) => { window.__lints = [lint]; window.__sent = []; }, LINT);
  await page.locator('#ta').click();
  await page.evaluate(() => { document.getElementById('ta').value = 'the the quick brown fox jumps over'; });
  await page.locator('#plain').click();
  await page.locator('#ta').click();
  await wait(500);
  await page.evaluate(() => { window.__asked = []; window.__egluWriting.act(0, 'ignore'); });
  await wait(100);
  check('Ignore sends the lint’s context to the app',
    await page.evaluate(() => window.__sent.some((m) => m.kind === 'ignore' && m.context === 'the the')));
  check('and the field is linted again once the app has it', (await page.evaluate(() => window.__asked.length)) >= 1);
  await wait(200);
  await page.evaluate(() => { window.__egluWriting.act(0, 'addWord'); });
  await wait(100);
  check('Add to Dictionary sends the word',
    await page.evaluate(() => window.__sent.some((m) => m.kind === 'addWord' && m.word === 'the the')));
  await wait(200);
  await page.evaluate(() => { window.__egluWriting.act(0, 'disableRule'); });
  await wait(100);
  check('Turn Off This Rule sends the rule',
    await page.evaluate(() => window.__sent.some((m) => m.kind === 'disableRule' && m.rule === 'RepeatingWords')));

  // MARK: stop() leaves nothing in the page (Decided 16), and start() comes back.

  await page.evaluate(() => window.__egluWriting.stop());
  await wait(100);
  const left = await page.evaluate(() => ({
    style: !!document.getElementById('eglu-writing'),
    hosts: document.querySelectorAll('eglu-writing').length,
    mirrors: Array.from(document.querySelectorAll('div[aria-hidden="true"]')).filter((d) => d.style.visibility === 'hidden').length,
  }));
  check('stop() leaves no style, no hosts and no mirror', left.style === false && left.hosts === 0 && left.mirrors === 0,
    JSON.stringify(left));
  await page.evaluate(() => { window.__asked = []; });
  await page.locator('#plain').click();
  await page.locator('#ta').click();
  await page.keyboard.type(' more');
  await wait(500);
  check('a stopped script listens to nothing', (await page.evaluate(() => window.__asked.length)) === 0);
  await page.evaluate(() => window.__egluWriting.start());
  await wait(500);
  check('started again, it checks the field already focused',
    await page.evaluate(() => window.__egluWriting.field() === document.getElementById('ta') && window.__asked.length >= 1));

  // MARK: The card placed by hand, where there is no anchor positioning.

  const plain = await browser.newPage({ viewport: { width: 1200, height: 800 } });
  plain.on('pageerror', (error) => check('no errors on the fallback page', false, error.message));
  await plain.addInitScript(() => {
    const supports = CSS.supports.bind(CSS);
    CSS.supports = (...args) => {
      const text = args.join(' ');
      if (text.includes('anchor-name') || text.includes('position-area')) return false;
      return supports(...args);
    };
  });
  await plain.goto(`${base}/Tests/writing.html`);
  const openAt = async (top) => {
    await plain.evaluate(({ lint, top }) => {
      window.__lints = [lint];
      const field = document.getElementById('ta');
      field.style.cssText = `position:fixed;left:40px;top:${top}px;width:300px;height:40px;`;
    }, { lint: LINT, top });
    await plain.locator('#plain').click();
    await plain.locator('#ta').click();
    await plain.waitForTimeout(600);
    const at = await plain.evaluate(() => {
      const lint = window.__egluWriting.lints()[0];
      const r = lint.boxes[0];
      const host = document.querySelector('eglu-writing').getBoundingClientRect();
      return { x: r.left + host.left + 2, y: r.top + host.top + 2, top: r.top + host.top, bottom: r.top + host.top + r.height };
    });
    await plain.mouse.click(at.x, at.y);
    await plain.waitForTimeout(300);
    return { word: at, card: await plain.evaluate(() => window.__egluWriting.cardRect()) };
  };
  const low = await openAt(740);
  check('near the window’s foot the card opens above the word',
    low.card && low.card.bottom <= low.word.top && low.card.top >= 0, JSON.stringify(low));
  await plain.keyboard.press('Escape');
  await plain.setViewportSize({ width: 1200, height: 260 });
  const squeezed = await openAt(110);
  check('with room on neither side the card stays inside the window',
    squeezed.card && squeezed.card.top >= 0 && squeezed.card.bottom <= 260 + 1, JSON.stringify(squeezed));
  await plain.close();
} finally {
  await browser.close();
  server.close();
}

let failed = 0;
for (const result of results) {
  if (!result.ok) failed += 1;
  console.log(`${result.ok ? 'PASS' : 'FAIL'} ${result.name}${result.ok || !result.detail ? '' : `  (${result.detail})`}`);
}
console.log(`\n${engine}: ${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
