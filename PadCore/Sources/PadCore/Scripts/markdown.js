// The page as Markdown, for Handoff (Handoff.swift): what the page says, in
// the order it says it, for an app that reads text. It is run once, when
// Handoff is asked for, in the app's own world, and never on a hands-off
// page (Page.markdown). It reads the page's elements and their text, changes
// nothing, and sends nothing anywhere: what it returns goes to the share
// sheet, and from there only where the person says.
//
// One walk over the page as it stands. Nothing is copied to work on (a copy
// of the document is the page's memory over again), and the walk stops at
// `limit` characters, so a page of any size costs what the limit costs.
//
// It returns the page as blocks (PageReading.swift), each as Markdown with
// what the walk knows of it, which is what Handoff organises the file by
// (HandoffCompose.swift):
//
//   kind       heading, paragraph, item, quote, table, code, rule
//   hint       what the page itself calls the part it is in: comments,
//              related, legal, newsletter, share, contents, price, faq,
//              transcript, review. From the container's own name, ARIA
//              label and role first, its id and class after: a class says
//              nothing on a site whose classes are generated, so nothing
//              in Swift rests on a hint alone.
//   group,     which run of repeated siblings it is in, and which of them:
//   item       five or more children of one parent, most with a link, each
//              a small thing (search results, cards, replies).
//   onScreen   whether any of it shows in the window now.
//   selected   whether the person's selection touches it.
//   start,     its first words without Markdown where they differ from its
//   link       text, and its first link's address.
//   plain      how long its words are without Markdown, where that differs:
//              a link's address is no part of what a block says, and a
//              list of links is told by how much of its words is links.
//
// Beside the blocks: what was counted for the kind of page (Handoff.kind),
// what the page declares of its things to search engines (schema.org), and
// the selection itself, read on its own so that it is there even when it
// lies in a part the walk left out.
(function (limit) {
  'use strict';
  const doc = document;
  const most = Math.max(200, Number(limit) || 100000);
  // Past this many blocks the rest of the page is one block.
  const mostBlocks = 3000;

  // Never the page's content: code, controls, pictures drawn by script, and
  // the parts of a page that are the same on every page of its site.
  const skipped = new Set(['script', 'style', 'noscript', 'template', 'head', 'svg', 'canvas', 'video', 'audio',
    'iframe', 'object', 'embed', 'select', 'button', 'input', 'textarea', 'nav', 'aside', 'dialog']);
  const skippedRoles = new Set(['navigation', 'banner', 'contentinfo', 'complementary', 'search', 'dialog',
    'alertdialog', 'menu', 'menubar', 'toolbar', 'tablist', 'tree', 'tooltip', 'progressbar']);
  // What runs on in a line. Everything else starts a line of its own: a
  // page's own elements (a site's components) most often hold blocks.
  const inline = new Set(['a', 'abbr', 'b', 'bdi', 'bdo', 'big', 'cite', 'code', 'data', 'del', 'dfn', 'em', 'font',
    'i', 'img', 'ins', 'kbd', 'label', 'mark', 'nobr', 'picture', 'q', 'rp', 'rt', 'ruby', 's', 'samp', 'slot',
    'small', 'source', 'span', 'strike', 'strong', 'sub', 'sup', 'time', 'tt', 'u', 'var', 'wbr', 'math']);
  const blocky = 'p, div, li, h1, h2, h3, h4, h5, h6, table, ul, ol, blockquote, pre, section, article';
  // How a span or a link is laid out when it is a box of its own: a cell of
  // a row (a flexible box's or a grid's children are made blocks), or a
  // block by the page's styles. One set inline in a line, however it is
  // boxed, is not here: a word's letters are, where each is animated.
  const boxes = new Set(['block', 'flex', 'grid', 'list-item', 'flow-root', 'table', 'table-cell']);

  // The words in a container's name that say what part of a page it is.
  // Whole words only, and few: a wrong hint sets real content aside.
  const hintOf = new Map();
  for (const [hint, words] of [
    ['comments', ['comment', 'comments', 'disqus', 'discussion', 'discussions', 'replies', 'responses']],
    ['related', ['related', 'recommended', 'recommendations', 'popular', 'trending']],
    ['legal', ['legal', 'disclaimer', 'copyright']],
    ['newsletter', ['newsletter']],
    ['share', ['share', 'sharing']],
    ['contents', ['toc']],
    ['price', ['price', 'prices', 'pricing', 'plans']],
    ['faq', ['faq', 'faqs']],
    ['transcript', ['transcript', 'captions']],
    ['review', ['review', 'reviews', 'ratings', 'testimonial', 'testimonials']],
  ]) {
    for (const word of words) hintOf.set(word, hint);
  }
  // Names seen, and what they came to: a page repeats its class names.
  const named = new Map();

  let blocks = [];
  let size = 0;
  let full = false;
  // The block being put together: its Markdown, its first words without,
  // and how long all of its words are without.
  let text = '';
  let plain = '';
  let spoken = 0;
  // What a block's lines begin with: a list item's mark on its first line
  // and spaces under it, ">" down a quotation.
  const prefixes = [];
  // Inside something that is one run of words whatever it holds (a link, a
  // table's cell): blocks there don't start lines.
  let running = 0;
  // The words of the last run, without Markdown.
  let ran = '';
  // Inside something read whether it shows or not (a section not yet opened).
  let unseen = 0;
  // What the walk counts for the kind of page: blocks of 200 characters or
  // more (writing to be read, not labels) and how much is in them, links
  // and the characters in them, and the first headings.
  let long = 0;
  let written = 0;
  let links = 0;
  let linked = 0;
  const headings = [];

  // Where the walk is: the element, the hints of the containers around it
  // (the innermost last), and the repeated sibling it is inside, if any.
  let from = null;
  let at = null;
  const hints = [];
  let member = null;
  let members = new WeakMap();
  let groups = 0;
  let items = 0;
  // Of the block being put together: where it started, its links, and the
  // first and last text it took, which say where it is on the page.
  let started = null;
  let blockLinks = 0;
  let blockLinked = 0;
  let firstLink = '';
  let firstText = null;
  let lastText = null;

  // The person's selection, if there is one, and a range to lay over each block.
  const selection = typeof getSelection === 'function' ? getSelection() : null;
  const chosen = selection && selection.rangeCount && !selection.isCollapsed ? selection.getRangeAt(0) : null;
  const span = doc.createRange();
  let reached = false;

  // Whether an element is drawn. One with no box of its own whose children
  // are drawn in its place (display: contents, as a slot has and as sites'
  // frameworks wrap things in) counts as drawn: the engine's own answer for
  // it is no, and everything inside it would be lost.
  const asks = typeof Element.prototype.checkVisibility === 'function';
  function shows(element) {
    if (asks && element.checkVisibility({ checkVisibilityCSS: true, visibilityProperty: true })) return true;
    const display = getComputedStyle(element).display;
    return display === 'contents' || (!asks && display !== 'none');
  }

  // `words` as Markdown, and as they read without it where that differs.
  function say(words, read) {
    if (!words || full) return;
    let bare = read === undefined ? words : read;
    if (!text || text.endsWith(' ') || text.endsWith('\n')) {
      words = words.replace(/^ +/, '');
      bare = bare.replace(/^ +/, '');
    }
    if (!words) return;
    if (!text && !running) started = { at: at, hint: hints.length ? hints[hints.length - 1] : '', member: member };
    text += words;
    if (plain.length < 220) plain += bare;
    // What a run of words comes to is counted once, when it is said as one.
    if (!running) spoken += bare.length;
    if (size + text.length > most) full = true;
  }

  // Whether a box shows in the window.
  function inWindow(box) {
    return box.width > 0 && box.height > 0 && box.bottom > 0 && box.right > 0
      && box.top < (window.innerHeight || 0) && box.left < (window.innerWidth || 0);
  }

  // The block being put together is done with: what was kept of it goes.
  function clear() {
    started = null;
    plain = '';
    spoken = 0;
    blockLinks = 0;
    blockLinked = 0;
    firstLink = '';
    firstText = null;
    lastText = null;
  }

  // A block: its lines, each with what it begins with, and what is known of it.
  function emit(lines, kind, level, element) {
    let made = '';
    for (const line of lines) {
      let start = '';
      for (const prefix of prefixes) {
        start += prefix.used ? prefix.rest : prefix.first;
        prefix.used = true;
      }
      made += (start + line).replace(/\s+$/, '') + '\n';
    }
    made = made.replace(/\n+$/, '');
    if (kind !== 'code') made = made.replace(/\n{3,}/g, '\n\n');
    if (size + made.length + 2 > most) {
      made = made.slice(0, Math.max(0, most - size));
      full = true;
    }
    const where = started || { at: element || at, hint: hints.length ? hints[hints.length - 1] : '', member: member };
    const block = { kind: kind, text: made, characters: made.length, links: blockLinks, linked: blockLinked };
    if (level) block.level = level;
    if (where.hint) block.hint = where.hint;
    if (where.member) {
      block.group = where.member.group;
      block.item = where.member.item;
    }
    // Where it is: by its own text where it has some, else by its element.
    let box = null;
    let touched = false;
    if (!element && firstText && lastText) {
      try {
        span.setStart(firstText, 0);
        span.setEnd(lastText, lastText.data.length);
        const rect = span.getBoundingClientRect();
        touched = !!chosen && span.compareBoundaryPoints(Range.END_TO_START, chosen) < 0
          && span.compareBoundaryPoints(Range.START_TO_END, chosen) > 0;
        box = rect;
      } catch (error) {
        // Text that begins in a component's own tree and ends outside it is no one range: by its element.
      }
    }
    if (!box) {
      const of = element || where.at;
      try {
        if (of && of.getBoundingClientRect) {
          box = of.getBoundingClientRect();
          touched = !!chosen && chosen.intersectsNode(of);
        }
      } catch (error) {
        // Nor can an element in a component's own tree be held against a selection outside it.
      }
    }
    if (box && inWindow(box)) block.onScreen = true;
    if (touched) {
      block.selected = true;
      reached = true;
    }
    const bare = plain.replace(/\s+/g, ' ').trim().slice(0, 220);
    if (kind === 'heading') {
      block.start = (ran || bare).slice(0, 220);
      block.plain = ran.length;
    } else if (bare) {
      if (blockLinks || bare !== made.slice(0, 220)) block.start = bare;
      if (spoken && spoken < made.length) block.plain = spoken;
    }
    if (firstLink) block.link = firstLink;
    clear();
    if (!made) return;
    size += made.length + 2;
    if (blocks.length >= mostBlocks) {
      const last = blocks[blocks.length - 1];
      last.text += '\n\n' + made;
      last.characters = last.text.length;
      return;
    }
    blocks.push(block);
  }

  function flush() {
    if (running) {
      say(' ');
      return;
    }
    const words = text.replace(/[ \t]+\n/g, '\n').trim();
    text = '';
    if (!words) {
      clear();
      return;
    }
    // In a list item, an item. Down a quotation, a quote. Else a paragraph.
    const inner = prefixes.length ? prefixes[prefixes.length - 1] : null;
    const kind = inner ? (inner.listed ? 'item' : 'quote') : 'paragraph';
    // Paragraphs a page parts with empty lines alone (two line breaks) are each a block.
    const pieces = words.split(/\n{2,}/);
    for (const piece of pieces) {
      if (piece.length >= 200) {
        long += 1;
        written += piece.length;
      }
    }
    if (pieces.length === 1) {
      emit(words.split('\n'), kind, 0, null);
      return;
    }
    // Each piece is where the whole run is, which is near enough. The
    // links are the run's: counted once, on its first piece.
    const whole = { started: started, first: firstText, last: lastText, links: blockLinks, linked: blockLinked, link: firstLink, plain: plain,
      spoken: spoken };
    pieces.forEach((piece, index) => {
      started = whole.started;
      firstText = whole.first;
      lastText = whole.last;
      blockLinks = index ? 0 : whole.links;
      blockLinked = index ? 0 : whole.linked;
      firstLink = index ? '' : whole.link;
      plain = index ? '' : whole.plain;
      // The first piece has the run's links, so it is as much shorter without them as the run is.
      spoken = index ? 0 : Math.max(0, piece.length - (words.length - whole.spoken));
      emit(piece.split('\n'), kind, 0, null);
    });
  }

  // The words a node comes to, as one run.
  function run(node) {
    const kept = text;
    const bare = plain;
    text = '';
    plain = '';
    running += 1;
    each(node);
    running -= 1;
    const words = text.replace(/\s+/g, ' ').trim();
    ran = plain.replace(/\s+/g, ' ').trim();
    text = kept;
    plain = bare;
    return words;
  }

  // A component's own tree where it has one, what was put in a slot, or the children.
  function inside(node) {
    if (node.shadowRoot) return node.shadowRoot.childNodes;
    if (node.localName === 'slot' && typeof node.assignedNodes === 'function') {
      const given = node.assignedNodes({ flatten: true });
      if (given.length) return given;
    }
    return node.childNodes;
  }

  function each(node) {
    for (const child of inside(node)) {
      if (full) return;
      walk(child);
    }
  }

  function block(node) {
    flush();
    each(node);
    flush();
  }

  function fenced(node) {
    flush();
    let code = (node.textContent || '').replace(/\s+$/, '');
    if (!code.trim()) return;
    const room = most - size;
    if (code.length > room) code = code.slice(0, Math.max(0, room));
    const language = node.querySelector('[class*="language-"]') || node;
    const name = (/(?:^|\s)lang(?:uage)?-([\w+#.-]+)/.exec(language.getAttribute('class') || '') || [])[1] || '';
    const fence = code.includes('```') ? '````' : '```';
    emit([fence + name].concat(code.split('\n'), [fence]), 'code', 0, node);
  }

  // A table of rows and columns as Markdown's; one that only lays the page
  // out (another table inside it, or said to be for presentation) as the
  // blocks it holds.
  function table(node) {
    const rows = Array.from(node.rows || []);
    const laysOut = node.getAttribute('role') === 'presentation' || node.querySelector('table') || rows.length < 2;
    if (laysOut) return block(node);
    flush();
    const lines = [];
    // How long the table is so far: a cell is put together on its own, away from
    // what counts the page's length, and a table of any size must cost what the limit costs.
    let length = 0;
    for (const row of rows) {
      if (full) break;
      const cells = Array.from(row.cells).map((cell) => run(cell).replace(/\|/g, '\\|'));
      if (!cells.length) continue;
      lines.push('| ' + cells.join(' | ') + ' |');
      // Under the first row that has cells, which is not always the table's first.
      if (lines.length === 1) lines.push('|' + cells.map(() => ' --- |').join(''));
      length += lines[lines.length - 1].length + 1;
      if (size + length > most) full = true;
    }
    if (lines.length) emit(lines, 'table', 0, node);
  }

  function marked(node, mark) {
    if (node.querySelector(blocky)) return each(node);
    const words = run(node);
    if (words) say(mark + words + mark, ran);
  }

  function link(node) {
    const address = node.href;
    const given = node.getAttribute('href') || '';
    if (!address || given.startsWith('#') || !/^https?:/i.test(address)) return each(node);
    const words = run(node);
    if (!words) return;
    // For the page, as Markdown, which is what the kinds were measured by. For
    // the block, its words: a picture's address inside a link is not what the link says.
    links += 1;
    linked += words.length;
    blockLinks += 1;
    blockLinked += ran.length;
    if (!firstLink) firstLink = address;
    say('[' + words + '](' + address + ')', ran);
  }

  function picture(node) {
    const says = (node.getAttribute('alt') || '').replace(/\s+/g, ' ').trim();
    if (!says) return;
    const address = node.currentSrc || node.src || '';
    // Never a picture written into the page as data: megabytes that say nothing.
    say(/^https?:/i.test(address) ? '![' + says + '](' + address + ')' : says, says);
  }

  // A site's top and foot, which a page's own sections also have: only the site's are left out.
  function isSites(node) {
    return !node.closest('article, main, section, [role="main"]');
  }

  // Not the page's content, or not to be seen.
  function leftOut(node, tag) {
    if (skipped.has(tag) || node.hidden || node.getAttribute('aria-hidden') === 'true') return true;
    if (skippedRoles.has(node.getAttribute('role') || '')) return true;
    if ((tag === 'header' || tag === 'footer') && isSites(node)) return true;
    return !unseen && !shows(node);
  }

  // What a name's words say the part is: the first of them that says anything.
  function hintIn(name) {
    if (!name) return '';
    const known = named.get(name);
    if (known !== undefined) return known;
    let hint = '';
    if (name.toLowerCase().replace(/[^a-z]/g, '').includes('tableofcontents')) hint = 'contents';
    if (!hint) {
      for (const one of name.replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase().split(/[^a-z0-9]+/)) {
        hint = hintOf.get(one) || '';
        if (hint) break;
      }
    }
    if (named.size < 5000) named.set(name, hint);
    return hint;
  }

  // What a container calls itself: by its own name and what it tells
  // assistive technology first, by its id and class after. Not the page's
  // outermost boxes: what they are called is said of the whole page.
  function hintFor(node, tag) {
    if (node === from || tag === 'body' || tag === 'html' || tag === 'main' || tag === 'article') return '';
    const label = node.getAttribute('aria-label') || '';
    const told = (tag.includes('-') ? tag + ' ' : '') + (label.length <= 60 ? label + ' ' : '') + (node.getAttribute('role') || '');
    return hintIn(told.trim()) || hintIn(((node.id || '') + ' ' + (node.getAttribute('class') || '')).trim());
  }

  // Marks a parent's children as repeated siblings where they are: five or
  // more with a link, most of the children, each a small thing. Search
  // results, cards and replies are; the sections of a page are not.
  function scan(parent) {
    const kids = parent.children;
    if (kids.length < 5 || kids.length > 2000) return;
    const withLinks = [];
    for (const kid of kids) {
      if (kid.localName === 'a' ? kid.hasAttribute('href') : kid.querySelector('a[href]')) withLinks.push(kid);
    }
    if (withLinks.length < 5 || withLinks.length < kids.length * 0.6) return;
    let small = 0;
    for (const kid of withLinks) {
      if (kid.getElementsByTagName('*').length <= 80) small += 1;
    }
    if (small < withLinks.length * 0.8) return;
    groups += 1;
    for (const kid of withLinks) {
      items += 1;
      members.set(kid, { group: groups, item: items });
    }
  }

  // Walks into an element. Where the walk is, what the element calls
  // itself and which repeated sibling it is hold for as long as it is in it.
  function enter(node, tag, body) {
    const wasAt = at;
    const wasMember = member;
    at = node;
    const container = !inline.has(tag);
    const hint = container ? hintFor(node, tag) : '';
    if (hint) hints.push(hint);
    if (!member) {
      member = members.get(node) || null;
      // Only the outermost: a result's own row of links is part of the result.
      if (!member && container) scan(node);
    }
    body();
    if (hint) hints.pop();
    member = wasMember;
    at = wasAt;
  }

  function walk(node) {
    if (full) return;
    if (node.nodeType === 3) {
      if (node.data.trim()) {
        if (!firstText) firstText = node;
        lastText = node;
      }
      say(node.data.replace(/\s+/g, ' '));
      return;
    }
    if (node.nodeType !== 1) return;
    const tag = node.localName;
    if (leftOut(node, tag)) return;
    // In a run of words a block is only its words, set apart by a space: a
    // heading inside a link, a list inside a table's cell.
    if (running && !inline.has(tag) && tag !== 'br') {
      say(' ');
      each(node);
      say(' ');
      return;
    }
    // A span that is a box of its own is not next to its neighbours' words,
    // though no space is written between them: a label and its value at
    // the two ends of a row.
    const apart = inline.has(tag) && tag !== 'br' && tag !== 'wbr' && boxes.has(getComputedStyle(node).display);
    if (apart) say(' ');
    enter(node, tag, () => element(node, tag));
    if (apart) say(' ');
  }

  function element(node, tag) {
    switch (tag) {
      case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6': {
        flush();
        const words = run(node);
        if (!words) return;
        if (headings.length < 12) headings.push(ran.slice(0, 80));
        blockLinks = 0;
        blockLinked = 0;
        emit(['#'.repeat(Number(tag[1])) + ' ' + words], 'heading', Number(tag[1]), node);
        return;
      }
      case 'br':
        say('\n', ' ');
        return;
      case 'hr':
        flush();
        emit(['---'], 'rule', 0, node);
        return;
      case 'pre':
        return fenced(node);
      case 'table':
        return table(node);
      case 'ul': case 'ol': case 'menu': {
        flush();
        let number = tag === 'ol' ? Number(node.getAttribute('start')) || 1 : 0;
        for (const item of inside(node)) {
          if (full) return;
          if (item.nodeType !== 1 || item.localName !== 'li') {
            walk(item);
            continue;
          }
          if (leftOut(item, 'li')) continue;
          const mark = number ? number + '. ' : '- ';
          if (number) number += 1;
          prefixes.push({ first: mark, rest: ' '.repeat(mark.length), used: false, listed: true });
          enter(item, 'li', () => block(item));
          prefixes.pop();
        }
        return;
      }
      case 'blockquote':
        flush();
        prefixes.push({ first: '> ', rest: '> ', used: false, listed: false });
        each(node);
        flush();
        prefixes.pop();
        return;
      case 'details':
        // What a section holds is the page's, opened or not.
        flush();
        if (!node.open) unseen += 1;
        each(node);
        if (!node.open) unseen -= 1;
        flush();
        return;
      case 'a':
        return link(node);
      case 'img':
        return picture(node);
      case 'strong': case 'b':
        return marked(node, '**');
      case 'em': case 'i':
        return marked(node, '*');
      case 'del': case 's': case 'strike':
        return marked(node, '~~');
      case 'code': case 'kbd': case 'samp': case 'tt': {
        const words = (node.textContent || '').replace(/\s+/g, ' ').trim();
        if (words) say('`' + words + '`', words);
        return;
      }
      case 'q':
        say('"');
        each(node);
        say('"');
        return;
      case 'math': {
        // As it is written out, where the page says how (Wikipedia does).
        const formula = node.getAttribute('alttext');
        say(formula ? '$' + formula + '$' : (node.textContent || '').replace(/\s+/g, ' '));
        return;
      }
      default:
        if (inline.has(tag)) each(node); else block(node);
    }
  }

  // The part of the page that is its content, where the page says which:
  // its one main part, or its one article. Otherwise all of it.
  function start() {
    const mains = doc.querySelectorAll('main, [role="main"]');
    if (mains.length === 1) return mains[0];
    const articles = doc.querySelectorAll('article');
    if (articles.length === 1) return articles[0];
    return doc.body || doc.documentElement;
  }

  function read(root) {
    blocks = [];
    size = 0;
    full = false;
    text = '';
    prefixes.length = 0;
    long = 0;
    written = 0;
    links = 0;
    linked = 0;
    headings.length = 0;
    from = root;
    at = null;
    hints.length = 0;
    member = null;
    members = new WeakMap();
    groups = 0;
    items = 0;
    reached = false;
    clear();
    walk(root);
    flush();
  }

  // What the page's head says of it, in the page's own words.
  function meta(names) {
    for (const name of names) {
      const found = doc.querySelector('meta[property="' + name + '"], meta[name="' + name + '"]');
      const content = found ? (found.getAttribute('content') || '').replace(/\s+/g, ' ').trim() : '';
      if (content) return content.slice(0, 300);
    }
    return '';
  }

  // A value the page declares, as a short line of words.
  function word(value, length) {
    if (typeof value === 'number') return String(value);
    return typeof value === 'string' ? value.replace(/\s+/g, ' ').trim().slice(0, length) : '';
  }

  // Who, of a person or an organisation declared as one, or as a list of them.
  function who(value) {
    const one = Array.isArray(value) ? value[0] : value;
    return one && typeof one === 'object' ? word(one.name, 80) : word(one, 80);
  }

  // What a declared thing says of itself that a reader would ask: the few
  // properties that name it, date it, price it and rate it.
  function said(thing) {
    const facts = {};
    const set = (key, value) => {
      if (value) facts[key] = value;
    };
    set('name', word(thing.headline || thing.name, 150));
    set('author', who(thing.author));
    set('publisher', who(thing.publisher));
    set('published', word(thing.datePublished || thing.uploadDate || thing.dateCreated, 40));
    set('modified', word(thing.dateModified, 40));
    set('duration', word(thing.duration, 20));
    const rating = thing.aggregateRating;
    if (rating && typeof rating === 'object') {
      set('rating', word(rating.ratingValue, 10));
      set('ratings', word(rating.reviewCount || rating.ratingCount, 12));
    }
    // A price with its own currency, from the same offer. Several offers
    // in one currency give the range they span; in more than one, nothing.
    const prices = [];
    const currencies = new Set();
    for (const offer of [].concat(thing.offers || [])) {
      if (!offer || typeof offer !== 'object') continue;
      const currency = word(offer.priceCurrency, 8);
      for (const price of [offer.price, offer.lowPrice, offer.highPrice]) {
        if (price === undefined || price === null || price === '' || !currency) continue;
        const amount = Number(typeof price === 'string' ? price.replace(/,/g, '') : price);
        if (Number.isFinite(amount)) {
          prices.push(amount);
          currencies.add(currency);
        }
      }
    }
    if (prices.length && currencies.size === 1) {
      const low = Math.min(...prices);
      const high = Math.max(...prices);
      set('price', (low === high ? String(low) : low + ' to ' + high) + ' ' + Array.from(currencies)[0]);
    }
    return facts;
  }

  // What the page declares itself and its things to be, to search engines
  // (schema.org's names): the kinds, and each thing with what it says of
  // itself. A thing is the page's own where the page says so (mainEntity,
  // mainEntityOfPage); which of the others is, Handoff decides by the kind.
  function declared() {
    const types = [];
    const things = [];
    const add = (thing, main) => {
      const kinds = [].concat(thing['@type'] || []).filter((one) => typeof one === 'string').map((one) => one.slice(0, 40));
      for (const kind of kinds) {
        if (types.length < 8 && !types.includes(kind)) types.push(kind);
      }
      if (kinds.length && things.length < 12) things.push({ types: kinds, main: main, facts: said(thing) });
    };
    const take = (thing, depth) => {
      if (!thing || typeof thing !== 'object' || depth > 3) return;
      if (Array.isArray(thing)) {
        for (const one of thing) take(one, depth + 1);
        return;
      }
      add(thing, !!thing.mainEntityOfPage);
      for (const own of [].concat(thing.mainEntity || [])) {
        if (own && typeof own === 'object' && !Array.isArray(own)) add(own, true);
      }
      take(thing['@graph'], depth + 1);
    };
    for (const script of doc.querySelectorAll('script[type="application/ld+json"]')) {
      const json = script.textContent || '';
      if (json.length > 50000) continue;
      try {
        take(JSON.parse(json), 0);
      } catch (error) {
        // Not what it says it is: nothing declared.
      }
    }
    return { types: types, things: things };
  }

  // The words around a place the walk did not read, for a selection or a
  // window that is there: the smallest box around it with something to say.
  function around(node) {
    let box = node && node.nodeType === 1 ? node : node && node.parentElement;
    for (let climbed = 0; box && box.parentElement && box.parentElement !== doc.documentElement && climbed < 6; climbed += 1) {
      if ((box.textContent || '').trim().length >= 200) break;
      box = box.parentElement;
    }
    return box ? (box.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 4000) : '';
  }

  const whole = doc.body || doc.documentElement;
  if (!whole) return { blocks: [], facts: {} };
  const main = start();
  let used = main;
  read(main);
  // A main part with next to nothing in it is a page that doesn't say which part is which.
  if (main !== whole && size < 200) {
    used = whole;
    read(whole);
  }

  // The selection as the person made it, and, where the walk never came to
  // it (a part left out, or past the limit), the words around it.
  let focus = null;
  if (chosen) {
    const picked = String(selection).replace(/[ \t\f\v]+/g, ' ').replace(/\s*\n\s*/g, '\n').trim().slice(0, 4000);
    if (picked) {
      focus = { selection: picked };
      if (!reached) focus.excerpt = around(chosen.commonAncestorContainer);
    }
  } else if (full && !blocks.some((one) => one.onScreen) && window.innerHeight > 0) {
    // The page was longer than the walk, and the window is past where it stopped.
    const seen = around(doc.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2));
    if (seen) focus = { selection: '', excerpt: seen };
  }

  const says = declared();
  const result = {
    blocks: blocks,
    truncated: full,
    facts: {
      description: meta(['description', 'og:description', 'twitter:description']),
      type: meta(['og:type']),
      site: meta(['og:site_name', 'application-name', 'apple-mobile-web-app-title']),
      schema: says.types,
      headings: headings.slice(),
      characters: Math.max(0, size - 2),
      long: long,
      written: written,
      links: links,
      linked: linked,
      // Things to press and things to fill in, over the whole page: what a
      // tool is made of, and a page to read has few of.
      controls: doc.querySelectorAll('button, [role="button"], [role="tab"], [role="menuitem"], [role="switch"]').length,
      fields: doc.querySelectorAll('input:not([type="hidden"]), textarea, select, [contenteditable]:not([contenteditable="false"])').length,
      drawn: doc.querySelectorAll('canvas').length,
      // Whether the page says which part of it is its content.
      marked: used !== whole,
    },
    things: says.things,
  };
  if (focus) result.focus = focus;
  return result;
})
