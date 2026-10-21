#!/usr/bin/env node
// Runs PadCore's shim for Chrome extensions (Scripts/extension-shim.js)
// against a stand-in for WebKit's extension APIs, which behaves where it
// matters as WebKit does: the first onMessage listener's return is the
// answer (macOS 26, as Search found), a promise returned is waited for, and
// a reply that never came is undefined with no error (macOS 27 too). On 27
// a promise that fails never reaches the sender at all; the shim's gate
// never returns one.
// Chrome's side is Chrome 148's, from developer.chrome.com's messaging page.
//
//   node Tests/extension-shim.mjs
//
// Needs nothing beyond Node. Nothing here ships in the app.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const shim = fs.readFileSync(path.join(root, 'PadCore/Sources/PadCore/Scripts/extension-shim.js'), 'utf8');

const results = [];
const check = (name, ok, detail = '') => results.push({ name, ok: !!ok, detail: String(detail) });
const tick = (ms = 0) => new Promise((resolve) => setTimeout(resolve, ms));

/// A world with WebKit's APIs as an extension's background, page or
/// content script has them, the shim run in it `times` times.
function world({ protocol = 'chrome-extension:', apis = true, times = 1, reply, background = false, lastError } = {}) {
  const native = [];
  const event = () => {
    const listeners = [];
    return {
      listeners,
      addListener(f) { listeners.push(f); },
      removeListener(f) { const i = listeners.indexOf(f); if (i >= 0) listeners.splice(i, 1); },
      hasListener(f) { return listeners.includes(f); },
      // WebKit's rule: the first listener's return decides.
      deliver(message) {
        return new Promise((resolve, reject) => {
          let answered = false;
          const sendResponse = (value) => { if (!answered) { answered = true; resolve(value); } };
          let first;
          listeners.forEach((listener, i) => {
            const result = listener(message, { id: 'sender' }, sendResponse);
            if (i === 0) first = result;
          });
          if (first === true) return;
          if (first && typeof first.then === 'function') { first.then(sendResponse, reject); return; }
          sendResponse(undefined);
        });
      },
    };
  };
  const target = new EventTarget();
  const chrome = apis ? {
    runtime: {
      id: 'abcdefghijklmnopabcdefghijklmnop',
      onMessage: event(),
      onMessageExternal: event(),
      sendMessage: async (message) => (reply ? reply(message) : undefined),
      sendNativeMessage: async (application, message) => { native.push({ application, message }); return { value: null }; },
    },
    tabs: { sendMessage: async () => undefined },
  } : undefined;
  if (chrome && lastError) chrome.runtime.lastError = lastError;
  // A timer's throw reaches the world's error event, as in a browser.
  const timer = (f, ms) => setTimeout(() => {
    try { f(); } catch (error) { target.dispatchEvent(Object.assign(new Event('error'), { error })); }
  }, ms);
  const globals = {
    setTimeout: timer, clearTimeout, location: { protocol }, EventTarget,
    addEventListener: target.addEventListener.bind(target),
  };
  if (chrome) { globals.chrome = chrome; globals.browser = chrome; }
  const context = vm.createContext(globals);
  if (background) {
    context.document = {};
    chrome.extension = { getBackgroundPage: () => vm.runInContext('globalThis', context) };
  }
  for (let i = 0; i < times; i++) vm.runInContext(shim, context, { filename: 'extension-shim.js' });
  return { context, chrome, native, target, run: (code) => vm.runInContext(code, context) };
}

// A page's own world: no extension APIs, nothing left behind.
{
  const w = world({ apis: false });
  check('a world without extension APIs is left as it was', w.run('typeof __safienceShim === "undefined" && typeof requestIdleCallback === "undefined"'));
}

// Run twice, as when two content script entries match one page: once.
{
  const w = world({ times: 2 });
  check('the shim runs once in a world', w.run('__safienceShim === true'));
  const webkit = w.chrome.runtime.onMessage.listeners;
  check('a page with no listener has none of WebKit\'s', webkit.length === 0, webkit.length);
  const f = () => undefined;
  w.run('chrome.runtime.onMessage').addListener(f);
  w.run('chrome.runtime.onMessage').addListener(() => undefined);
  check('one of WebKit\'s behind its listeners', webkit.length === 1, webkit.length);
  w.run('chrome.runtime.onMessage').removeListener(f);
  check('still there while one is left', webkit.length === 1, webkit.length);
}
{
  const w = world();
  const f = () => undefined;
  w.run('chrome.runtime.onMessage').addListener(f);
  w.run('chrome.runtime.onMessage').removeListener(f);
  check('gone with the last', w.chrome.runtime.onMessage.listeners.length === 0);
}
{
  const w = world({ background: true });
  check('the background\'s is there from the start', w.chrome.runtime.onMessage.listeners.length === 1);
  const f = () => undefined;
  w.run('chrome.runtime.onMessage').addListener(f);
  w.run('chrome.runtime.onMessage').removeListener(f);
  check('and stays', w.chrome.runtime.onMessage.listeners.length === 1);
}

// What WebKit lacks, filled in.
{
  const w = world();
  check('Symbol.dispose and asyncDispose are there', w.run('typeof Symbol.dispose === "symbol" && typeof Symbol.asyncDispose === "symbol"'));
  const idle = await new Promise((resolve) => w.run('requestIdleCallback')((deadline) => resolve(deadline)));
  check('requestIdleCallback calls back with time to spare', idle.didTimeout === false && idle.timeRemaining() > 0 && idle.timeRemaining() <= 50);
  let called = false;
  const id = w.run('requestIdleCallback')(() => { called = true; });
  w.run('cancelIdleCallback')(id);
  await tick(10);
  check('cancelIdleCallback cancels', !called);
}

// onMessage, by Chrome's rule.
{
  const w = world();
  const onMessage = w.run('chrome.runtime.onMessage');
  onMessage.addListener(() => undefined);
  onMessage.addListener((message, sender, respond) => { setTimeout(() => respond('later'), 5); return true; });
  check('a later listener that returns true answers', await w.chrome.runtime.onMessage.deliver('ping') === 'later');
}
{
  const w = world();
  const onMessage = w.run('chrome.runtime.onMessage');
  onMessage.addListener(() => undefined);
  onMessage.addListener(async () => 'from a promise');
  check('a later listener that returns a promise answers', await w.chrome.runtime.onMessage.deliver('ping') === 'from a promise');
}
{
  const w = world();
  const onMessage = w.run('chrome.runtime.onMessage');
  onMessage.addListener((message, sender, respond) => { respond('first'); });
  onMessage.addListener((message, sender, respond) => { respond('second'); return true; });
  check('only the first answer counts', await w.chrome.runtime.onMessage.deliver('ping') === 'first');
}
{
  const w = world();
  w.run('chrome.runtime.onMessage').addListener((message, sender, respond) => { respond(); });
  check('an empty answer is null', await w.chrome.runtime.onMessage.deliver('ping') === null);
}
{
  const w = world();
  w.run('chrome.runtime.onMessage').addListener((message, sender, respond) => {
    const answer = { ok: true };
    respond(answer);
    answer.ok = false;
  });
  const reply = await w.chrome.runtime.onMessage.deliver('ping');
  check('an answer goes as it was when given', reply?.ok === true, JSON.stringify(reply));
}
{
  const w = world();
  w.run('chrome.runtime.onMessage').addListener((message, sender, respond) => { respond({ then: (yes, no) => no(new Error('x')) }); });
  const reply = await w.chrome.runtime.onMessage.deliver('ping').then((r) => r, () => 'rejected');
  check('an answer with a then goes as JSON, not as a promise', reply !== 'rejected' && typeof reply?.then !== 'function', JSON.stringify(reply));
}
{
  const w = world();
  w.run('chrome.runtime.onMessage').addListener((message, sender, respond) => { const a = {}; a.a = a; respond(a); });
  const reply = await w.chrome.runtime.onMessage.deliver('ping');
  check('an answer that isn\'t JSON fails', typeof reply?.__safienceFailed === 'string', JSON.stringify(reply));
}
{
  const w = world();
  w.run('chrome.runtime.onMessage').addListener(() => ({ get then() { throw new Error('getter'); } }));
  w.run('chrome.runtime.onMessage').addListener((message, sender, respond) => { respond('later listener'); });
  const reply = await w.chrome.runtime.onMessage.deliver('ping');
  check('a return whose then throws fails, and the rest still run', reply?.__safienceFailed === 'getter', JSON.stringify(reply));
  await tick(5);
}
{
  const w = world();
  w.run('chrome.runtime.onMessage').addListener(async () => {});
  w.run('chrome.runtime.onMessage').addListener((message, sender, respond) => { setTimeout(() => respond('later'), 5); return true; });
  check('an async listener that returns nothing answers null first, as in Chrome 148', await w.chrome.runtime.onMessage.deliver('ping') === null);
}
{
  const w = world();
  w.run('chrome.runtime.onMessage').addListener(async () => { throw new Error('nope'); });
  const reply = await w.chrome.runtime.onMessage.deliver('ping');
  check('a rejection is answered as a failure, not a failed promise', reply?.__safienceFailed === 'nope', JSON.stringify(reply));
}
{
  const w = world();
  w.run('chrome.runtime.onMessageExternal').addListener(async () => { throw new Error('nope'); });
  check('to another extension it is null', await w.chrome.runtime.onMessageExternal.deliver('ping') === null);
}
{
  const w = world();
  w.run('chrome.runtime.onMessage').addListener(() => { throw new Error('thrown'); });
  w.run('chrome.runtime.onMessage').addListener((message, sender, respond) => { respond('too late'); });
  const reply = await w.chrome.runtime.onMessage.deliver('ping');
  check('a throw fails it, first', reply?.__safienceFailed === 'thrown', JSON.stringify(reply));
  await tick(5);
  check('and is passed on to the error watch', w.native.some((n) => n.message.args[1] === 'thrown'), JSON.stringify(w.native));
}
{
  const w = world();
  const onMessage = w.run('chrome.runtime.onMessage');
  const f = () => undefined;
  onMessage.addListener(f);
  check('hasListener sees the extension\'s listener', onMessage.hasListener(f) && onMessage.hasListeners());
  onMessage.removeListener(f);
  check('removeListener takes it away', !onMessage.hasListener(f));
  check('nobody answering is undefined', await w.chrome.runtime.onMessage.deliver('ping') === undefined);
}

// sendMessage with a callback and no reply: lastError, as in Chrome.
{
  const w = world();
  const seen = await new Promise((resolve) => w.run('chrome.runtime').sendMessage('ping', (reply) => {
    resolve({ reply, error: w.run('chrome.runtime.lastError && chrome.runtime.lastError.message') });
  }));
  check('no reply sets lastError for the callback', seen.reply === undefined && /message port closed/.test(seen.error), JSON.stringify(seen));
  check('lastError is gone after the callback', w.run('chrome.runtime.lastError') === undefined);
}
{
  const w = world({ reply: () => 'pong' });
  const reply = await new Promise((resolve) => w.run('chrome.runtime').sendMessage('ping', resolve));
  check('a reply reaches the callback', reply === 'pong');
  check('without a callback, a promise as before', await w.run('chrome.runtime').sendMessage('ping') === 'pong');
}
{
  const w = world({ reply: () => null });
  const seen = await new Promise((resolve) => w.run('chrome.runtime').sendMessage('ping', (reply) => {
    resolve({ reply, error: w.run('chrome.runtime.lastError') });
  }));
  check('an empty answer sets no lastError', seen.reply === null && seen.error === undefined, JSON.stringify(seen));
}
{
  const w = world({ reply: () => ({ __safienceFailed: 'nope' }) });
  const error = await new Promise((resolve) => w.run('chrome.runtime').sendMessage('ping', (reply) => {
    resolve(reply === undefined && w.run('chrome.runtime.lastError.message'));
  }));
  check('a failure is lastError for the callback', error === 'nope', error);
  const rejected = await w.run('chrome.runtime').sendMessage('ping').then(() => 'resolved', (e) => e.message);
  check('and a rejection without one', rejected === 'nope', rejected);
}
{
  const native = { message: 'WebKit\'s own' };
  const w = world({ lastError: native });
  await new Promise((resolve) => w.run('chrome.runtime').sendMessage('ping', resolve));
  check('WebKit\'s own lastError is put back', w.run('chrome.runtime.lastError') === native);
}

// Errors nobody caught, told to Safience: from the extension's own pages
// and worker, not from content scripts.
{
  const w = world();
  w.target.dispatchEvent(Object.assign(new Event('error'), {
    error: new TypeError("undefined is not an object (evaluating 'chrome.sidePanel.open')"), filename: 'bg.js', lineno: 7,
  }));
  w.target.dispatchEvent(Object.assign(new Event('unhandledrejection'), { reason: new Error('chrome.offscreen is undefined') }));
  await tick();
  const sent = w.native.map((n) => n.message);
  check('an uncaught error is reported', w.native[0]?.application === 'safience' && sent[0]?.api === 'report'
    && /sidePanel/.test(sent[0]?.args[1]) && sent[0]?.args[2] === 'bg.js' && sent[0]?.args[3] === 7, JSON.stringify(sent[0]));
  check('an unhandled rejection is reported', sent[1]?.args[0] === 'rejection' && /offscreen/.test(sent[1]?.args[1]), JSON.stringify(sent[1]));
}
{
  const w = world({ protocol: 'https:' });
  w.target.dispatchEvent(Object.assign(new Event('error'), { error: new Error('the page\'s own') }));
  await tick();
  check('a content script reports nothing', w.native.length === 0, w.native.length);
}

const failed = results.filter((r) => !r.ok);
for (const r of results) console.log(`${r.ok ? 'ok  ' : 'FAIL'} ${r.name}${r.ok || !r.detail ? '' : `: ${r.detail}`}`);
console.log(failed.length ? `FAILED ${failed.length} of ${results.length}` : `PASSED ${results.length}`);
process.exit(failed.length ? 1 : 0);
