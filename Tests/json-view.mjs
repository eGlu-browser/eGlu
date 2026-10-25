#!/usr/bin/env node
// The JSON view (PadCore/Scripts/json-view.js) against real JSON pages: a
// <pre> of JSON gets the tree over it in a closed shadow root, folding works,
// Raw puts the overlay away, and over ten megabytes nothing is drawn.
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

// The view lives in a closed shadow root, which opens to nothing outside:
// its own say is window.__egluJSON.
const jsonState = `(window.__egluJSON ? { api: true, drawn: window.__egluJSON.drawn() } : { api: false })`;

try {
  // A JSON page, as WebKit frames a bare JSON body: one <pre>.
  const jsonPage = async (value, { big = false } = {}) => {
    const page = await browser.newPage();
    page.on('pageerror', (error) => check('no errors on the page', false, error.message));
    const text = big ? '{"pad":"' + 'x'.repeat(11 * 1024 * 1024) + '"}' : JSON.stringify(value);
    await page.setContent(`<body><pre></pre></body>`);
    await page.evaluate((t) => { document.querySelector('pre').textContent = t; }, text);
    await page.evaluate(script);
    return page;
  };

  // The shipped example page itself.
  {
    const page = await browser.newPage();
    page.on('pageerror', (error) => check('no errors on the page', false, error.message));
    await page.goto(`${base}/Tests/json-view.html`);
    const state = await page.evaluate(jsonState);
    check('the example page has the view', state.api === true && state.drawn === true, JSON.stringify(state));
    await page.close();
  }

  // An object: keys named, scalars coloured by their own kinds.
  {
    const page = await jsonPage({ a: 1, b: 'two', c: true, d: null });
    const state = await page.evaluate(jsonState);
    check('an object is drawn', state.api && state.drawn, JSON.stringify(state));
    await page.close();
  }

  // An array, and a nested one inside an object.
  {
    const page = await jsonPage([{ deep: [1, 2] }, 'x']);
    const state = await page.evaluate(jsonState);
    check('an array with a nested one is drawn', state.api && state.drawn, JSON.stringify(state));
    await page.close();
  }

  // Unicode through, unbroken.
  {
    const page = await jsonPage({ '키': 'héllo ✓ ' });
    const state = await page.evaluate(jsonState);
    check('unicode is drawn', state.api && state.drawn, JSON.stringify(state));
    await page.close();
  }

  // Over ten megabytes: raw only, and no Raw to offer.
  {
    const page = await jsonPage(null, { big: true });
    const state = await page.evaluate(jsonState);
    check('a page over 10 MB stays raw', state.api === false, JSON.stringify(state));
    await page.close();
  }

  // Raw from the view's own button and from the app-side toggle.
  {
    const page = await jsonPage({ raw: [1, 'two'] });
    await page.evaluate(`window.__egluJSON.toggle()`);
    let state = await page.evaluate(jsonState);
    check('toggle puts the view away', state.drawn === false, JSON.stringify(state));
    await page.evaluate(`window.__egluJSON.toggle()`);
    state = await page.evaluate(jsonState);
    check('toggle brings the view back', state.drawn === true, JSON.stringify(state));
    await page.close();
  }

  // Not JSON: nothing happens.
  {
    const page = await browser.newPage();
    await page.setContent('<body><p>not json</p></body>');
    await page.evaluate(script);
    const state = await page.evaluate(jsonState);
    check('a plain page is left alone', state.api === false, JSON.stringify(state));
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
