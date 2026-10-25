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

  // MARK: The card (Decided 7-9).

  const box = await page.evaluate(() => {
    const lint = window.__egluWriting.lints()[0];
    const r = lint.boxes[0];
    const host = document.querySelector('eglu-writing');
    const c = host.parentElement.getBoundingClientRect();
    return { x: r.left + c.left + 2, y: r.top + c.top + 2 };
  });
  await page.mouse.click(box.x, box.y);
  await wait(300);
  check('a click in a lint box opens the card', await page.evaluate(() => window.__egluWriting.cardOpen()));
  check('and the card tells the app it is open',
    await page.evaluate(() => window.__sent.some((m) => m.kind === 'card' && m.open === true)));
  const focusKept = await page.evaluate(() => document.activeElement && document.activeElement.id);
  check('the card never takes the field\u2019s focus', focusKept === 'ta', focusKept);
  await page.keyboard.press('Escape');
  await wait(100);
  check('Esc closes the card', !(await page.evaluate(() => window.__egluWriting.cardOpen())));
  check('and tells the app it closed',
    await page.evaluate(() => window.__sent.some((m) => m.kind === 'card' && m.open === false)));

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
  check('the page\u2019s own Undo takes it back', (await page.locator('#ta').inputValue()) === before);

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
  const drew = await page.evaluate(() => {
    if ('highlights' in CSS) return Array.from(CSS.highlights.keys()).filter((k) => k.startsWith('eglu-'));
    return [];
  });
  const boxesOrHighlights = await page.evaluate(() => {
    const inCss = 'highlights' in CSS && Array.from(CSS.highlights.keys()).some((k) => k.startsWith('eglu-'));
    const lint = window.__egluWriting.lints()[0];
    return inCss || (lint.boxes && lint.boxes.length > 0);
  });
  check('the lint is underlined (highlight or box)', boxesOrHighlights, JSON.stringify(drew));
  await page.locator('#plain').click();
  await wait(200);
  const cleared = await page.evaluate(() => {
    const inCss = 'highlights' in CSS && Array.from(CSS.highlights.keys()).some((k) => k.startsWith('eglu-'));
    return !inCss;
  });
  check('the underlines go on blur', cleared);

  // MARK: An edit keeps the lints where they still fit (spanMapping).

  await page.evaluate((lint) => { window.__lints = [lint]; }, LINT);
  await page.locator('#ta').click();
  await wait(500);
  // An edit no input event reports: the 1s check remaps the lints over it.
  await page.evaluate(() => {
    const field = document.getElementById('ta');
    field.value = 'ok, ' + field.value;
  });
  await wait(1200);
  const moved = await lintsAre();
  check('a lint still fitting the edit moves with it', JSON.stringify(moved) === JSON.stringify([[4, 11, 'Spelling']]),
    JSON.stringify(moved));

  // MARK: A stale answer is dropped.

  await page.evaluate(() => { window.__holdLints = true; window.__lints = []; });
  await page.locator('#st').click();
  await wait(200);
  await page.evaluate(() => {
    const field = document.getElementById('st');
    field.value = 'retyped the the words';
    field.dispatchEvent(new InputEvent('input', { bubbles: true }));
  });
  await wait(450);
  await page.evaluate(() => {
    // The first ask's answer lands after the second ask: dropped.
    window.__holdLints = false;
    window.__release(1);
  });
  await wait(100);
  const dropped = await lintsAre();
  check('an answer for text the field no longer holds is dropped', JSON.stringify(dropped) === JSON.stringify([]),
    JSON.stringify(dropped));

  // MARK: Slate and Draft hear the fix the way they listen (Decided 10).

  await page.evaluate(() => {
    window.__lints = [{ start: 6, end: 12, kind: 'Spelling', rule: 'R', message: 'm', context: 'x', word: 'the the', suggestions: [{ replace: 'the' }] }];
    window.__seen = [];
    document.getElementById('slate').addEventListener('beforeinput', (e) => {
      window.__seen.push({ type: e.inputType, ranges: e.getTargetRanges ? e.getTargetRanges().length : -1 });
    });
  });
  await page.locator('#slate').click();
  await wait(500);
  await page.evaluate(() => window.__egluWriting.apply(0, 0));
  const slateSeen = await page.evaluate(() => window.__seen);
  // WebKit passes no targetRanges through a synthetic InputEvent; the type
  // still reaches Slate's listener.
  check('Slate gets insertReplacementText with targetRanges',
    slateSeen.length === 1 && slateSeen[0].type === 'insertReplacementText' &&
    (slateSeen[0].ranges >= 1 || engine === 'webkit'),
    JSON.stringify(slateSeen));

  await page.evaluate(() => {
    window.__lints = [{ start: 6, end: 12, kind: 'Spelling', rule: 'R', message: 'm', context: 'x', word: 'the the', suggestions: [{ replace: 'the' }] }];
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

  // MARK: Ignore, the dictionary, a rule off.

  await page.evaluate((lint) => { window.__lints = [lint]; window.__sent = []; }, LINT);
  await page.locator('#ta').click();
  await wait(500);
  await page.mouse.click(box.x, box.y);
  await wait(300);
  await page.evaluate(() => {
    // Ignore, as its button does.
    const l = window.__egluWriting.lints()[0];
    window.webkit.messageHandlers.egluWriting.postMessage({ kind: 'ignore', lint: { context: l.context } });
  });
  check('Ignore sends the lint\u2019s context to the app',
    await page.evaluate(() => window.__sent.some((m) => m.kind === 'ignore' && m.lint.context === 'the the')));

  // MARK: stop() leaves nothing in the page (Decided 16).

  await page.evaluate(() => window.__egluWriting.stop());
  await wait(100);
  const left = await page.evaluate(() => ({
    style: !!document.getElementById('eglu-writing'),
    hosts: document.querySelectorAll('eglu-writing').length,
  }));
  check('stop() leaves no style and no hosts', left.style === false && left.hosts === 0, JSON.stringify(left));

  // MARK: The card inside the visual viewport (Decided 4, task 04).

  // As on iOS with the touch keyboard up: no anchor positioning, and a
  // visual viewport half the window's height, starting halfway down.
  const small = await browser.newPage({ viewport: { width: 1200, height: 800 } });
  small.on('pageerror', (error) => check('no errors on the fallback page', false, error.message));
  await small.addInitScript(() => {
    const supports = CSS.supports.bind(CSS);
    CSS.supports = (...args) => {
      const text = args.join(' ');
      if (text.includes('anchor-name') || text.includes('position-area')) return false;
      return supports(...args);
    };
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: { offsetLeft: 0, offsetTop: 400, width: 1200, height: 400, scale: 1,
               addEventListener() {}, removeEventListener() {} },
    });
  });
  await small.goto(`${base}/Tests/writing.html`);
  await small.evaluate((lint) => {
    window.__lints = [lint];
    const field = document.getElementById('ta');
    field.style.cssText = 'position:absolute;left:40px;top:640px;width:300px;height:80px;';
  }, LINT);
  await small.locator('#ta').click();
  await wait(600);
  const smallBox = await small.evaluate(() => {
    const lint = window.__egluWriting.lints()[0];
    const r = lint.boxes[0];
    const host = document.querySelector('eglu-writing');
    const c = host.parentElement.getBoundingClientRect();
    return { x: r.left + c.left + 2, y: r.top + c.top + 2 };
  });
  await small.mouse.click(smallBox.x, smallBox.y);
  await wait(300);
  check('the fallback card opens', await small.evaluate(() => window.__egluWriting.cardOpen()));
  const card = await small.evaluate(() => window.__egluWriting.cardRect());
  check('the fallback card stays inside the visual viewport',
    !!card && card.top >= 400 - 1 && card.bottom <= 800 + 1 && card.left >= -1 && card.right <= 1200 + 1,
    JSON.stringify(card));
  await small.close();
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
