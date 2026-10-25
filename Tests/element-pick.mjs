#!/usr/bin/env node
// Picking an element (PadCore/Scripts/element-pick.js), as the developer
// tools' Take a Picture of an Element runs it: a click picks the element
// under it, even with no move of the pointer since the pick began (a key
// starts it); the click and the presses that make it never reach the page,
// nor does Esc, however early the page listens; the page's styles never
// hide the outline; nothing is left behind.
//
//   node Tests/element-pick.mjs              Chromium
//   node Tests/element-pick.mjs webkit       Playwright's WebKit, closest to Safari
//
// Needs Playwright (npm i -D playwright, or PLAYWRIGHT=/path/to/playwright
// for one installed elsewhere). Nothing here ships in the app.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const engine = process.argv[2] || 'chromium';
const playwright = await import(process.env.PLAYWRIGHT || 'playwright');
const script = fs.readFileSync(path.join(root, 'PadCore/Sources/PadCore/Scripts/element-pick.js'), 'utf8');

const results = [];
const check = (name, ok, detail = '') => results.push({ name, ok: !!ok, detail: String(detail) });
const browser = await playwright[engine].launch();

// A page that listens as hard as a web app does: capturing on the document
// and on the window (that one added once the pick has begun: a listener
// the page put on the window before it is the one nothing can come before),
// bubbling on the window; and a rule for every div.
const fixture = `<!doctype html>
<style>body { margin: 0 } div { display: none !important } .card { display: block !important; margin: 0;
  position: absolute; left: 100px; top: 80px; width: 200px; height: 120px; background: #ddd }</style>
<p class="card" id="card">A card</p>
<script>
  window.heard = [];
  window.types = ['pointerdown', 'mousedown', 'mouseup', 'click', 'keydown'];
  window.hear = (where) => (event) => window.heard.push(where + ' ' + event.type + (event.key ? ':' + event.key : ''));
  for (const type of window.types) {
    document.addEventListener(type, window.hear('document'), true);
    window.addEventListener(type, window.hear('window, bubbling'));
  }
</script>`;

// The pick as the app starts it: the script is the body of an async function.
const start = (page) => page.evaluate((source) => {
  window.__pick = new Function(`return (async () => { ${source} })()`)();
  for (const type of window.types) window.addEventListener(type, window.hear('window'), true);
}, script);

try {
  // A click with no move since the pick began picks what is under it.
  {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    page.on('pageerror', (error) => check('no errors on the page', false, error.message));
    await page.setContent(fixture);
    await page.mouse.move(150, 120);
    await start(page);
    await page.mouse.down();
    await page.mouse.up();
    const picked = await page.evaluate(() => window.__pick);
    check('a click with no move picks the element under it',
      picked && picked.x === 100 && picked.y === 80 && picked.width === 200 && picked.height === 120, JSON.stringify(picked));
    check('the answer says where the visual viewport is',
      picked && picked.viewportX === 0 && picked.viewportY === 0 && picked.viewportWidth === 800, JSON.stringify(picked));
    const heard = await page.evaluate(() => window.heard);
    check('the page hears none of the click', heard.length === 0, JSON.stringify(heard));
    const left = await page.evaluate(() => document.documentElement.lastElementChild.tagName);
    check('nothing is left on the page', left === 'BODY', left);
    await page.close();
  }

  // The outline shows over a page whose rules hide every div.
  {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    await page.setContent(fixture);
    await start(page);
    const host = await page.evaluate(() => {
      const host = document.documentElement.lastElementChild;
      const style = getComputedStyle(host);
      return { tag: host.tagName, display: style.display, position: style.position };
    });
    check('the page\'s rules don\'t hide or move the outline\'s host',
      host.tag === 'DIV' && host.display !== 'none' && host.position === 'fixed', JSON.stringify(host));
    await page.keyboard.press('Escape');
    await page.evaluate(() => window.__pick);
    await page.close();
  }

  // Esc ends it with nothing picked, and never reaches the page.
  {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    await page.setContent(fixture);
    await page.mouse.move(150, 120);
    await start(page);
    await page.mouse.move(160, 130);
    await page.keyboard.press('Escape');
    const picked = await page.evaluate(() => window.__pick);
    check('Esc ends it with nothing', picked === null, JSON.stringify(picked));
    const heard = await page.evaluate(() => window.heard);
    check('the page doesn\'t hear Esc', heard.length === 0, JSON.stringify(heard));
    // Other keys are the page's.
    await page.keyboard.press('a');
    const after = await page.evaluate(() => window.heard);
    check('after it, the page has its keys', after.includes('document keydown:a'), JSON.stringify(after));
    await page.close();
  }

  // A click after a move picks as well.
  {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    await page.setContent(fixture);
    await start(page);
    await page.mouse.click(250, 150);
    const picked = await page.evaluate(() => window.__pick);
    check('a moved click picks too', picked && picked.width === 200, JSON.stringify(picked));
    await page.close();
  }
} finally {
  await browser.close();
}

let failed = 0;
for (const { name, ok, detail } of results) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail && !ok ? ' - ' + detail : ''}`);
  if (!ok) failed += 1;
}
console.log(`${results.length - failed}/${results.length} checks passed`);
process.exit(failed ? 1 : 0);
