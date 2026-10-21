// Safience's shim for Chrome extensions (Docs/ExtensionsDesign.md).
//
// Put first in an extension's worker, its background scripts, its content
// scripts and its pages (ExtensionPreparation.swift), it mends where
// WebKit's extension APIs behave unlike Chrome's, and tells Safience of the
// errors nobody caught. Parts follow Search's (github.com/driceroland/Search,
// MIT, Office Commun, its ExtensionShims.swift), each saying so; the rest of
// Search's, and its answers for the APIs WebKit lacks, are still to come
// (Docs/ExtensionsFromSearch.md).
(() => {
  const root = globalThis;
  const chrome = root.chrome || root.browser;
  // A page's own world, where an extension's MAIN-world script runs with
  // this before it, has no extension APIs: nothing to mend there, and
  // nothing may be left there for a page to see. (Search)
  const ours = (() => { try { return !!(chrome && chrome.runtime && chrome.runtime.id); } catch (e) { return false; } })();
  if (!ours || root.__safienceShim) return;
  Object.defineProperty(root, "__safienceShim", { value: true });
  const runtime = chrome.runtime;
  // On a web page this is a content script.
  const inContent = typeof location !== "undefined" && !/^(chrome|webkit)-extension:$/.test(location.protocol);
  // The extension's background, whichever WebKit runs: its worker, or its
  // page. (Search)
  const background = (typeof ServiceWorkerGlobalScope !== "undefined" && root instanceof ServiceWorkerGlobalScope)
    || (!inContent && typeof document !== "undefined" && (() => {
      try { return typeof chrome.extension?.getBackgroundPage === "function" && chrome.extension.getBackgroundPage() === root; }
      catch (e) { return false; }
    })());

  // Bitwarden's bundled TypeScript uses these as computed class keys before
  // it registers disposable resources: defined before any extension code
  // runs, Symbol.for keeping the key shared by its frames. (Search)
  for (const name of ["dispose", "asyncDispose"]) {
    if (root.Symbol[name] === undefined) Object.defineProperty(root.Symbol, name, { value: root.Symbol.for("Symbol." + name) });
  }

  // WebKit took requestIdleCallback back out after a page-load regression
  // (bug 287681), leaving Proton Pass's form detection without it. Chrome's
  // longest idle deadline is 50 ms; this gives the whole of it. (Search)
  if (typeof root.requestIdleCallback !== "function" || typeof root.cancelIdleCallback !== "function") {
    const idle = new Map();
    let last = 0;
    root.requestIdleCallback = (callback) => {
      const id = ++last;
      idle.set(id, setTimeout(() => {
        if (!idle.delete(id)) return;
        const start = Date.now();
        callback({ didTimeout: false, timeRemaining: () => Math.max(0, 50 - (Date.now() - start)) });
      }, 1));
      return id;
    };
    root.cancelIdleCallback = (id) => {
      const timer = idle.get(id);
      if (timer === undefined) return;
      idle.delete(id);
      clearTimeout(timer);
    };
  }

  // WebKit finds an extension's APIs through the chrome and browser globals
  // when it delivers an event. A sandbox that locks every global away
  // (MetaMask's LavaMoat) cuts it off. Made fixed accessors, they can't be
  // taken away, and a replacement that still carries the APIs is taken;
  // one that hides them (a Proxy, as Proton Pass puts there) isn't. (Search)
  for (const key of ["browser", "chrome"]) {
    // SingleFile installs its own browser getter: browser is left open for it.
    if (key === "browser" && runtime.id === "mpiodijhokgodhhofbcjdecpffjipkle") continue;
    const d = Object.getOwnPropertyDescriptor(root, key);
    if (!d || !d.configurable) continue;
    let value = root[key];
    const carries = (v) => { try { return !!(v && v.runtime && v.runtime.id); } catch (e) { return false; } };
    try {
      Object.defineProperty(root, key, { configurable: false, enumerable: d.enumerable, get: () => value, set: (v) => { if (carries(v)) value = v; } });
    } catch (e) {}
  }

  // WebKit's namespace and event objects are wrappers it doesn't keep
  // alive: once no script holds one, the next chrome.runtime is a fresh
  // object without what was set on it. So what is touched here is held for
  // good, and a member is set as an own property, which takes the place of
  // the prototype's method of the same name. (Search)
  const kept = new Set([chrome, runtime]);
  if (chrome.tabs) kept.add(chrome.tabs);
  try { Object.defineProperty(root, "__safienceKept", { value: kept }); } catch (e) {}
  const put = (target, key, value) => {
    if (target && (typeof target === "object" || typeof target === "function")) kept.add(target);
    try { Object.defineProperty(target, key, { value, configurable: true, writable: true, enumerable: true }); }
    catch (e) { try { target[key] = value; } catch (e2) {} }
  };
  // Set for the callback, then as it was: WebKit's own, if it had one.
  const withLastError = (error, callback) => {
    const before = Object.getOwnPropertyDescriptor(runtime, "lastError");
    put(runtime, "lastError", { message: String(error && error.message || error) });
    try { callback(); } finally {
      try { if (before) Object.defineProperty(runtime, "lastError", before); else delete runtime.lastError; } catch (e) {}
    }
  };

  // Safience itself, through native messaging to "safience": it hears of
  // errors here, and will answer the APIs WebKit lacks.
  const native = (api, args) =>
    runtime.sendNativeMessage("safience", { api, args: JSON.parse(JSON.stringify(args ?? [])) })
      .then((reply) => {
        if (reply && reply.error) throw new Error(reply.error);
        return reply ? reply.value : undefined;
      });

  // Errors nobody caught, in the worker and the extension's own pages, told
  // to Safience, which keeps only those whose words name an API
  // (ExtensionError) and never the words themselves. Not from a content
  // script, where the page's own errors arrive too. macOS 27 tells the app
  // of them itself; this is how it hears where it doesn't.
  if (!inContent && typeof root.addEventListener === "function") {
    const tell = (kind, error, file, line) => {
      try { native("report", [kind, String(error && error.message || error), String(file || ""), Number(line) || 0]).catch(() => {}); } catch (e) {}
    };
    root.addEventListener("error", (e) => tell("error", e.error || e.message, e.filename, e.lineno));
    root.addEventListener("unhandledrejection", (e) => tell("rejection", e.reason, "", 0));
  }

  // Several onMessage listeners: WebKit (on macOS 26, as Search found; 27
  // already waits) takes the first one's return, usually undefined, as the
  // answer. Chrome's rule, as of Chrome 148: the first listener to answer,
  // fail or throw decides; an answer comes by sendResponse after returning
  // true, or by a promise; an empty one is null; a throw or a rejection
  // fails the sender's call. So the extension's listeners are gathered
  // behind one of WebKit's that follows it, and answers WebKit with a
  // promise. (Search) That promise never fails: when one does, WebKit
  // (27.0.1) never calls the sender back. A failure is an answer marked as
  // one instead, which the sender's shim turns back into lastError or a
  // rejection (replied, below); to another extension, which has no shim of
  // Safience's, it is null. An answer of the extension's own that looks
  // like the mark reads as a failure too: at worst a call fails.
  const failure = "__safienceFailed";
  const gathered = new Set();
  const gather = (event, eager, internal) => {
    if (!event || typeof event.addListener !== "function" || gathered.has(event)) return;
    gathered.add(event);
    kept.add(event);
    const add = event.addListener.bind(event);
    const remove = typeof event.removeListener === "function" ? event.removeListener.bind(event) : () => {};
    const listeners = new Set();
    const dispatch = (message, sender) => {
      let settle;
      const answer = new Promise((resolve) => { settle = { resolve }; });
      let answered = false;
      let keep = false;
      const failWith = (error) => {
        let words = "Error";
        try { words = String(error && typeof error.message === "string" ? error.message : error); } catch (e) {}
        answered = true;
        settle.resolve(internal ? { [failure]: words } : null);
      };
      // As Chrome sends it, as JSON, taken when it is given: changed
      // afterwards, it goes as it was; not JSON, it fails.
      const respond = (value) => {
        if (answered) return;
        let copy;
        try {
          const json = value === undefined ? undefined : JSON.stringify(value);
          copy = json === undefined ? null : JSON.parse(json);
        } catch (e) { return failWith(e); }
        answered = true;
        settle.resolve(copy);
      };
      const fail = (error) => { if (!answered) failWith(error); };
      for (const listener of [...listeners]) {
        let result;
        let then;
        try {
          result = listener(message, sender, respond);
          then = result !== true && result ? result.then : undefined;
        } catch (e) { fail(e); setTimeout(() => { throw e; }); continue; }
        if (result === true) keep = true;
        else if (typeof then === "function") {
          keep = true;
          try { then.call(result, respond, fail); } catch (e) { fail(e); }
        }
      }
      return keep || answered ? answer : undefined;
    };
    // Only while there is a listener: a page with none says nothing, as
    // it would without the shim, and so leaves a message to the pages and
    // the worker that answer it. The background's is WebKit's from the
    // start: a worker may add listeners only while it starts, and WebKit
    // wakes it for an event only if it knows a listener for it. (Search)
    let attached = false;
    const attach = () => { if (!attached) { attached = true; add(dispatch); } };
    put(event, "addListener", (f) => { if (typeof f === "function") { listeners.add(f); attach(); } });
    put(event, "removeListener", (f) => {
      listeners.delete(f);
      if (attached && !listeners.size && !(background && eager)) { attached = false; remove(dispatch); }
    });
    put(event, "hasListener", (f) => listeners.has(f));
    put(event, "hasListeners", () => listeners.size > 0);
    if (background && eager) attach();
  };
  // browser is the same as chrome in WebKit; if it isn't, its events are
  // gathered too, only when listened to.
  for (const ns of new Set([chrome, root.browser].filter(Boolean))) {
    kept.add(ns);
    gather(ns.runtime && ns.runtime.onMessage, ns === chrome, true);
    gather(ns.runtime && ns.runtime.onMessageExternal, ns === chrome, false);
  }

  // A reply that never came, asked for with a callback: Chrome calls back
  // with lastError set; WebKit calls back with nothing and no error, and
  // code that pings a tab to see whether its script is there waits for
  // ever. An empty answer is null, from the gate above, as in Chrome, and
  // sets nothing. (Search) A failure marked as one by the gate is
  // lastError, or a rejection when there is no callback.
  const replying = new Set();
  const replied = (ns, method) => {
    const original = ns && ns[method];
    if (typeof original !== "function" || replying.has(ns)) return;
    replying.add(ns);
    kept.add(ns);
    const failed = (reply) => reply !== null && typeof reply === "object" && typeof reply[failure] === "string";
    put(ns, method, function (...args) {
      const callback = args.length && typeof args[args.length - 1] === "function" ? args.pop() : null;
      const promise = Promise.resolve(original.apply(ns, args));
      if (!callback) return promise.then((reply) => { if (failed(reply)) throw new Error(reply[failure]); return reply; });
      promise.then(
        (reply) => failed(reply) ? withLastError(new Error(reply[failure]), () => callback())
          : reply === undefined ? withLastError(new Error("The message port closed before a response was received."), () => callback())
          : callback(reply),
        (error) => withLastError(error, () => callback()));
    });
  };
  for (const ns of new Set([chrome, root.browser].filter(Boolean))) {
    if (ns.runtime) replied(ns.runtime, "sendMessage");
    if (ns.tabs) replied(ns.tabs, "sendMessage");
  }

  // The static routing API of Chrome's service workers (the install event's
  // addRoutes): a speed-up, so nothing is lost without it. (Search)
  if (typeof root.InstallEvent === "function" && root.InstallEvent.prototype && !root.InstallEvent.prototype.addRoutes) {
    root.InstallEvent.prototype.addRoutes = () => Promise.resolve();
  }
})();
