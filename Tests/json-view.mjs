#!/usr/bin/env node
// The JSON view (PadCore/Scripts/json-view.js) against real JSON pages: a
// <pre> of JSON gets the tree over it in a closed shadow root, with each
// value drawn as it is, folding works, Raw puts the overlay away and leaves
// the <pre> as it was, markup in a value stays text, and over ten megabytes
// (of UTF-8, not of characters) nothing is drawn.
//
//   node Tests/json-view.mjs              Chromium
//   node Tests/json-view.mjs webkit       Playwright's WebKit, closest to Safari
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
const script = fs.readFileSync(path.join(root, 'PadCore/Sources/PadCore/Scripts/json-view.js'), 'utf8');

const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript' };
const served = { name: 'eGlu', list: [1, 2, { deep: true }], text: 'héllo ✓' };
const server = http.createServer((request, response) => {
  // A JSON answer as a server sends one, for the browser to frame itself.
  if (request.url === '/data.json') {
    response.writeHead(200, { 'content-type': 'application/json; charset=utf-8' }).end(JSON.stringify(served));
    return;
  }
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

// The view lives in a closed shadow root, which opens to nothing outside:
// its own say is window.__egluJSON. To look inside, the tests make shadow
// roots open before the script runs (the app never does).
const jsonState = `(window.__egluJSON ? { api: true, drawn: window.__egluJSON.drawn() } : { api: false })`;
const openShadows = `(() => {
  const attach = Element.prototype.attachShadow;
  Element.prototype.attachShadow = function (options) {
    const root = attach.call(this, Object.assign({}, options, { mode: 'open' }));
    window.__shadow = root;
    return root;
  };
})()`;
// What the view shows: each key and each scalar as drawn, the folds, the button.
const drawn = `(() => {
  const root = window.__shadow;
  if (!root) return null;
  const texts = (selector) => [...root.querySelectorAll(selector)].map((node) => node.textContent);
  return {
    keys: texts('.row > .key'),
    strings: texts('.string'), numbers: texts('.number'), booleans: texts('.boolean'), nulls: texts('.null'),
    folds: root.querySelectorAll('details').length,
    open: root.querySelectorAll('details[open]').length,
    button: (root.querySelector('.bar button') || {}).textContent,
    markup: root.querySelectorAll('img, script').length,
  };
})()`;

try {
  // A JSON page, as WebKit frames a bare JSON body: one <pre>.
  const jsonPage = async (value, { text, source = script } = {}) => {
    const page = await browser.newPage();
    page.on('pageerror', (error) => check('no errors on the page', false, error.message));
    await page.setContent(`<body><pre></pre></body>`);
    await page.evaluate((t) => { document.querySelector('pre').textContent = t; }, text ?? JSON.stringify(value));
    await page.evaluate(openShadows);
    await page.evaluate(source);
    return page;
  };
  const same = (one, other) => JSON.stringify(one) === JSON.stringify(other);

  // The shipped example page itself.
  {
    const page = await browser.newPage();
    page.on('pageerror', (error) => check('no errors on the page', false, error.message));
    await page.goto(`${base}/Tests/json-view.html`);
    const state = await page.evaluate(jsonState);
    check('the example page has the view', state.api === true && state.drawn === true, JSON.stringify(state));
    await page.close();
  }

  // An object: keys named, each scalar drawn as itself in its own kind.
  {
    const page = await jsonPage({ a: 1, b: 'two', c: true, d: null, e: -2.5 });
    const state = await page.evaluate(jsonState);
    check('an object is drawn', state.api && state.drawn, JSON.stringify(state));
    const view = await page.evaluate(drawn);
    check('its keys are drawn in order', same(view.keys, ['"a": ', '"b": ', '"c": ', '"d": ', '"e": ']), JSON.stringify(view.keys));
    check('its values are drawn as themselves',
      same(view.strings, ['"two"']) && same(view.numbers, ['1', '-2.5']) && same(view.booleans, ['true']) && same(view.nulls, ['null']),
      JSON.stringify(view));
    check('the button says Raw', view.button === 'Raw', view.button);
    await page.close();
  }

  // An array, and a nested one inside an object: each folds and unfolds.
  {
    const page = await jsonPage([{ deep: [1, 2] }, 'x']);
    const state = await page.evaluate(jsonState);
    check('an array with a nested one is drawn', state.api && state.drawn, JSON.stringify(state));
    let view = await page.evaluate(drawn);
    check('each array and object folds, open at first', view.folds === 3 && view.open === 3, JSON.stringify(view));
    await page.evaluate(() => window.__shadow.querySelectorAll('summary')[1].click());
    view = await page.evaluate(drawn);
    check('a click on one folds it alone', view.open === 2, JSON.stringify(view));
    const hidden = await page.evaluate(() => {
      const fold = window.__shadow.querySelectorAll('details')[1];
      // A closed fold's content keeps its boxes in today's engines, unseen.
      const children = fold.querySelector('.children');
      return children.checkVisibility ? !children.checkVisibility() : children.getClientRects().length === 0;
    });
    check('a folded one hides what it holds', hidden);
    await page.evaluate(() => window.__shadow.querySelectorAll('summary')[1].click());
    view = await page.evaluate(drawn);
    check('a second click unfolds it', view.open === 3, JSON.stringify(view));
    await page.close();
  }

  // Unicode through, unbroken, in keys and values.
  {
    const page = await jsonPage({ '키': 'héllo ✓ 😀' });
    const view = await page.evaluate(drawn);
    check('unicode is drawn unbroken', same(view.keys, ['"키": ']) && same(view.strings, ['"héllo ✓ 😀"']), JSON.stringify(view));
    await page.close();
  }

  // Markup in a value is text: nothing of it is made or run.
  {
    const page = await jsonPage({ html: '<img src=x onerror="window.__ran=1"><script>window.__ran=2</script>' });
    await page.waitForTimeout(100);
    const view = await page.evaluate(drawn);
    const ran = await page.evaluate(() => window.__ran);
    check('markup in a value stays text', view.markup === 0 && ran === undefined && view.strings[0].startsWith('"<img'),
      JSON.stringify({ view, ran }));
    await page.close();
  }

  // Over ten megabytes: raw only, and no Raw to offer. Counted in UTF-8:
  // 3.5 million Korean characters are 10.5 MB in 3.5 million units.
  {
    const page = await jsonPage(null, { text: '{"pad":"' + 'x'.repeat(11 * 1024 * 1024) + '"}' });
    const state = await page.evaluate(jsonState);
    check('a page over 10 MB stays raw', state.api === false, JSON.stringify(state));
    await page.close();
  }
  {
    const page = await jsonPage(null, { text: '{"pad":"' + '가'.repeat(3.5 * 1024 * 1024) + '"}' });
    const state = await page.evaluate(jsonState);
    check('over 10 MB of Korean in fewer characters stays raw', state.api === false, JSON.stringify(state));
    await page.close();
  }
  {
    const page = await jsonPage(null, { text: '{"pad":"' + '가'.repeat(1024 * 1024) + '"}' });
    const state = await page.evaluate(jsonState);
    check('3 MB of Korean is drawn', state.api && state.drawn, JSON.stringify(state));
    await page.close();
  }

  // Raw from the view's own button, and from the app-side toggle; the
  // <pre> is never changed.
  {
    const text = JSON.stringify({ raw: [1, 'two'] });
    const page = await jsonPage(null, { text });
    await page.evaluate(() => window.__shadow.querySelector('.bar button').click());
    let state = await page.evaluate(jsonState);
    check('the view\'s Raw puts it away', state.drawn === false, JSON.stringify(state));
    const pre = await page.evaluate(() => document.querySelector('pre').textContent);
    check('the <pre> is as it came', pre === text, pre);
    await page.evaluate(`window.__egluJSON.toggle()`);
    state = await page.evaluate(jsonState);
    check('toggle brings the view back', state.drawn === true, JSON.stringify(state));
    await page.evaluate(`window.__egluJSON.toggle()`);
    state = await page.evaluate(jsonState);
    check('toggle puts the view away', state.drawn === false, JSON.stringify(state));
    await page.close();
  }

  // The button's word as the app writes it in (Scripts.jsonView).
  {
    const page = await jsonPage({ a: 1 }, { source: script.replace('/*WORDS*/null', '{"raw":"원본"}') });
    const view = await page.evaluate(drawn);
    check('the button has the app\'s word', view.button === '원본', view.button);
    await page.close();
  }

  // A JSON answer as the browser frames it. WebKit frames it in one <pre>,
  // as the app sees it; Chromium may add its own viewer beside it, which
  // the script then leaves alone.
  {
    const page = await browser.newPage();
    page.on('pageerror', (error) => check('no errors on the page', false, error.message));
    await page.goto(`${base}/data.json`);
    await page.evaluate(script);
    const state = await page.evaluate(jsonState);
    const lone = await page.evaluate(() => document.body.children.length === 1 && document.body.firstElementChild.tagName === 'PRE');
    check('a served JSON page gets the view', engine === 'webkit' ? state.drawn === true : (lone ? state.drawn === true : state.api === false),
      JSON.stringify({ state, lone }));
    await page.close();
  }

  // Not JSON, or not JSON that parses: nothing happens.
  {
    const page = await browser.newPage();
    await page.setContent('<body><p>not json</p></body>');
    await page.evaluate(script);
    const state = await page.evaluate(jsonState);
    check('a plain page is left alone', state.api === false, JSON.stringify(state));
    await page.close();
  }
  {
    const page = await jsonPage(null, { text: '{"broken": ' });
    const state = await page.evaluate(jsonState);
    check('a <pre> that is not JSON is left alone', state.api === false, JSON.stringify(state));
    await page.close();
  }
} finally {
  await browser.close();
  server.close();
}

let failed = 0;
for (const { name, ok, detail } of results) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail && !ok ? ' - ' + detail : ''}`);
  if (!ok) failed += 1;
}
console.log(`${results.length - failed}/${results.length} checks passed`);
process.exit(failed ? 1 : 0);
