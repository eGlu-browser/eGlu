// Hides what a site's filters ask for and WebKit's rule lists can't say
// (ScriptedFilters.swift): elements found by what they say, by what is
// inside them or by an XPath, and plain selectors for a site named with a
// wildcard. It goes only into pages of the sites the lists name, in the
// app's own world, with those sites' rules written in below; a page on any
// other site never sees it. It reads the page's elements and their text,
// sets styles on the ones it finds, and sends nothing anywhere.
(function (rules) {
  'use strict';
  if (!rules) return;
  const doc = document;

  // Whether a chain can be asked of what the page added alone, instead of
  // the whole document again. It can when nothing it reads is beside or
  // outside what it starts from: its first selector depends on an element
  // and what is above it, and every step after reads inside the elements
  // found. Then only two kinds of element can come to fit it when nodes are
  // added: the new ones, and the ones the new ones are inside.
  const reachesAcross = /[+~]|:has\(|:nth-|:first-|:last-|:only-|:empty/;
  function staysNear(steps, top) {
    if (top && (!steps.length || steps[0][0] !== 'css')) return false;
    return steps.every(([kind, value], index) => {
      if (kind === 'css') return top && index === 0 ? !reachesAcross.test(value) : !/^\s*[+~]/.test(value);
      if (kind === 'has') return staysNear(value, false);
      // Up from an element, and nothing after: what came after would be
      // read from somewhere the element isn't inside.
      if (kind === 'up') return top && index === steps.length - 1;
      return kind === 'text' || kind === 'len';
    });
  }
  const chains = (rules.hide || []).map((steps) => ({ steps, near: staysNear(steps, true) }));
  // What a `:style()` filter sets, a property at a time as the engine
  // reads it, so that each pass can tell whether the page has set it
  // otherwise since.
  function declarations(css) {
    const probe = doc.createElement('div').style;
    probe.cssText = css;
    const sets = [];
    for (let index = 0; index < probe.length; index += 1) {
      const name = probe[index];
      sets.push([name, probe.getPropertyValue(name), probe.getPropertyPriority(name)]);
    }
    return sets;
  }
  const restyles = (rules.style || []).map((item) => ({ steps: item.steps, sets: declarations(item.css), near: staysNear(item.steps, true) }));
  // Chains that read beside or outside are asked of the whole document
  // whenever it changes, as every chain used to be.
  const far = chains.some((chain) => !chain.near) || restyles.some((item) => !item.near);

  // Plain selectors, in one style sheet. Each is tried first: one the
  // engine can't parse would take every selector in the rule with it.
  let sheet = null;
  function addSheet() {
    const good = [];
    for (const selector of rules.css || []) {
      try {
        doc.querySelector(selector);
        good.push(selector);
      } catch (_) {}
    }
    if (!good.length) return;
    sheet = doc.createElement('style');
    sheet.textContent = good.join(',\n') + ' { display: none !important; }';
    attach();
  }

  // The sheet goes in as soon as the document has somewhere to put it, and
  // back in if the page takes it out.
  function attach() {
    const parent = doc.head || doc.documentElement;
    if (sheet && parent && !sheet.isConnected) parent.appendChild(sheet);
  }

  // "text" or "/pattern/flags", as the lists write what to look for. Made
  // once for each: a pattern made again for every element it is tried on
  // was a good part of what a pass cost.
  const testers = new Map();
  function tester(needle) {
    let test = testers.get(needle);
    if (test) return test;
    const parts = /^\/(.+)\/([a-z]*)$/.exec(needle);
    if (!parts) {
      test = (text) => text.includes(needle);
    } else {
      try {
        // Without the flags that make a pattern remember where it stopped.
        const pattern = new RegExp(parts[1], parts[2].replace(/[gy]/g, ''));
        test = (text) => pattern.test(text);
      } catch (_) {
        test = () => false;
      }
    }
    testers.set(needle, test);
    return test;
  }

  // CSS that goes on from an element already found. " .ad" and "> a" look
  // inside it; "+ div" and "~ div" look beside it, which a query from the
  // element can't reach, so those are asked of its parent, by its place.
  function onward(node, selector) {
    const text = selector.trim();
    if (text[0] === '+' || text[0] === '~') {
      const parent = node.parentElement;
      if (!parent) return [];
      const place = Array.prototype.indexOf.call(parent.children, node) + 1;
      return Array.from(parent.querySelectorAll(':scope > :nth-child(' + place + ') ' + text));
    }
    return Array.from(node.querySelectorAll(':scope ' + text));
  }

  // The elements a list of steps finds. `from` is the elements to start
  // from, or null for the whole document; `inside` says a first selector
  // looks inside them (:has) where it otherwise tests them (:not).
  function find(steps, from, inside) {
    let nodes = from;
    steps.forEach(([kind, value], index) => {
      if (kind === 'css') {
        if (nodes === null) {
          nodes = Array.from(doc.querySelectorAll(value));
        } else if (/^\s|^[>+~]/.test(value) || (index === 0 && inside)) {
          nodes = nodes.flatMap((node) => onward(node, value));
        } else {
          nodes = nodes.filter((node) => node.matches(value));
        }
        return;
      }
      if (kind === 'xpath') {
        const out = [];
        for (const root of nodes === null ? [doc] : nodes) {
          const found = doc.evaluate(value, root, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          for (let i = 0; i < found.snapshotLength; i += 1) {
            const node = found.snapshotItem(i);
            if (node && node.nodeType === 1) out.push(node);
          }
        }
        nodes = out;
        return;
      }
      // The rest choose among elements already found. A chain starts from a
      // selector or a path (ScriptedFilter.hiding): a test with nothing named
      // to choose among would be asked of every element on the page, the
      // page itself among them, and finds nothing here.
      if (nodes === null) {
        nodes = [];
        return;
      }
      if (kind === 'text') {
        const test = tester(value);
        nodes = nodes.filter((node) => test(node.textContent || ''));
      } else if (kind === 'has') {
        nodes = nodes.filter((node) => find(value, [node], true).length > 0);
      } else if (kind === 'not') {
        nodes = nodes.filter((node) => find(value, [node], false).length === 0);
      } else if (kind === 'up') {
        const levels = /^\d+$/.test(value) ? Number(value) : 0;
        nodes = nodes.map((node) => {
          if (!levels) return node.parentElement && node.parentElement.closest(value);
          let up = node;
          for (let i = 0; i < levels && up; i += 1) up = up.parentElement;
          return up;
        }).filter(Boolean);
      } else if (kind === 'style') {
        const colon = value.indexOf(':');
        const name = value.slice(0, colon).trim();
        const test = tester(value.slice(colon + 1).trim());
        nodes = nodes.filter((node) => colon > 0 && test(getComputedStyle(node).getPropertyValue(name)));
      } else if (kind === 'len') {
        nodes = nodes.filter((node) => (node.textContent || '').length >= value);
      } else {
        nodes = [];
      }
    });
    return Array.from(new Set(nodes || []));
  }

  // What the page added since the last pass, or everything (`whole`): at
  // the start, when the page has loaded, after more was added than is worth
  // telling apart, and now and then while the page goes on changing. That
  // last is for what changes with nothing added, which isn't watched: a
  // class put on an element, a row of a long list given another's place.
  // How often goes by what looking through everything costs, three hundred
  // times over: every second on a light page, every three where it takes
  // ten milliseconds, so it is a third of a hundredth of the page's time.
  let whole = true;
  const added = new Set();
  const most = 200;
  let wholeCost = 0;
  let lastWhole = 0;

  // The new elements, and the elements the new nodes are inside.
  function surroundings() {
    const fresh = [];
    const above = new Set();
    for (const node of added) {
      if (!node.isConnected) continue;
      if (node.nodeType === 1) fresh.push(node);
      for (let up = node.parentElement; up && !above.has(up); up = up.parentElement) above.add(up);
    }
    return { fresh, above };
  }

  // A chain's elements among those: the ones its first selector names, then
  // the rest of its steps from them.
  function nearby(steps, around) {
    const selector = steps[0][1];
    const starts = new Set();
    for (const node of around.above) if (node.matches(selector)) starts.add(node);
    for (const node of around.fresh) {
      if (node.matches(selector)) starts.add(node);
      for (const inside of node.querySelectorAll(selector)) starts.add(inside);
    }
    return starts.size ? find(steps.slice(1), Array.from(starts), false) : [];
  }

  function conceal(node) {
    if (node.style.getPropertyValue('display') !== 'none') node.style.setProperty('display', 'none', 'important');
  }

  // The elements hidden so far, held weakly: one the page takes out is let go.
  const known = new WeakSet();
  let kept = [];
  // The elements restyled so far, each with what it was given, held the
  // same way and given it again on every pass: a page that draws an
  // element again sets the whole of its style, and what a filter set
  // would be gone for good.
  const restyled = new WeakMap();
  let given = [];
  function restyle(node, sets) {
    for (const [name, value, priority] of sets) {
      if (node.style.getPropertyValue(name) !== value || node.style.getPropertyPriority(name) !== priority) {
        node.style.setProperty(name, value, priority);
      }
    }
  }
  function pass() {
    attach();
    const all = whole;
    const around = all ? null : surroundings();
    whole = false;
    added.clear();
    // What was hidden stays hidden, should the page have put it back.
    kept = kept.filter((ref) => {
      const node = ref.deref();
      if (node && node.isConnected) {
        conceal(node);
        return true;
      }
      if (node) known.delete(node);
      return false;
    });
    given = given.filter((entry) => {
      const node = entry.ref.deref();
      if (node && node.isConnected) {
        restyle(node, entry.sets);
        return true;
      }
      if (node) restyled.delete(node);
      return false;
    });
    const look = (item) => {
      try {
        return all || !item.near ? find(item.steps, null, false) : nearby(item.steps, around);
      } catch (_) {
        return [];
      }
    };
    for (const chain of chains) {
      for (const node of look(chain)) {
        if (!node.style) continue;
        conceal(node);
        if (!known.has(node)) {
          known.add(node);
          kept.push(new WeakRef(node));
        }
      }
    }
    for (const item of restyles) {
      for (const node of look(item)) {
        if (!node.style) continue;
        restyle(node, item.sets);
        const items = restyled.get(node) || [];
        if (items.includes(item)) continue;
        items.push(item);
        restyled.set(node, items);
        given.push({ ref: new WeakRef(node), sets: item.sets });
      }
    }
  }

  // Again a moment after the page changes, and never more often than a
  // pass takes ten times over: a page that changes all the time and is slow
  // to look through is looked through less often, not all the time. A page
  // out of sight is looked through every two seconds at most, and at once
  // when it is seen again, before it is drawn.
  let waiting = 0;
  let cost = 0;
  function run() {
    clearTimeout(waiting);
    waiting = 0;
    const all = whole;
    const began = performance.now();
    pass();
    cost = performance.now() - began;
    if (all) {
      wholeCost = cost;
      lastWhole = began + cost;
    }
  }
  function soon() {
    if (waiting) return;
    waiting = setTimeout(run, Math.max(doc.hidden ? 2000 : 60, Math.min(2000, cost * 10)));
  }
  function everything() {
    whole = true;
    added.clear();
    soon();
  }

  // What the page added is kept for the next pass, and a text that was
  // changed where it stands counts as added: it is what most chains read.
  // Nodes only taken away bring nothing new to hide, and ask for a pass
  // only where a chain reads beside or outside what it starts from, or
  // when everything is due again.
  function changed(records) {
    attach();
    if (!whole && performance.now() - lastWhole > Math.max(1000, Math.min(30000, wholeCost * 300))) {
      whole = true;
      added.clear();
    }
    let any = whole;
    for (const record of records) {
      const nodes = record.type === 'characterData' ? [record.target] : record.addedNodes;
      for (const node of nodes) {
        any = true;
        if (whole) break;
        if (added.size < most) {
          added.add(node);
        } else {
          whole = true;
          added.clear();
        }
      }
    }
    if (any || far) soon();
  }

  // The listeners first, so nothing below can keep them from being there.
  const looking = chains.length > 0 || restyles.length > 0;
  doc.addEventListener('DOMContentLoaded', looking ? everything : attach);
  window.addEventListener('load', looking ? everything : attach);
  addSheet();
  if (looking) {
    doc.addEventListener('visibilitychange', () => {
      if (!doc.hidden && waiting) run();
    });
    // The document itself is watched, not its root element: at the very
    // start there may be no root yet.
    new MutationObserver(changed).observe(doc, { childList: true, characterData: true, subtree: true });
    run();
  } else if (sheet) {
    // Only the sheet to keep: the page is not watched, only the three
    // places the sheet can be taken out of.
    const keeper = new MutationObserver(() => {
      attach();
      watch();
    });
    const watch = () => {
      keeper.disconnect();
      for (const node of [doc, doc.documentElement, doc.head]) {
        if (node) keeper.observe(node, { childList: true });
      }
    };
    watch();
  }
})(/*RULES*/null);
