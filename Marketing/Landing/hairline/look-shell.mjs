// Runs the skill's look.mjs unchanged, with Playwright pointed at the Chromium headless shell already on
// this Mac (the cache's playwright-core finds no browser of its own revision).
import { createRequire } from "node:module";
import { join } from "node:path";
import { homedir } from "node:os";
const dir = join(homedir(), "Library/Caches/hairline-look");
const pw = createRequire(join(dir, "look.cjs"))("playwright-core");
const shell = join(homedir(), "Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell");
const launch = pw.chromium.launch.bind(pw.chromium);
pw.chromium.launch = (opts = {}) => {
  if (opts.channel) return Promise.reject(new Error("no Chrome channel here"));
  return launch({ ...opts, executablePath: shell, args: [...(opts.args || []), "--enable-unsafe-swiftshader", "--use-angle=swiftshader"] });
};
const look = join(homedir(), ".claude/skills/hairline-create/look.mjs");
process.argv = [process.argv[0], look, ...process.argv.slice(2)];
await import(look);
