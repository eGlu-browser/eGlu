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
function world({ protocol = 'chrome-extension:', apis = true, times = 1, reply, background = false, lastError, channel = false, page = '/page.html', nativeReply, i18n = {}, extra = {}, scripting, permissions = [], namespaces = {}, worker = false, runtimeExtra = {}, events = null, manifestExtra = {} } = {}) {
  const native = [];
  const event = () => {
    const listeners = [];
    return {
      listeners,
      addListener(f) { listeners.push(f); },
      removeListener(f) { const i = listeners.indexOf(f); if (i >= 0) listeners.splice(i, 1); },
      hasListener(f) { return listeners.includes(f); },
      // WebKit's rule: the first listener's return decides.
      deliver(message, sender = { id: 'sender' }) {
        return new Promise((resolve, reject) => {
          let answered = false;
          const sendResponse = (value) => { if (!answered) { answered = true; resolve(value); } };
          let first;
          listeners.forEach((listener, i) => {
            const result = listener(message, sender, sendResponse);
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
      sendNativeMessage: async (application, message) => { native.push({ application, message }); return nativeReply ? nativeReply(message) : { value: null }; },
      getURL: (path) => 'chrome-extension://abcdefghijklmnopabcdefghijklmnop/' + path,
      getManifest: () => ({ background: { service_worker: 'bg.js' }, permissions, ...manifestExtra }),
      ...runtimeExtra,
    },
    tabs: { sendMessage: async () => undefined },
    i18n,
    ...(scripting ? { scripting } : {}),
    ...namespaces,
  } : undefined;
  if (chrome && lastError) chrome.runtime.lastError = lastError;
  // A timer's throw reaches the world's error event, as in a browser.
  const timer = (f, ms) => setTimeout(() => {
    try { f(); } catch (error) { target.dispatchEvent(Object.assign(new Event('error'), { error })); }
  }, ms);
  const origin = protocol === 'chrome-extension:' ? 'chrome-extension://abcdefghijklmnopabcdefghijklmnop' : 'https://example.com';
  const globals = {
    setTimeout: timer, clearTimeout, EventTarget, DOMException,
    location: { protocol, origin, pathname: page, href: origin + page },
    addEventListener: target.addEventListener.bind(target),
    ...extra,
  };
  if (chrome) { globals.chrome = chrome; globals.browser = chrome; }
  // A service worker: what the shim takes for one.
  if (worker) { globals.__isWorker = true; globals.ServiceWorkerGlobalScope = class { static [Symbol.hasInstance](x) { return !!(x && x.__isWorker); } }; }
  if (channel) globals.BroadcastChannel = BroadcastChannel;
  const context = vm.createContext(globals);
  if (background) {
    context.document = {};
    chrome.extension = { getBackgroundPage: () => vm.runInContext('globalThis', context) };
  }
  // The events the extension's code names, as ExtensionPreparation fills them in.
  const filled = events ? shim.replace('/*__EGLU_EVENTS__*/[]', JSON.stringify(events)) : shim;
  for (let i = 0; i < times; i++) vm.runInContext(filled, context, { filename: 'extension-shim.js' });
  return { context, chrome, native, target, run: (code) => vm.runInContext(code, context) };
}

// Missing language detection is supplied locally, including content-script callers.
{
  const result = { isReliable: true, languages: [{ language: 'en', percentage: 100 }] };
  const w = world({ nativeReply: (message) => ({ value: message.api === 'i18n.detectLanguage' ? result : null }) });
  const detect = w.run('chrome.i18n.detectLanguage');
  check('missing i18n.detectLanguage is supplied', typeof detect === 'function');
  if (typeof detect === 'function') {
    check('language detection promise preserves the Chrome result', JSON.stringify(await detect('A synthetic English paragraph.')) === JSON.stringify(result));
    const callback = await new Promise((done) => detect('Text', done));
    check('language detection supports callback callers', JSON.stringify(callback) === JSON.stringify(result));
    check('only supplied text is passed to the language endpoint', w.native.filter((n) => n.message.api === 'i18n.detectLanguage').every((n) => n.message.args.length === 1 && typeof n.message.args[0] === 'string'));
    const sent = w.native.length;
    const invalid = await detect({ text: 'not a string' }).then(() => false, (e) => e.name === 'TypeError');
    check('invalid language input rejects without sending native data', invalid && w.native.length === sent);
    const invalidCallback = await new Promise((done) => detect(null, () => done(w.chrome.runtime.lastError?.message)));
    check('invalid callback language input exposes lastError only during callback', typeof invalidCallback === 'string' && w.chrome.runtime.lastError === undefined);

  }
  const native = () => Promise.resolve(result);
  const given = world({ i18n: { detectLanguage: native } });
  check('native i18n.detectLanguage is retained', given.run('chrome.i18n.detectLanguage') === native);
  const worker = world({ background: true, nativeReply: () => ({ value: result }) });
  const sender = { id: worker.chrome.runtime.id, url: 'https://synthetic.invalid/page' };
  const envelope = { __egluCall: { space: 'i18n', method: 'detectLanguage', args: ['Synthetic text'] } };
  const answered = await worker.chrome.runtime.onMessage.deliver(envelope, sender);
  check('same-extension content script can detect only supplied text', JSON.stringify(answered?.value) === JSON.stringify(result));
  const before = worker.native.length;
  await worker.chrome.runtime.onMessage.deliver(envelope, { id: 'another-extension', url: sender.url });
  check('another extension cannot use the private language relay', worker.native.length === before);
  const denied = await worker.chrome.runtime.onMessage.deliver({ __egluCall: { space: 'tabs', method: 'query', args: [{}] } }, sender);
  check('language relay does not grant a content script tab APIs', typeof denied?.error === 'string');
  const content = world({ protocol: 'https:', reply: (message) => message.__egluCall ? { value: result } : undefined });
  const contentDetect = content.run('chrome.i18n.detectLanguage');
  check('content scripts receive the language method', typeof contentDetect === 'function');
  if (typeof contentDetect === 'function') {
    check('content detection uses its worker instead of native messaging', JSON.stringify(await contentDetect('Text')) === JSON.stringify(result) && content.native.length === 0);
  }
}

// The Mac's colour sampler stands in for Chromium's EyeDropper: a pick
// answers a colour, a cancel rejects as AbortError, and a world that has
// its own keeps it.
{
  const w = world({ nativeReply: (message) => ({ value: message.api === 'eyeDropper.open' ? '#336699' : null }) });
  check('an extension page gets an EyeDropper', w.run('typeof EyeDropper === "function"'));
  const picked = await w.run('new EyeDropper().open()');
  check('a pick answers a colour as Chrome\'s does', picked?.sRGBHex === '#336699', JSON.stringify(picked));
  check('the pick asked eGlu', w.native.some((n) => n.message.api === 'eyeDropper.open' && n.message.args.length === 0), JSON.stringify(w.native));
  const cancel = world({ nativeReply: () => ({ error: 'AbortError' }) });
  const reason = await cancel.run('new EyeDropper().open()').then(() => 'resolved', (e) => e);
  check('a cancel rejects with a DOMException named AbortError', reason instanceof DOMException && reason.name === 'AbortError', String(reason && reason.name || reason));
  class OwnDropper { open() { return Promise.resolve({ sRGBHex: '#000000' }); } }
  const already = world({ extra: { EyeDropper: OwnDropper } });
  check('an existing EyeDropper is kept', already.run('EyeDropper') === OwnDropper
    && await already.run('new EyeDropper().open().then((c) => c.sRGBHex)') === '#000000');
  const content = world({ protocol: 'https:', reply: (message) => message.__egluCall ? { value: '#a1b2c3' } : undefined });
  check('a content script has the picker too', content.run('typeof EyeDropper === "function"'));
  const relayed = await content.run('new EyeDropper().open()');
  check('its pick goes through the worker, not native messaging', relayed?.sRGBHex === '#a1b2c3' && content.native.length === 0, JSON.stringify(relayed));
  const worker = world({ background: true, nativeReply: () => ({ value: '#102030' }) });
  const sender = { id: worker.chrome.runtime.id, url: 'https://synthetic.invalid/page' };
  const envelope = { __egluCall: { space: 'eyeDropper', method: 'open', args: [] } };
  const answered = await worker.chrome.runtime.onMessage.deliver(envelope, sender);
  check('a content script\'s pick reaches the sampler', answered?.value === '#102030', JSON.stringify(answered));
  const before = worker.native.length;
  await worker.chrome.runtime.onMessage.deliver(envelope, { id: 'another-extension', url: sender.url });
  check('another extension cannot ask for a pick', worker.native.length === before);
}

// An abort while the sampler is open answers at once, as AbortError.
{
  const w = world({ nativeReply: () => new Promise(() => {}) });
  const controller = new AbortController();
  w.context.signal = controller.signal;
  const pending = w.run('new EyeDropper().open({ signal })').then(() => 'resolved', (e) => e);
  controller.abort();
  const reason = await Promise.race([pending, new Promise((r) => setTimeout(() => r('still open'), 200))]);
  check('an abort during a pick rejects at once with AbortError', reason instanceof DOMException && reason.name === 'AbortError', String(reason && reason.name || reason));
}

// chrome.scripting puts the shim in front of the files it injects, so a
// click-only grant's injection gets the stand-ins too.
{
  const calls = [];
  const scripting = { executeScript: async (injection) => { calls.push(injection); return [{ result: 'ran' }]; } };
  const worker = world({ background: true, scripting });
  const result = await worker.run('chrome.scripting.executeScript({ target: { tabId: 1 }, files: ["content.js"] })');
  check('injected files get the shim first', JSON.stringify(calls[0]?.files) === JSON.stringify(['_eglu/shim.js', 'content.js']), JSON.stringify(calls[0]));
  check('the injection answers as it did', result?.[0]?.result === 'ran', JSON.stringify(result));
  await worker.run('chrome.scripting.executeScript({ target: { tabId: 1 }, files: ["page.js"], world: "MAIN" })');
  check('the page\'s own world gets no shim', JSON.stringify(calls[1]?.files) === JSON.stringify(['page.js']), JSON.stringify(calls[1]));
  await worker.run('chrome.scripting.executeScript({ target: { tabId: 1 }, func: () => 1 })');
  check('a function injection is left as it is', calls[2] && !('files' in calls[2]), JSON.stringify(calls[2]));
  await worker.run('chrome.scripting.executeScript({ target: { tabId: 1 }, files: ["/_eglu/shim.js", "a.js"] })');
  check('a shim already named is not added twice', JSON.stringify(calls[3]?.files) === JSON.stringify(['/_eglu/shim.js', 'a.js']), JSON.stringify(calls[3]));
}

// A page's own world: no extension APIs, nothing left behind.
{
  const w = world({ apis: false });
  check('a world without extension APIs is left as it was', w.run('typeof __egluShim === "undefined" && typeof requestIdleCallback === "undefined"'));
}

// Run twice, as when two content script entries match one page: once.
{
  const w = world({ times: 2 });
  check('the shim runs once in a world', w.run('__egluShim === true'));
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

// Between the extension's pages, on their channel (Search's): a page with
// nothing to say steps aside until the worker has spoken, and a page's
// message reaches its other pages, which WebKit doesn't bring it to.
{
  const options = { background: false, channel: true };
  const pageA = world({ ...options, page: '/options.html' });
  const bg = world({ background: true, channel: true, page: '/bg.js' });
  pageA.run('chrome.runtime.onMessage').addListener(() => undefined);
  bg.run('chrome.runtime.onMessage').addListener(() => undefined);
  await tick(20);
  const started = Date.now();
  const pageAnswer = pageA.chrome.runtime.onMessage.deliver({ about: 'nothing' });
  await tick(5);
  await bg.chrome.runtime.onMessage.deliver({ about: 'nothing' });
  const reply = await Promise.race([pageAnswer, new Promise((r) => setTimeout(() => r('still waiting'), 3000))]);
  check('a page with nothing to say waits for the worker, then says nothing', reply === undefined && Date.now() - started < 3000, String(reply));
  // The worker answers, late: the page waits until it has, then says nothing.
  bg.run('chrome.runtime.onMessage').addListener((message, sender, respond) => { if (message && message.slow) { setTimeout(() => respond('slow answer'), 400); return true; } });
  const slowAsked = Date.now();
  const pageSide = pageA.chrome.runtime.onMessage.deliver({ slow: 1 });
  await tick(5);
  const workerSide = await bg.chrome.runtime.onMessage.deliver({ slow: 1 });
  const pageSaid = await Promise.race([pageSide, new Promise((r) => setTimeout(() => r('still waiting'), 3000))]);
  check('a page steps aside until a slow answer has gone, then says nothing', workerSide === 'slow answer' && pageSaid === undefined
    && Date.now() - slowAsked >= 400 && Date.now() - slowAsked < 3000, workerSide + ' / ' + String(pageSaid));
  const pageB = world({ ...options, page: '/popup.html' });
  const seen = [];
  pageB.run('chrome.runtime.onMessage').addListener((message) => { seen.push(message); });
  await tick(20);
  pageA.run('chrome.runtime').sendMessage({ sync: 1 }).catch(() => {});
  await tick(150);
  check('a page\'s message reaches the extension\'s other pages', seen.some((m) => m && m.sync === 1), JSON.stringify(seen));
  // And its answer comes back to the sender, which WebKit brought nothing.
  pageB.run('chrome.runtime.onMessage').addListener((message, sender, respond) => { if (message && message.ask) { setTimeout(() => respond('from B'), 20); return true; } });
  const relayedReply = await pageA.run('chrome.runtime').sendMessage({ ask: 1 });
  check('a relayed message\'s answer reaches its sender', relayedReply === 'from B', String(relayedReply));
  const asked = Date.now();
  const none = await pageA.run('chrome.runtime').sendMessage({ nobody: 1 });
  check('one nobody answers doesn\'t wait long', none === undefined && Date.now() - asked < 1500, String(Date.now() - asked));
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
  check('an answer that isn\'t JSON fails', typeof reply?.__egluFailed === 'string', JSON.stringify(reply));
}
{
  const w = world();
  w.run('chrome.runtime.onMessage').addListener(() => ({ get then() { throw new Error('getter'); } }));
  w.run('chrome.runtime.onMessage').addListener((message, sender, respond) => { respond('later listener'); });
  const reply = await w.chrome.runtime.onMessage.deliver('ping');
  check('a return whose then throws fails, and the rest still run', reply?.__egluFailed === 'getter', JSON.stringify(reply));
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
  check('a rejection is answered as a failure, not a failed promise', reply?.__egluFailed === 'nope', JSON.stringify(reply));
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
  check('a throw fails it, first', reply?.__egluFailed === 'thrown', JSON.stringify(reply));
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
  const w = world({ reply: () => ({ __egluFailed: 'nope' }) });
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

// Members and namespaces WebKit leaves out, read at the top of a worker:
// one missing is a TypeError that stops the whole worker. iCloud
// Passwords' worker listens to these webNavigation events as it starts;
// 1Password's to chrome.notifications; both read chrome.privacy.
// What threw is the result, as in WebKit, where it stops the worker.
const attempt = (f) => { try { return f(); } catch (e) { return `${e.name}: ${e.message}`; } };
{
  const onBeforeNavigate = { addListener() {} };
  const w = world({ background: true, namespaces: { webNavigation: { onBeforeNavigate, getAllFrames: async () => [] } } });
  const started = attempt(() => w.run(`(() => {
    chrome.webNavigation.onBeforeNavigate.addListener(() => {});
    chrome.webNavigation.onHistoryStateUpdated.addListener(() => {});
    chrome.webNavigation.onTabReplaced.addListener(() => {});
    return "started";
  })()`));
  check('a worker listening to webNavigation events WebKit lacks gets past them', started === 'started', started);
  check('WebKit\'s own webNavigation members are kept', w.run('chrome.webNavigation.onBeforeNavigate') === onBeforeNavigate);
  check('webNavigation\'s enums are there', attempt(() => w.run('chrome.webNavigation.TransitionType.FORM_SUBMIT')) === 'form_submit'
    && attempt(() => w.run('chrome.webNavigation.TransitionQualifier.FORWARD_BACK')) === 'forward_back');
  check('no webNavigation is made where WebKit gives none', world().run('chrome.webNavigation') === undefined);
}
{
  const executeScript = async () => [];
  const w = world({ background: true, scripting: { executeScript } });
  check('a worker reading scripting\'s enums gets them (Bitwarden)', attempt(() => w.run('chrome.scripting.ExecutionWorld.ISOLATED')) === 'ISOLATED'
    && attempt(() => w.run('chrome.scripting.StyleOrigin.USER')) === 'USER');
}
{
  // WebKit's words for a tab it holds no web view for: one not loaded yet.
  const refused = () => Promise.reject(new Error('Invalid call to webNavigation.getAllFrames(). Tab not found.'));
  const frames = [{ frameId: 0, parentFrameId: -1, url: 'https://example.com/' }];
  const tabs = { sendMessage: async () => undefined, get: async (id) => { if (id === 9) throw new Error('No tab with id: 9.'); return { id }; } };
  // A callback is called with nothing when WebKit refuses, as WebKit does.
  const getAllFrames = ({ tabId }, callback) => {
    const answer = tabId === 1 ? Promise.resolve(frames) : refused();
    if (typeof callback !== 'function') return answer;
    answer.then(callback, () => callback(undefined));
  };
  const w = world({ background: true, namespaces: { tabs, webNavigation: { getAllFrames } } });
  const nav = w.run('chrome.webNavigation');
  check('a loaded tab\'s frames are WebKit\'s', await nav.getAllFrames({ tabId: 1 }) === frames);
  const unloaded = await nav.getAllFrames({ tabId: 2 }).then((list) => list, (e) => e.message);
  check('a tab whose page isn\'t loaded has no frames, not an error', Array.isArray(unloaded) && unloaded.length === 0, unloaded);
  const gone = await nav.getAllFrames({ tabId: 9 }).then(() => 'answered', (e) => e.message);
  check('a tab that isn\'t there is still refused', /Tab not found/.test(gone), gone);
  const byCallback = await new Promise((done) => nav.getAllFrames({ tabId: 2 }, done));
  check('and through a callback', Array.isArray(byCallback) && byCallback.length === 0);
  // iCloud Passwords' start, every tab's frames in turn: it gets past an unloaded one.
  const seen = await w.run(`(async () => {
    const seen = [];
    for (const id of [2, 1]) for (const frame of await chrome.webNavigation.getAllFrames({ tabId: id })) seen.push(id + ":" + frame.frameId);
    return seen.join(",");
  })()`).catch((e) => e.message);
  check('a worker listing every tab\'s frames gets past one not loaded', seen === '1:0', seen);
}
{
  const onChanged = { addListener() {} };
  const w = world({ background: true, namespaces: { storage: { local: {}, onChanged } } });
  const started = attempt(() => w.run('chrome.storage.managed.onChanged.addListener(() => {}), "started"'));
  check('a worker listening to managed storage gets past it', started === 'started', started);
  if (started === 'started') {
    check('managed storage holds nothing', JSON.stringify(await w.run('chrome.storage.managed').get(null)) === '{}');
    check('and says so through a callback', JSON.stringify(await new Promise((done) => w.run('chrome.storage.managed').get(['policy'], done))) === '{}');
    check('asked by name, nothing', JSON.stringify(await w.run('chrome.storage.managed').get('policy')) === '{}');
    const defaults = { enabled: true, server: 'https://example.com' };
    const given = await w.run('chrome.storage.managed').get(defaults);
    check('asked with defaults, the defaults', JSON.stringify(given) === JSON.stringify(defaults) && given !== defaults, JSON.stringify(given));
    const byCallback = await new Promise((done) => w.run('chrome.storage.managed').get(defaults, done));
    check('and through a callback', JSON.stringify(byCallback) === JSON.stringify(defaults), JSON.stringify(byCallback));
  }
  check('WebKit\'s own storage members are kept', w.run('chrome.storage.onChanged') === onChanged);
}
{
  // A .wasm of the extension's own, which WebKit serves untyped: compiled
  // whole. A website's is left to WebKit's streaming.
  const WebAssembly = {
    instantiateStreaming: async () => 'streamed', compileStreaming: async () => 'streamed',
    instantiate: async (bytes) => 'whole ' + bytes.byteLength, compile: async (bytes) => 'whole ' + bytes.byteLength,
  };
  const response = (url) => ({ url, arrayBuffer: async () => new ArrayBuffer(3) });
  const w = world({ background: true, extra: { WebAssembly } });
  w.context.own = response('chrome-extension://abcdefghijklmnopabcdefghijklmnop/core.wasm');
  w.context.site = response('https://example.com/core.wasm');
  check('the extension\'s own .wasm is compiled whole', await w.run('WebAssembly.instantiateStreaming(Promise.resolve(own))') === 'whole 3'
    && await w.run('WebAssembly.compileStreaming(own)') === 'whole 3');
  check('a website\'s is streamed as before', await w.run('WebAssembly.instantiateStreaming(site)') === 'streamed');
}
{
  const w = world({ background: true, permissions: ['privacy'] });
  const saving = attempt(() => w.run('chrome.privacy.services.passwordSavingEnabled'));
  check('a worker gets privacy\'s settings', typeof saving === 'object', saving);
  if (typeof saving === 'object') {
  check('privacy\'s password saving reads as off, and not eGlu\'s to change',
    JSON.stringify(await saving.get({})) === JSON.stringify({ value: false, levelOfControl: 'not_controllable' }));
  const byCallback = await new Promise((done) => saving.get({}, done));
  check('and the same through a callback', byCallback?.value === false);
  const refused = await saving.set({ value: false }).then(() => 'set', (e) => e.message);
  check('a change is refused', /can't be changed/.test(refused), refused);
  const lastError = await new Promise((done) => saving.set({ value: false }, () => done(w.chrome.runtime.lastError?.message)));
  check('as lastError for a callback, there only while it runs', /can't be changed/.test(lastError) && w.chrome.runtime.lastError === undefined);
  check('clearing it is nothing to refuse', await saving.clear({}) === undefined);
  const other = await w.run('chrome.privacy.websites.thirdPartyCookiesAllowed').get({}).then(() => 'answered', (e) => e.message);
  check('a setting eGlu has no word on says so rather than make one up', /isn't available/.test(other), other);
  // iCloud Passwords' settings, as its worker and popup start.
  const ran = w.run(`(async () => {
    const s = chrome.privacy.services;
    s.passwordSavingEnabled && s.passwordSavingEnabled.onChange.addListener(() => {});
    s.autofillCreditCardEnabled && s.autofillCreditCardEnabled.onChange.addListener(() => {});
    chrome.privacy.network.webRTCIPHandlingPolicy.onChange.addListener(() => {});
    const got = await s.autofillAddressEnabled.get({});
    return got.levelOfControl === "not_controllable" ? "left alone" : "set";
  })()`);
  check('a password manager reading privacy settings gets past them', await ran === 'left alone');
  }
  check('no privacy namespace without its permission', world({ background: true }).run('chrome.privacy') === undefined);
  const own = { services: {} };
  check('WebKit\'s own privacy, if it has one, is kept', world({ permissions: ['privacy'], namespaces: { privacy: own } }).run('chrome.privacy') === own);
}
{
  const w = world({ background: true, permissions: ['notifications'] });
  const started = attempt(() => w.run(`(() => {
    chrome.notifications.onClicked.addListener(() => {});
    chrome.notifications.onButtonClicked.addListener(() => {});
    chrome.notifications.onClosed.addListener(() => {});
    return "started";
  })()`));
  check('a worker listening to notifications gets past them', started === 'started', started);
  if (started === 'started') {
  check('a notification asked for is given the id it named', await w.run('chrome.notifications').create('saved', { type: 'basic', title: 't', message: 'm' }) === 'saved');
  const made = await new Promise((done) => w.run('chrome.notifications').create({ type: 'basic', title: 't', message: 'm' }, done));
  check('or one of its own, through a callback', typeof made === 'string' && made.length > 0, made);
  check('the permission level reads denied', await w.run('chrome.notifications').getPermissionLevel() === 'denied');
  check('notifications ask eGlu nothing', !w.native.some((n) => String(n.message?.api).startsWith('notifications')));
  }
  check('no notifications namespace without its permission', world({ background: true }).run('chrome.notifications') === undefined);
}

// Search's list of members WebKit leaves out.
{
  const content = world({ protocol: 'https:' });
  check('a content script reads runtime\'s enums (GPTZero)', content.run('chrome.runtime.OnInstalledReason.INSTALL') === 'install'
    && content.run('chrome.runtime.PlatformOs.MAC') === 'mac');
  const w = world({ background: true, namespaces: { windows: { getCurrent: async () => ({}) }, declarativeNetRequest: { updateDynamicRules: async () => {} } } });
  check('a worker listens to windows.onBoundsChanged (Session Buddy)', attempt(() => { w.run('chrome.windows.onBoundsChanged.addListener(() => {})'); return 'ok'; }) === 'ok');
  check('windows\' enums are there', w.run('chrome.windows.WindowState.MAXIMIZED') === 'maximized' && w.run('chrome.windows.CreateType.POPUP') === 'popup');
  const refused = await w.run('chrome.declarativeNetRequest').updateStaticRules({ rulesetId: 'a', disableRuleIds: [1] }).then(() => 'done', (e) => e.message);
  check('what eGlu doesn\'t do is refused, not answered as done', /isn't available in eGlu/.test(refused), refused);
  check('declarativeNetRequest\'s constants are there', w.run('chrome.declarativeNetRequest.RuleActionType.UPGRADE_SCHEME') === 'upgradeScheme'
    && w.run('chrome.declarativeNetRequest.ResourceType.XMLHTTPREQUEST') === 'xmlhttprequest');
  check('tabs\' zoom reads as Chrome\'s default', (await w.run('chrome.tabs').getZoomSettings()).mode === 'automatic');
}

// Small differences from Chrome's: menus, storage, groupId.
{
  const made = [], stored = [];
  const onUpdated = { listeners: null, list: [], addListener(f) { this.list.push(f); }, removeListener(f) { this.list = this.list.filter((g) => g !== f); }, hasListener(f) { return this.list.includes(f); } };
  delete onUpdated.listeners;
  const w = world({ background: true, namespaces: {
    contextMenus: { create: (props) => { made.push(props); return 1; }, update: () => {} },
    storage: { local: { set: async (items) => { if (Object.getPrototypeOf(items) === null) throw new Error('Object expected'); stored.push(items); } } },
    tabs: { sendMessage: async () => undefined, query: async () => [{ id: 1 }, { id: 2, groupId: 7 }], get: async (id) => ({ id }), onUpdated },
  } });
  w.run('chrome.contextMenus').create({ id: 'a', contexts: ['browser_action', 'launcher', 'page'] });
  check('a menu item for the old button goes in the button\'s menu, none for a launcher', JSON.stringify(made[0].contexts) === '["action","page"]', JSON.stringify(made[0]));
  const bare = await w.run('(async () => { const o = Object.create(null); o.a = 1; await chrome.storage.local.set(o); return "set"; })()').catch((e) => e.message);
  check('an item with no prototype is stored', bare === 'set' && stored[0].a === 1, bare);
  const tabs = await w.run('chrome.tabs').query({});
  check('every tab has a groupId, -1 in no group', tabs[0].groupId === -1 && tabs[1].groupId === 7);
  const seen = [];
  w.run('chrome.tabs').onUpdated.addListener((id, change, tab) => seen.push(tab.groupId));
  onUpdated.list[0](1, {}, { id: 1 });
  check('and the tab an event hands its listener too', seen[0] === -1);
}

// Ports between the extension's own ends: WebKit hands a message on twice
// (seen on 27.0.1); numbered, it is heard once. The popup's port comes with
// no tab (Passbolt).
{
  const ev = () => { const list = []; return { list, addListener(f) { list.push(f); }, removeListener(f) { const i = list.indexOf(f); if (i >= 0) list.splice(i, 1); }, hasListener(f) { return list.includes(f); } }; };
  const own = 'chrome-extension://abcdefghijklmnopabcdefghijklmnop/';
  const pair = (sender) => {
    const a = { name: 'popup', onMessage: ev(), onDisconnect: ev() }, b = { name: 'popup', onMessage: ev(), onDisconnect: ev(), sender };
    // Every message twice, as WebKit delivers it once per world.
    a.postMessage = (m) => { for (let i = 0; i < 2; i++) for (const f of [...b.onMessage.list]) f(m, b); };
    b.postMessage = (m) => { for (let i = 0; i < 2; i++) for (const f of [...a.onMessage.list]) f(m, a); };
    return [a, b];
  };
  const popupSender = { id: 'abcdefghijklmnopabcdefghijklmnop', url: own + 'popup.html', frameId: 0, tab: { id: 5, index: NaN, url: own + 'popup.html' } };
  const [a, b] = pair(popupSender);
  const onConnect = ev();
  const page = world({ runtimeExtra: { connect: () => a, onConnect: ev() } });
  const worker = world({ worker: true, runtimeExtra: { connect: () => ({}), onConnect } });
  const workerHeard = [], pageHeard = [];
  let seenSender = null;
  worker.run('chrome.runtime').onConnect.addListener((port) => {
    seenSender = port.sender;
    port.onMessage.addListener((m) => { workerHeard.push(m); port.postMessage({ reply: m }); });
  });
  const port = page.run('chrome.runtime').connect({ name: 'popup' });
  port.onMessage.addListener((m) => pageHeard.push(m));
  for (const f of [...onConnect.list]) f(b);
  port.postMessage('state?');
  check('a message between the extension\'s own ends is heard once', JSON.stringify(workerHeard) === '["state?"]', JSON.stringify(workerHeard));
  check('and its answer once', JSON.stringify(pageHeard) === '[{"reply":"state?"}]', JSON.stringify(pageHeard));
  check('the popup\'s port comes with no tab, as in Chrome', seenSender && seenSender.url === popupSender.url && !('tab' in seenSender), JSON.stringify(seenSender));
  // A content script's port is the website's: left as it is.
  const site = { id: 'abcdefghijklmnopabcdefghijklmnop', url: 'https://example.com/', frameId: 0, tab: { id: 6, index: 0, url: 'https://example.com/' } };
  const plain = { name: 'cs', sender: site, onMessage: ev(), onDisconnect: ev(), postMessage: (m) => { plain.sent = m; } };
  let csPort = null;
  worker.run('chrome.runtime').onConnect.addListener((p) => { if (p.name === 'cs') { csPort = p; p.postMessage('hi'); } });
  for (const f of [...onConnect.list]) f(plain);
  check('a content script\'s port goes as it is', csPort === plain && plain.sent === 'hi' && plain.sender.tab.id === 6);
}

// chrome.idle and chrome.power, the Mac's (ExtensionAnswers).
{
  const ticks = [];
  const w = world({ background: true, permissions: ['idle', 'power'], extra: { setInterval: (f, ms) => { ticks.push(ms); return 1; } },
    nativeReply: (m) => ({ value: m.api === 'idle.queryState' ? 'locked' : null }) });
  check('idle asks the Mac', await w.run('chrome.idle').queryState(60) === 'locked'
    && w.native.some((n) => n.message.api === 'idle.queryState' && n.message.args[0] === 60));
  check('idle\'s state and event are there', w.run('chrome.idle.IdleState.LOCKED') === 'locked'
    && attempt(() => { w.run('chrome.idle.onStateChanged.addListener(() => {})'); return 'ok'; }) === 'ok' && ticks[0] === 15000);
  await w.run('chrome.power').requestKeepAwake('display');
  check('power asks the Mac', w.native.some((n) => n.message.api === 'power.requestKeepAwake' && n.message.args[0] === 'display'));
  check('no idle or power without their permissions', world({ background: true }).run('chrome.idle') === undefined && world({ background: true }).run('chrome.power') === undefined);
}
// The popup: no current tab, and among the popup views, as in Chrome.
{
  const popupTab = { id: 9, index: NaN, url: 'chrome-extension://abcdefghijklmnopabcdefghijklmnop/popup.html' };
  const w = world({ page: '/popup.html', extra: { document: {} }, manifestExtra: { action: { default_popup: 'popup.html' } },
    namespaces: { tabs: { sendMessage: async () => undefined, getCurrent: async () => popupTab, get: async (id) => ({ id }) },
      extension: { getViews: () => [] } } });
  check('the popup has no current tab', await w.run('chrome.tabs').getCurrent() === undefined);
  check('and is among the popup views', w.run('chrome.extension.getViews({ type: "popup" }).length') === 1
    && w.run('chrome.extension.getViews({ type: "tab" }).length') === 0);
  const tabPage = world({ page: '/options.html', extra: { document: {} }, manifestExtra: { action: { default_popup: 'popup.html' } },
    namespaces: { tabs: { sendMessage: async () => undefined, getCurrent: async () => ({ id: 3, index: 2 }), get: async (id) => ({ id }) } } });
  check('a page in a tab keeps its tab', (await tabPage.run('chrome.tabs').getCurrent()).id === 3);
}

// A worker's listeners, held from its first moment (ExtensionPreparation's
// event list). WebKit's stand-in events here: one that refuses a listener
// as too late once told to, and keeps the filter it was given.
{
  const webkitEvent = () => {
    const listeners = [];
    return {
      started: false, filters: [],
      addListener(f, filter) { if (this.started) throw new Error('Invalid call to runtime.onConnect.addListener(). Listeners must be added during startup.'); listeners.push(f); this.filters.push(filter); },
      removeListener(f) { const i = listeners.indexOf(f); if (i >= 0) listeners.splice(i, 1); },
      hasListener(f) { return listeners.includes(f); },
      fire(...args) { for (const f of [...listeners]) f(...args); },
      count() { return listeners.length; },
    };
  };
  const port = () => ({ disconnected: false, disconnect() { this.disconnected = true; } });
  {
    const onConnect = webkitEvent();
    const w = world({ worker: true, runtimeExtra: { onConnect }, events: ['runtime.onConnect'] });
    check('a named event has WebKit\'s listener from the first moment', onConnect.count() === 1);
    const early = port();
    onConnect.fire(early);
    check('a port with nobody listening is closed, as in Chrome', early.disconnected);
    const heard = [];
    w.run('chrome.runtime').onConnect.addListener((p) => heard.push(p));
    const later = port();
    onConnect.fire(later);
    check('a port with a listener is heard, and left open', heard[0] === later && !later.disconnected);
    onConnect.started = true;
    const late = [];
    const added = attempt(() => { w.run('chrome.runtime').onConnect.addListener((p) => late.push(p)); return 'added'; });
    check('a listener WebKit refuses as too late is taken', added === 'added', added);
    const third = port();
    onConnect.fire(third);
    check('and hears what comes after', late[0] === third && heard[1] === third);
  }
  {
    const onCompleted = webkitEvent();
    const w = world({ worker: true, namespaces: { webNavigation: { onCompleted, getAllFrames: async () => [] } }, events: [] });
    const filter = { url: [{ hostSuffix: 'example.com' }] };
    w.run('chrome.webNavigation').onCompleted.addListener(() => {}, filter);
    check('a listener\'s filter stays WebKit\'s', onCompleted.filters.includes(filter) && onCompleted.count() === 1);
    onCompleted.started = true;
    const added = attempt(() => { w.run('chrome.webNavigation').onCompleted.addListener(() => {}); return 'added'; });
    check('an event the code doesn\'t name takes a late listener without a throw', added === 'added', added);
  }
  {
    const onConnect = webkitEvent();
    world({ background: true, runtimeExtra: { onConnect }, events: ['runtime.onConnect'] });
    check('an extension page holds no stand-in', onConnect.count() === 0);
  }
}

// Errors nobody caught, told to eGlu: from the extension's own pages
// and worker, not from content scripts.
{
  const w = world();
  w.target.dispatchEvent(Object.assign(new Event('error'), {
    error: new TypeError("undefined is not an object (evaluating 'chrome.sidePanel.open')"), filename: 'bg.js', lineno: 7,
  }));
  w.target.dispatchEvent(Object.assign(new Event('unhandledrejection'), { reason: new Error('chrome.offscreen is undefined') }));
  await tick();
  const sent = w.native.map((n) => n.message);
  check('an uncaught error is reported', w.native[0]?.application === 'eglu' && sent[0]?.api === 'report'
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
