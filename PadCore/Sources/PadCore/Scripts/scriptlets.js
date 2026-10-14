// Takes away what "ad blocker detected" scripts look for, on the sites whose
// filters ask for it (ScriptedFilters.swift). The lists call these
// scriptlets: each is a small, fixed thing done to the page's own world
// before its scripts run, named by a filter and given that filter's words
// (a property's name, a word to look for). The rules written in below are
// data; nothing a list says is ever run as code. It goes only into pages of
// the sites the lists name. None of these reads or writes cookies.
(function (rules) {
  'use strict';
  if (!Array.isArray(rules)) return;
  const win = window;
  const doc = document;
  // What a stopped script is stopped with: told apart from the page's own
  // errors, and kept from the page's error handlers.
  const magic = 'x' + Math.random().toString(36).slice(2, 12);
  win.addEventListener('error', (event) => {
    if (typeof event.message === 'string' && event.message.includes(magic)) {
      event.stopImmediatePropagation();
      event.preventDefault();
    }
  }, true);
  function stop() {
    throw new ReferenceError(magic);
  }

  // "text", "/pattern/flags", or nothing for anything; "!…" for the opposite.
  function matcher(needle) {
    if (needle === undefined || needle === '') return () => true;
    let wanted = true;
    let text = String(needle);
    if (text[0] === '!') {
      wanted = false;
      text = text.slice(1);
    }
    const parts = /^\/(.+)\/([a-z]*)$/.exec(text);
    let test = (value) => value.includes(text);
    if (parts) {
      try {
        const pattern = new RegExp(parts[1], parts[2].replace('g', ''));
        test = (value) => pattern.test(value);
      } catch (_) {
        test = () => false;
      }
    }
    return (value) => test(String(value)) === wanted;
  }

  function isObject(value) {
    return (typeof value === 'object' && value !== null) || typeof value === 'function';
  }

  // Calls `install(owner, name)` for the last name of "a.b.c" on the object
  // that holds it: now if a.b is there, or when the page makes it.
  function reach(chain, install) {
    const names = String(chain).split('.');
    (function walk(owner, index) {
      const name = names[index];
      if (index === names.length - 1) {
        install(owner, name);
        return;
      }
      let value = owner[name];
      if (isObject(value)) {
        walk(value, index + 1);
        return;
      }
      const had = Object.getOwnPropertyDescriptor(owner, name);
      if (had && !had.configurable) return;
      Object.defineProperty(owner, name, {
        configurable: true,
        enumerable: true,
        get() { return value; },
        set(next) {
          value = next;
          if (isObject(next)) {
            try { walk(next, index + 1); } catch (_) {}
          }
        },
      });
    })(win, 0);
  }

  // A property with a getter and a setter of ours over whatever was there:
  // the object's own, or the one it has from its prototype, as
  // document.createElement is Document's.
  function trap(owner, name, onGet, onSet) {
    const own = Object.getOwnPropertyDescriptor(owner, name);
    if (own && !own.configurable) return;
    let had = own;
    for (let from = Object.getPrototypeOf(owner); !had && from; from = Object.getPrototypeOf(from)) {
      had = Object.getOwnPropertyDescriptor(from, name);
    }
    let value = had && 'value' in had ? had.value : undefined;
    Object.defineProperty(owner, name, {
      configurable: true,
      enumerable: had ? had.enumerable : true,
      get() {
        onGet();
        return had && had.get ? had.get.call(this) : value;
      },
      set(next) {
        onSet();
        if (had && had.set) had.set.call(this, next); else value = next;
      },
    });
  }

  const none = {};
  // The values a filter may set: a short, fixed list, as the lists have it.
  function constant(text) {
    switch (text) {
      case 'undefined': return undefined;
      case 'false': return false;
      case 'true': return true;
      case 'null': return null;
      case 'noopFunc': return function () {};
      case 'trueFunc': return function () { return true; };
      case 'falseFunc': return function () { return false; };
      case 'emptyArr': case '[]': return [];
      case 'emptyObj': case '{}': return {};
      case 'emptyStr': case '': return '';
      default:
        if (/^-?\d{1,5}$/.test(text)) return Number(text);
        return none;
    }
  }

  // "url:… method:…", or a plain word for the address.
  function request(spec) {
    const tests = {};
    for (const word of String(spec || '').split(/\s+/)) {
      if (!word) continue;
      const pair = /^(url|method):(.*)$/.exec(word);
      if (pair) tests[pair[1]] = matcher(pair[2]); else tests.url = matcher(word);
    }
    return (url, method) => (!tests.url || tests.url(url)) && (!tests.method || tests.method(method || 'GET'));
  }

  function whenReady(work) {
    if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', work); else work();
    win.addEventListener('load', work);
  }

  const scriptlets = {
    'set-constant'(chain, text) {
      const value = constant(text === undefined ? '' : text);
      if (value === none) return;
      reach(chain, (owner, name) => {
        const had = Object.getOwnPropertyDescriptor(owner, name);
        if (had && !had.configurable) return;
        Object.defineProperty(owner, name, { configurable: true, enumerable: true, get() { return value; }, set() {} });
      });
    },
    'abort-on-property-read'(chain) {
      reach(chain, (owner, name) => {
        const had = Object.getOwnPropertyDescriptor(owner, name);
        if (had && !had.configurable) return;
        Object.defineProperty(owner, name, { configurable: true, get: stop, set() {} });
      });
    },
    'abort-on-property-write'(chain) {
      reach(chain, (owner, name) => trap(owner, name, () => {}, stop));
    },
    // Stops the script running now, if its own text has the word in it.
    'abort-current-script'(chain, needle, context) {
      const inText = matcher(needle);
      const inSource = context === undefined || context === '' ? null : matcher(context);
      const check = () => {
        const script = doc.currentScript;
        if (!script) return;
        if (inSource ? inSource(script.src || '') && inText(script.textContent || '') : inText(script.textContent || '')) stop();
      };
      reach(chain, (owner, name) => trap(owner, name, check, check));
    },
    // Stops whatever reaches the property from code whose call stack has the word in it.
    'abort-on-stack-trace'(chain, needle) {
      const test = matcher(needle);
      const check = () => {
        if (test(new Error(magic).stack || '')) stop();
      };
      reach(chain, (owner, name) => trap(owner, name, check, check));
    },
    'no-setTimeout-if'(needle, delay) { timer('setTimeout', needle, delay); },
    'no-setInterval-if'(needle, delay) { timer('setInterval', needle, delay); },
    // An answer with nothing in it, for a request the filter names.
    'no-fetch-if'(spec) {
      if (typeof win.fetch !== 'function') return;
      const test = request(spec);
      win.fetch = new Proxy(win.fetch, {
        apply(target, self, args) {
          const first = args[0];
          const url = typeof first === 'string' ? first : (first && first.url) || String(first);
          const method = (args[1] && args[1].method) || (first && first.method) || 'GET';
          if (test(url, method)) return Promise.resolve(new Response('', { status: 200, statusText: 'OK' }));
          return Reflect.apply(target, self, args);
        },
      });
    },
    'no-xhr-if'(spec) {
      const test = request(spec);
      const proto = win.XMLHttpRequest && win.XMLHttpRequest.prototype;
      if (!proto) return;
      const empty = new WeakSet();
      const answer = [['readyState', 4], ['status', 200], ['statusText', 'OK'], ['response', ''], ['responseText', '']];
      proto.open = new Proxy(proto.open, {
        apply(target, self, args) {
          if (test(String(args[1]), String(args[0] || 'GET'))) {
            empty.add(self);
          } else if (empty.has(self)) {
            // A request a page opens again, for something the filter
            // doesn't name, is that one's: it goes, and it is answered.
            empty.delete(self);
            for (const [name] of answer) delete self[name];
          }
          return Reflect.apply(target, self, args);
        },
      });
      proto.send = new Proxy(proto.send, {
        apply(target, self, args) {
          if (!empty.has(self)) return Reflect.apply(target, self, args);
          for (const [name, value] of answer) {
            Object.defineProperty(self, name, { configurable: true, get() { return value; } });
          }
          setTimeout(() => {
            for (const type of ['readystatechange', 'load', 'loadend']) self.dispatchEvent(new Event(type));
          }, 1);
          return undefined;
        },
      });
    },
    // Empties a script (or other element of that name) whose text has the
    // word in it, as the page is read and before the script runs.
    'remove-node-text'(nodeName, needle) {
      const name = String(nodeName).toLowerCase();
      const test = matcher(needle);
      const empty = (node) => {
        const holder = node.nodeType === 3 ? node.parentNode : node;
        if (!holder || holder.nodeType !== 1 || holder.nodeName.toLowerCase() !== name) return;
        if (holder.textContent && test(holder.textContent)) holder.textContent = '';
      };
      new MutationObserver((records) => {
        for (const record of records) for (const node of record.addedNodes) empty(node);
      }).observe(doc, { childList: true, subtree: true });
    },
    'addEventListener-defuser'(type, handler) {
      const ofType = matcher(type);
      const ofHandler = matcher(handler);
      const proto = win.EventTarget && win.EventTarget.prototype;
      if (!proto) return;
      proto.addEventListener = new Proxy(proto.addEventListener, {
        apply(target, self, args) {
          let source = '';
          try { source = typeof args[1] === 'function' ? Function.prototype.toString.call(args[1]) : String(args[1]); } catch (_) {}
          if (ofType(String(args[0])) && ofHandler(source)) return undefined;
          return Reflect.apply(target, self, args);
        },
      });
    },
    // Only where it is there: taking away what isn't is still a change to
    // the element, which the page and this script's own watch would answer.
    'remove-attr'(names, selector, behavior) {
      strip(names, selector, behavior, (node, name) => { if (node.hasAttribute(name)) node.removeAttribute(name); });
    },
    'remove-class'(names, selector, behavior) {
      strip(names, selector, behavior, (node, name) => { if (node.classList.contains(name)) node.classList.remove(name); }, true);
    },
    'set-local-storage-item'(key, value) { store('localStorage', key, value); },
    'set-session-storage-item'(key, value) { store('sessionStorage', key, value); },
  };

  // A timer whose code has the word in it (and, where the filter says,
  // that waits so long, or "!" for any other wait) is set to do nothing,
  // and once: an interval of nothing would wake the page for as long as it
  // is open. The page still gets a number it can clear.
  function timer(name, needle, delay) {
    const original = win[name];
    const once = win.setTimeout;
    if (typeof original !== 'function' || typeof once !== 'function') return;
    const test = matcher(needle);
    const text = delay === undefined ? '' : String(delay);
    const wait = /^!?\d+$/.test(text) ? Number(text.replace('!', '')) : null;
    const other = text[0] === '!';
    win[name] = new Proxy(original, {
      apply(target, self, args) {
        // The wait first: it is a number, and the code is a text to make.
        if (wait !== null && ((Number(args[1]) || 0) === wait) === other) return Reflect.apply(target, self, args);
        let source = '';
        try { source = typeof args[0] === 'function' ? Function.prototype.toString.call(args[0]) : String(args[0]); } catch (_) {}
        if (!test(source)) return Reflect.apply(target, self, args);
        return Reflect.apply(once, self, [function () {}, args[1]]);
      },
    });
  }

  function strip(names, selector, behavior, remove, classes) {
    const list = String(names || '').split(/\s*\|\s*/).filter(Boolean);
    if (!list.length) return;
    const query = selector || list.map((name) => (classes ? '.' + CSS.escape(name) : '[' + CSS.escape(name) + ']')).join(',');
    const work = () => {
      let nodes = [];
      try { nodes = doc.querySelectorAll(query); } catch (_) {}
      for (const node of nodes) for (const name of list) remove(node, name);
    };
    whenReady(work);
    if (/\bstay\b/.test(String(behavior || ''))) {
      // Again when elements come, and when the class or one of the
      // attributes is put back: no other change to an element is watched.
      let waiting = 0;
      new MutationObserver(() => {
        if (!waiting) waiting = setTimeout(() => { waiting = 0; work(); }, 100);
      }).observe(doc, { childList: true, subtree: true, attributes: true, attributeFilter: classes ? ['class'] : list });
    }
  }

  // A page's own storage, given one of a few plain values or cleared of a key.
  function store(kind, key, text) {
    const allowed = ['', 'undefined', 'null', 'true', 'false', 'yes', 'no', 'on', 'off', 'accept', 'reject', 'emptyObj', 'emptyArr', '$remove$'];
    if (!allowed.includes(text) && !/^\d{1,5}$/.test(text || '')) return;
    try {
      const storage = win[kind];
      if (text === '$remove$') storage.removeItem(key);
      else storage.setItem(key, text === 'emptyObj' ? '{}' : text === 'emptyArr' ? '[]' : text);
    } catch (_) {}
  }

  for (const rule of rules) {
    const run = scriptlets[rule[0]];
    if (!run) continue;
    try { run.apply(null, rule.slice(1)); } catch (_) {}
  }
})(/*RULES*/null);
