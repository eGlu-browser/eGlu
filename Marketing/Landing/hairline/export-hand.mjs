// Exports the Scrub figure's hand, at rest, as a transparent PNG, with the fingertip's
// pixel position. node export-hand.mjs <page.html> <out.png> <theme>
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { writeFileSync } from "node:fs";

const req = createRequire(process.env.HOME + "/Library/Caches/hairline-look/node_modules/");
const { chromium } = req("playwright-core");
const [page, out, theme = "light"] = process.argv.slice(2);
const SCALE = 4;

const browser = await chromium.launch();
const tab = await browser.newPage({ viewport: { width: 900, height: 900 }, deviceScaleFactor: SCALE });
await tab.goto(pathToFileURL(page).href + "?theme=" + theme);
await tab.waitForTimeout(2000);
// Only the hand, on nothing.
const box = await tab.evaluate(() => {
  const hand = document.querySelector('[data-part="hand"]');
  const svg = hand.ownerSVGElement;
  for (const el of svg.querySelectorAll("*")) {
    if (el === hand || hand.contains(el) || el.contains(hand)) continue;
    el.style.display = "none";
  }
  const style = document.createElement("style");
  style.textContent = "*, *::before, *::after { background: transparent !important; box-shadow: none !important; border-color: transparent !important; }";
  document.head.append(style);
  for (const el of document.querySelectorAll("body *")) {
    if (el.contains(svg) || svg.contains(el)) continue;
    el.style.visibility = "hidden";
  }
  const r = hand.getBoundingClientRect();
  // The fingertip: the leftmost point of the last joint's silhouette, the first path.
  const tipPath = hand.querySelector("path"), m = tipPath.getScreenCTM(), n = tipPath.getTotalLength();
  let tip = null;
  for (let i = 0; i <= 400; i++) {
    const p = tipPath.getPointAtLength((i / 400) * n), x = m.a * p.x + m.c * p.y + m.e, y = m.b * p.x + m.d * p.y + m.f;
    if (!tip || x < tip[0]) tip = [x, y];
  }
  return { x: r.x - 4, y: r.y - 4, w: r.width + 8, h: r.height + 8, tip };
});
await tab.screenshot({ path: out, omitBackground: true, clip: { x: box.x, y: box.y, width: box.w, height: box.h } });
const tip = [(box.tip[0] - box.x) * SCALE, (box.tip[1] - box.y) * SCALE];
writeFileSync(out.replace(/\.png$/, ".json"), JSON.stringify({ tip, scale: SCALE }));
console.log("wrote", out, "tip at", tip.map(Math.round).join(","));
await browser.close();
