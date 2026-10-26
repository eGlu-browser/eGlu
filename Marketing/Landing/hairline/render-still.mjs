import { createRequire } from "node:module";
import { join } from "node:path";
import { homedir } from "node:os";
const pw = createRequire(join(homedir(), "Library/Caches/hairline-look/look.cjs"))("playwright-core");
const shell = join(homedir(), "Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell");
const browser = await pw.chromium.launch({ executablePath: shell });
const page = await browser.newPage({ viewport: { width: 1000, height: 900 }, deviceScaleFactor: 1 });
await page.goto("file://" + process.argv[2] + "?theme=dark");
await page.waitForTimeout(1500);
const markup = await page.evaluate(() => {
  const svg = document.querySelector("svg");
  svg.querySelectorAll("path.hi, circle.dot.m").forEach((e) => e.remove());
  // each mark's own computed style, written in, so the copy draws the same away from the page
  for (const e of svg.querySelectorAll("path, circle, ellipse, polygon, line")) {
    const c = getComputedStyle(e);
    for (const k of ["fill", "stroke", "stroke-width", "stroke-linejoin", "stroke-linecap", "stroke-dasharray", "opacity", "fill-opacity", "stroke-opacity"]) e.setAttribute(k, c.getPropertyValue(k));
    e.removeAttribute("class");
  }
  for (const m of svg.querySelectorAll("mask, [mask]")) m.removeAttribute("mask");
  const copy = svg.cloneNode(true);
  copy.setAttribute("width", "1880"); copy.setAttribute("height", "1504");
  copy.removeAttribute("style"); copy.removeAttribute("class");
  return copy.outerHTML;
});
const out = await browser.newPage({ viewport: { width: 1880, height: 1504 }, deviceScaleFactor: 1 });
await out.setContent(`<html><body style="margin:0;background:rgb(8,9,10)">${markup}</body></html>`);
await out.waitForTimeout(300);
await out.screenshot({ path: process.argv[3] });
console.log(markup.length);
await browser.close();
