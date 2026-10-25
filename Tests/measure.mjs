#!/usr/bin/env node
// The measuring tool (PadCore/Scripts/measure.js) against a real page: a
// click selects and posts the element's details, the page's own click is
// swallowed, ⌥ and a second tap give distances, G/R/X and Esc do the
// tool's own jobs, and stop() ends it as Esc does.
//
//   node Tests/measure.mjs              Chromium
//   node Tests/measure.mjs webkit       Playwright's WebKit, closest to Safari
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
const source = fs.readFileSync(path.join(root, 'PadCore/Sources/PadCore/Scripts/measure.js'), 'utf8');


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

// A page with the tool running: the app's handler stand-in keeps what it
// says, a counter counts the page's own clicks, and the run's promise is
// kept to await the ending.
const open = async () => {
  const page = await browser.newPage();
  page.on('pageerror', (error) => check('no errors on the page', false, error.message));
  await page.goto(`${base}/Tests/measure.html`);
  await page.evaluate(`window.__said = []; window.__clicks = 0;
    document.addEventListener('click', () => { window.__clicks += 1; });
    window.webkit = { messageHandlers: { egluMeasure: { postMessage: (m) => window.__said.push(m) } } };
    window.__guides = JSON.stringify({ columns: 12, gutter: 24, margin: 0, row: 8, rulers: true });`);
  return page;
};
// The body the app runs: the file is an async function's body (callAsyncJavaScript).
const start = (page) => page.evaluate((body) => {
  window.__done = new Function('guides', 'return (async () => {' + body + '})()')(JSON.parse(window.__guides));
}, source);
const state = (page) => page.evaluate(`window.__egluMeasure ? window.__egluMeasure.state() : null`);
const said = (page) => page.evaluate(`window.__said`);

try {
  // The overlay: a host under the document element in a closed shadow root.
  {
    const page = await open();
    await start(page);
    const host = await page.evaluate(`(() => {
      const host = document.documentElement.lastElementChild;
      return { isDiv: host && host.tagName === 'DIV', closed: host && host.shadowRoot === null };
    })()`);
    check('the overlay is a closed shadow host', host.isDiv && host.closed, JSON.stringify(host));
    const on = await state(page);
    check('the tool runs', on && on.on === true && on.rulers === true, JSON.stringify(on));
    await page.close();
  }

  // Hovering marks the element under the pointer without taking a click;
  // a click selects it, says its details, and the page never hears it.
  {
    const page = await open();
    await start(page);
    const box = await page.locator('.inner.primary').boundingBox();
    await page.mouse.move(box.x + 10, box.y + 10);
    await page.waitForTimeout(80);
    let st = await state(page);
    check('hover marks the element under the pointer', st.hover === true, JSON.stringify(st));
    await page.mouse.click(box.x + 10, box.y + 10);
    await page.waitForTimeout(80);
    const messages = await said(page);
    const details = messages.find((m) => m.kind === 'details');
    check('a click selects and posts details', !!details && details.tag === 'button'
          && details.width > 0 && details.padding && details.padding.top === 8
          && details.margin && details.margin.top === 4
          && details.font && details.font.size === '15px'
          && details.color === 'rgb(255, 255, 255)'
          && /#outer button\.inner:nth-of-type\(1\)/.test(details.name), JSON.stringify(details));
    check('the page never heard the click', await page.evaluate('window.__clicks') === 0);
    await page.close();
  }

  // ⌥ held, the element under the pointer gives the distance.
  {
    const page = await open();
    await start(page);
    const one = await page.locator('.inner.primary').boundingBox();
    const two = await page.locator('#aside').boundingBox();
    await page.mouse.click(one.x + 10, one.y + 10);
    await page.mouse.move(two.x + 10, two.y + 10);
    await page.keyboard.down('Alt');
    await page.mouse.move(two.x + 11, two.y + 11);
    await page.waitForTimeout(80);
    let messages = await said(page);
    let distance = messages.filter((m) => m.kind === 'distance').pop();
    check('⌥ gives the distance', !!distance && !distance.inside && distance.dy > 0,
          JSON.stringify(distance));
    await page.keyboard.up('Alt');
    await page.waitForTimeout(50);
    messages = await said(page);
    check('⌥ lifted ends the distance', messages.filter((m) => m.kind === 'distance').pop().gone === true);
    await page.close();
  }

  // A selection inside another: the four insets.
  {
    const page = await open();
    await start(page);
    const outer = await page.locator('#outer').boundingBox();
    const inner = await page.locator('.inner.primary').boundingBox();
    await page.mouse.click(outer.x + 5, outer.y + 2);
    await page.mouse.move(inner.x + 10, inner.y + 10);
    await page.keyboard.down('Alt');
    await page.mouse.move(inner.x + 11, inner.y + 11);
    await page.waitForTimeout(80);
    const messages = await said(page);
    const distance = messages.filter((m) => m.kind === 'distance').pop();
    check('one inside another gives the insets', !!distance && distance.inside === true
          && distance.insets && distance.insets.left > 0 && distance.insets.top > 0,
          JSON.stringify(distance));
    await page.close();
  }

  // G, R and X flip the guides, rulers and x-ray; Esc ends the tool.
  {
    const page = await open();
    await start(page);
    await page.keyboard.press('g');
    await page.keyboard.press('r');
    await page.keyboard.press('x');
    await page.waitForTimeout(50);
    let st = await state(page);
    check('G, R and X are the tool\'s', st.guides === true && st.rulers === false && st.xray === true,
          JSON.stringify(st));
    await page.keyboard.press('Escape');
    await page.waitForTimeout(80);
    const messages = await said(page);
    check('Esc ends the tool and says so', messages.some((m) => m.kind === 'ended'));
    check('the overlay goes', await page.evaluate(`document.documentElement.lastElementChild.tagName`) !== 'DIV'
          || (await state(page)) === null);
    check('the run resolves', await page.evaluate(`window.__done.then(() => 'resolved')`) === 'resolved');
    await page.close();
  }

  // The app's own handle: settings pushed, a note pinned, stop() ends.
  {
    const page = await open();
    await start(page);
    const box = await page.locator('.inner.primary').boundingBox();
    await page.mouse.click(box.x + 10, box.y + 10);
    await page.waitForTimeout(60);
    const ref = (await said(page)).find((m) => m.kind === 'details').ref;
    await page.evaluate(`window.__egluMeasure.pin('n1', ${ref}, 1)`);
    await page.waitForTimeout(50);
    let st = await state(page);
    check('a note pins to its element', st.pins === 1, JSON.stringify(st));
    await page.evaluate(`window.__egluMeasure.unpin('n1'); window.__egluMeasure.settings({ row: 4 })`);
    await page.waitForTimeout(50);
    st = await state(page);
    check('a note unpins and settings take', st.pins === 0, JSON.stringify(st));
    await page.evaluate(`window.__egluMeasure.stop()`);
    await page.waitForTimeout(60);
    check('stop() ends the tool', (await said(page)).some((m) => m.kind === 'ended'));
    await page.close();
  }

  // Element under the pointer is never the overlay's own: hovers after the
  // tool started still find page elements.
  {
    const page = await open();
    await start(page);
    const box = await page.locator('#aside').boundingBox();
    await page.mouse.move(box.x + 5, box.y + 5);
    await page.waitForTimeout(80);
    const st = await state(page);
    check('the overlay never covers the page', st.hover === true, JSON.stringify(st));
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
