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
//   note       it holds words of the reader's own, in square brackets,
//              where something of the page could not be read: a film, a
//              frame from another site, a choice made in a menu.
//
// What a page shows that is not text is said, not passed over in silence:
// a film is a line with its length, a frame from another site a line with
// its name, a large picture with no description its address alone, and
// all of these are counted. A mark that points to a note at the foot of
// the page is written as Markdown's ([^4]), and the notes pointed to are
// read from wherever the page keeps them. What a carousel says again and
// again is said once.
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
  // Of those, the ones that take up room in a line of text.
  const spaced = new Set(['svg', 'canvas', 'video', 'audio', 'iframe', 'object', 'embed', 'select', 'button', 'input', 'textarea']);
  const skippedRoles = new Set(['navigation', 'banner', 'contentinfo', 'complementary', 'search', 'dialog',
    'alertdialog', 'menu', 'menubar', 'toolbar', 'tablist', 'tree', 'tooltip', 'progressbar']);
  // What runs on in a line. Everything else starts a line of its own: a
  // page's own elements (a site's components) most often hold blocks.
  const inline = new Set(['a', 'abbr', 'b', 'bdi', 'bdo', 'big', 'cite', 'code', 'data', 'del', 'dfn', 'em', 'font',
    'i', 'img', 'ins', 'kbd', 'label', 'mark', 'nobr', 'picture', 'q', 'rp', 'rt', 'ruby', 's', 'samp', 'slot',
    'small', 'source', 'span', 'strike', 'strong', 'sub', 'sup', 'time', 'tt', 'u', 'var', 'wbr', 'math',
    // A formula as MathJax 3 sets it, which runs on in its line.
    'mjx-container', 'mjx-assistive-mml']);
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
    // Not "discussion": a paper's section is called so, and is its writing.
    ['comments', ['comment', 'comments', 'disqus', 'replies', 'responses']],
    ['related', ['related', 'recommended', 'recommendations', 'popular', 'trending']],
    ['legal', ['legal', 'disclaimer', 'copyright']],
    ['footer', ['footer', 'colophon']],
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
  // A word before one of those that says the box has such a part in it, or has none ("has-toc",
  // "no-comments"), and one after that says how the part stands ("comments-open"): neither says what the box is.
  const having = new Set(['has', 'have', 'with', 'without', 'no', 'not', 'show', 'shows', 'hide', 'hides', 'is', 'allow', 'allows', 'enable', 'enables']);
  const standing = new Set(['enabled', 'disabled', 'open', 'opened', 'closed', 'active', 'inactive', 'visible', 'hidden', 'on', 'off', 'allowed']);
  // Words a page uses of its own content as often as of what is beside it ("popular dishes"): only with one that says of what.
  const weak = new Set(['popular', 'trending', 'recommended', 'recommendations']);
  const ofWhat = new Set(['post', 'posts', 'article', 'articles', 'story', 'stories', 'news', 'read', 'reads', 'video', 'videos',
    'product', 'products', 'item', 'items', 'link', 'links', 'search', 'searches', 'topic', 'topics', 'content', 'widget', 'sidebar', 'rail', 'module', 'now']);
  // What a page sets beside its content, by these names: not what a box that holds the page's own title is.
  const besides = new Set(['comments', 'related', 'legal', 'footer', 'newsletter', 'share', 'contents']);
  // The page's own title, where it has one.
  let headline = null;

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

  // Emphasis the walk is inside, by its mark: italics inside italics say nothing more.
  const marking = { '**': 0, '*': 0, '~~': 0 };
  // Elements the walk went into, which a note pointed to elsewhere is told from.
  let visited = new WeakSet();
  // What plays a film or a recording, by the element that holds all of it.
  let players = new Map();
  // Marks in the text that point to notes, by what each is called and where it points.
  let notes = [];
  // The block being put together has words of the reader's own in it.
  let noted = false;
  // The last block as it was said: what is said again right after, word for word and with a link, is said once.
  let lastSaid = '';
  // The last link written, and the block's text as it stood then.
  let lastLink = { made: '', upTo: '' };
  // How many characters have been said as the names of drawings (a mark, stars): a link that says nothing else is only named.
  let labelled = 0;
  // The last run of emphasis written, by its mark, and the text as it stood then: a mark at the text's end is that run's only then.
  let closed = { mark: '', upTo: '' };
  // Frames from other sites named so far, and large pictures with nothing said of them.
  let frames = 0;
  // Frames of the page's own site read as part of it, how deep in them the walk is, and where the
  // frame it is in stands in the window: what is inside one is measured from the frame's own corner.
  let framesRead = 0;
  let framed = 0;
  let shiftX = 0;
  let shiftY = 0;
  let unnamed = 0;
  let unnamedTall = 0;
  // The block being put together has a picture in it that nothing is said of: its address is not words.
  let drawn = false;
  // Films with words written under them, which are then no decoration.
  let captioned = new WeakSet();
  // The page has all but a sheet marked as hidden from assistive technology, and that mark is not gone by (hiddenAway).
  let covered = false;
  // Parts the page keeps folded away until a button is pressed, and the panels of its tabs by the
  // name of the tab each is under: read like a closed section, opened or not (survey).
  let folds = new WeakSet();
  let panels = new Map();
  // The buttons that open such parts, and the one of several things the walk is in that is the one chosen.
  let openers = new WeakSet();
  let ticked = null;
  // The element last found not to be drawn and read all the same (hiddenAway): what is in it is read whether it shows or not.
  let opened = null;
  // Inside a heading: a button there holds the heading's words.
  let titling = 0;
  // How much the menus say that the walk found parked off the page's edge and left out (scan).
  let parked = 0;
  // A button that only opens or closes what is under it says nothing of the page.
  const toggles = /^((show|read|see|view|load)\s+(more|less|all)\b.{0,20}|more|less|expand( all)?|collapse( all)?|close|open|toggle|더\s*보기|펼치기|접기|자세히(\s*보기)?|닫기|열기|もっと見る|閉じる)$/i;
  // Hosts that serve advertisements: a frame from one is not named, and a link to one is not the page's.
  const advertisers = /(^|\.)(doubleclick\.net|googlesyndication\.com|googleadservices\.com|adservice\.google\.[a-z.]+|adnxs\.com|taboola\.com|outbrain\.com|criteo\.(com|net)|amazon-adsystem\.com|buysellads\.com|ad(er|cr)\.naver\.com)$/i;
  // What is to be seen and is not words.
  const seen = 'img, picture, video, iframe, canvas';
  // A way past the menus for someone reading by ear, which leads nowhere in the file.
  const skips = /^(skip (to |the |over )?(main |page )?(content|navigation|nav|menu)|jump to (main )?content|(본문|메뉴|주메뉴|주 메뉴|콘텐츠|컨텐츠)\s*(으로|로)?\s*(바로\s*가기|건너뛰기)|本文へ(スキップ|移動))[\s.:!›»→]*$/i;

  // A frame's own page, where it is one of this site's, loaded from an
  // address: some sites are one frame and nothing else (a blog's post on
  // Naver), and such a frame is the page. Not one written into by script,
  // which is an advertiser's as often as not, nor one from anywhere else,
  // which the app has no way into.
  function pageIn(frame) {
    try {
      const address = new URL(frame.getAttribute('src') || '', frame.baseURI);
      if (!frame.getAttribute('src') || /^(about|javascript|data|blob):$/.test(address.protocol)) return null;
      if (address.protocol !== location.protocol || address.host !== location.host) return null;
      const inner = frame.contentDocument;
      return inner && inner.body && inner.readyState !== 'loading' ? inner : null;
    } catch (error) {
      return null;
    }
  }

  // The person's selection, if there is one, and a range to lay over each
  // block. In a frame of the page's own where the page itself has none:
  // what is selected on a page that is one frame is selected in the frame.
  let selection = typeof getSelection === 'function' ? getSelection() : null;
  if (!selection || !selection.rangeCount || selection.isCollapsed) {
    for (const frame of Array.from(doc.querySelectorAll('iframe')).slice(0, 12)) {
      const inner = pageIn(frame);
      const own = inner && inner.defaultView ? inner.defaultView.getSelection() : null;
      if (own && own.rangeCount && !own.isCollapsed) {
        selection = own;
        break;
      }
    }
  }
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
    return box.width > 0 && box.height > 0 && box.bottom + shiftY > 0 && box.right + shiftX > 0
      && box.top + shiftY < (window.innerHeight || 0) && box.left + shiftX < (window.innerWidth || 0);
  }

  // The block being put together is done with: what was kept of it goes.
  function clear() {
    started = null;
    plain = '';
    spoken = 0;
    noted = false;
    drawn = false;
    blockLinks = 0;
    blockLinked = 0;
    firstLink = '';
    firstText = null;
    lastText = null;
  }

  // A block that does not all fit under the limit, as far as it does: a table
  // to its last whole row, code to its last whole line with its fence closed,
  // anything else to a sentence's or a word's end, and never to the middle of
  // a formula. Cut anywhere, a row read as a short one and a formula as another.
  function shortened(made, room, kind) {
    let cut = made.slice(0, room);
    if (kind === 'table' || kind === 'code') {
      cut = cut.slice(0, Math.max(0, cut.lastIndexOf('\n')));
      const fence = kind === 'code' ? (/^\s*(`{3,})/.exec(made) || [])[1] : '';
      if (fence && cut.split('\n').length > 1 && cut.length + fence.length + 1 <= room) cut += '\n' + fence;
      return cut;
    }
    const open = cut.lastIndexOf('$');
    if (open >= 0 && cut.split('$').length % 2 === 0) cut = cut.slice(0, open);
    const stop = Math.max(cut.lastIndexOf('. '), cut.lastIndexOf('\n'));
    const word = cut.lastIndexOf(' ');
    if (stop > cut.length * 0.6) return cut.slice(0, stop + 1).replace(/\s+$/, '');
    return word > cut.length * 0.6 ? cut.slice(0, word) : cut;
  }

  // A block: its lines, each with what it begins with, and what is known of it.
  function emit(lines, kind, level, element) {
    const where = started || { at: element || at, hint: hints.length ? hints[hints.length - 1] : '', member: member };
    // Said again right after itself: a carousel's slides, each with the same
    // link. Only what has a link: the same line twice running with none is how
    // a page wrote it, a song's or a poem's, and is kept as written.
    const said = kind + '\n' + lines.join('\n');
    if (kind !== 'code' && kind !== 'table' && blockLinks && said === lastSaid) {
      clear();
      return;
    }
    lastSaid = said;
    // A quotation's own title, where the page marks it as one: told from what it is the title of.
    if (kind === 'quote' && lines.length === 1 && lines[0].length <= 120 && !lines[0].includes('**') && titled(where.at)) {
      lines = ['**' + lines[0] + '**'];
    }
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
      made = shortened(made, Math.max(0, most - size), kind);
      full = true;
    }
    const block = { kind: kind, text: made, characters: made.length, links: blockLinks, linked: blockLinked };
    if (level) block.level = level;
    if (noted) block.note = true;
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
    } else if (drawn) {
      block.plain = 0;
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
    if (!words || (repeats(plain) && outOfSight(started && started.at))) {
      clear();
      return;
    }
    // In a list item, an item. Down a quotation, a quote. Else a paragraph.
    const inner = prefixes.length ? prefixes[prefixes.length - 1] : null;
    const kind = inner ? (inner.listed ? 'item' : 'quote') : 'paragraph';
    // Paragraphs a page parts with empty lines alone (two line breaks) are each a block.
    const pieces = words.split(/\n{2,}/);
    for (const piece of pieces) {
      // A picture's address is long and is no writing, linked or not. A letter of Korean, Japanese
      // or Chinese says what two or three of English do, and counts as two.
      const weight = piece.length >= 200 || piece.length < 100 ? piece.length : piece.length + (piece.match(/[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7a3]/g) || []).length;
      if (weight >= 200 && !/^(?:\[?!\[[^\]]*\]\([^)]*\)(?:\]\([^)]*\))?\s*)+$/.test(piece)) {
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

  // Written for someone reading by ear and kept from the eye: a box of a
  // pixel, or one set off the page's edge.
  function outOfSight(node) {
    if (!node || !node.getBoundingClientRect) return false;
    const box = node.getBoundingClientRect();
    const view = (node.ownerDocument && node.ownerDocument.defaultView) || window;
    return box.width <= 2 || box.height <= 2 || box.right + (view.scrollX || 0) < 0 || box.bottom + (view.scrollY || 0) < 0;
  }

  // The same few words over and over with only a number changing: the marks
  // under a carousel ("1 of 9", "2 of 9"), which say nothing of the page.
  // Only where they are kept from the eye (flush): three models' names in a
  // row to be seen are the same shape, and are the page's.
  function repeats(words) {
    const tokens = words.replace(/\d+/g, '#').trim().split(/\s+/);
    for (let unit = 1; unit <= 4 && unit * 3 <= tokens.length; unit += 1) {
      if (tokens.length % unit) continue;
      let same = true;
      for (let index = unit; index < tokens.length && same; index += 1) same = tokens[index] === tokens[index % unit];
      const one = tokens.slice(0, unit).join(' ');
      if (same && one.includes('#') && /\p{L}/u.test(one)) return true;
    }
    return false;
  }

  // Whether an element's own class calls it a title: what a quotation's first line is, on some pages.
  function titled(node) {
    if (!node || !node.getAttribute) return false;
    return / (heading|headline|title) /.test(' ' + (node.getAttribute('class') || '').toLowerCase().replace(/[^a-z]+/g, ' ') + ' ');
  }

  // A line of the reader's own, in square brackets, where something of the page is not read.
  function note(words, element) {
    if (running) {
      say(' ' + words + ' ');
      return;
    }
    flush();
    const inner = prefixes.length ? prefixes[prefixes.length - 1] : null;
    noted = true;
    emit([words], inner ? (inner.listed ? 'item' : 'quote') : 'paragraph', 0, element);
  }

  // Seconds as a clock shows them: 1:30, 1:02:03.
  function clock(seconds) {
    const all = Math.round(seconds);
    const hours = Math.floor(all / 3600);
    const minutes = Math.floor((all % 3600) / 60);
    const rest = String(all % 60).padStart(2, '0');
    return hours ? hours + ':' + String(minutes).padStart(2, '0') + ':' + rest : minutes + ':' + rest;
  }

  // A film or a recording, as one line with its length: the film itself is not
  // text, and what its player draws over it (a bar, a clock, a caption that
  // is on screen this second) is not the page's. One that plays by itself
  // with no sound and no controls is the page's decoration, and is passed over.
  function played(node, media) {
    const sound = media.localName === 'audio';
    if (node === media) {
      if (!media.controls && !captioned.has(media) && (sound || (media.muted && (media.autoplay || media.loop)))) return;
      const box = media.getBoundingClientRect();
      if (!sound && (box.width < 120 || box.height < 60)) return;
    }
    let length = Number.isFinite(media.duration) && media.duration > 0 ? clock(media.duration) : '';
    if (!length && node !== media) {
      const shown = (node.innerText || '').match(/(?:\d{1,2}:)?\d{1,2}:\d{2}/g);
      if (shown) length = shown[shown.length - 1].replace(/^0(\d)/, '$1');
    }
    const called = (media.getAttribute('aria-label') || media.getAttribute('title') || '').replace(/\s+/g, ' ').trim().slice(0, 80);
    // Where it has been played to, which is where the person is in it.
    const at = Number.isFinite(media.currentTime) && media.currentTime >= 1 ? clock(media.currentTime) : '';
    note('[' + (sound ? 'Audio' : 'Video') + (called ? ': ' + called : '') + (length ? ', ' + length : '') + (at ? ', played to ' + at : '') + ']', node);
  }

  // What is chosen in a menu of the page's that has a name, which says what
  // the page is showing: the model a table compares with. The name is beside
  // it in the text where it is a label to see, and said here where it is
  // only told to assistive technology. A menu with no name is a form's.
  function choice(node) {
    const option = node.selectedOptions && node.selectedOptions[0];
    const words = option ? (option.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80) : '';
    const told = (node.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim().slice(0, 60);
    const labelled = (node.labels && node.labels.length) || node.hasAttribute('aria-labelledby');
    if (!words || (!told && !labelled)) return;
    say(' [chosen' + (told && !labelled ? ' for ' + told : '') + ': ' + words + '] ');
    noted = true;
  }

  // What plays each film or recording under `root`: the outermost thing
  // around it, within reach, that calls itself a player and says next to
  // nothing, else the film's own element. Found before the walk comes to
  // it, which then asks by element.
  function cast(root) {
    for (const media of Array.from(root.querySelectorAll('video, audio')).slice(0, 40)) {
      let holder = media;
      for (let above = media.parentElement, steps = 0; above && above !== root && steps < 6; above = above.parentElement, steps += 1) {
        const called = ((above.id || '') + ' ' + (above.getAttribute('class') || '') + ' ' + (above.getAttribute('aria-label') || '')).toLowerCase();
        if (/player|플레이어|video-js|plyr/.test(called) && (above.innerText || '').trim().length <= 200) holder = above;
      }
      if (!players.has(holder)) players.set(holder, media);
    }
    survey(root);
  }

  // What under `root` is kept from sight and is the page's all the same.
  // A part folded away until its button is pressed (the hours of a shop,
  // an answer under its question): the page says which button opens which
  // part, and a part that is mostly links is a menu and is not one of
  // these. And the panels of tabs, each by its tab's name: a tab named
  // with a number alone is a carousel's.
  function survey(root) {
    const page = root.ownerDocument || doc;
    for (const control of Array.from(root.querySelectorAll('[aria-expanded][aria-controls]')).slice(0, 200)) {
      if (control.hasAttribute('aria-haspopup')) continue;
      if (control.closest('nav, header, footer, [role="navigation"], [role="banner"], [role="menubar"], [role="menu"], [role="tablist"]')) continue;
      for (const id of (control.getAttribute('aria-controls') || '').split(/\s+/).slice(0, 4)) {
        const target = id ? page.getElementById(id) : null;
        if (!target || target.contains(control) || /^(nav|dialog|aside)$/.test(target.localName)) continue;
        if (/^(menu|menubar|dialog|alertdialog|listbox|tree|tooltip)$/.test(target.getAttribute('role') || '')) continue;
        const said = (target.textContent || '').replace(/\s+/g, ' ').trim().length;
        if (!said || said > 20000) continue;
        let linked = 0;
        for (const link of target.querySelectorAll('a[href]')) linked += (link.textContent || '').replace(/\s+/g, ' ').trim().length;
        if (linked * 10 > said * 6) continue;
        openers.add(control);
        if (control.getAttribute('aria-expanded') === 'false') folds.add(target);
      }
    }
    for (const panel of Array.from(root.querySelectorAll('[role="tabpanel"]')).slice(0, 40)) {
      const by = (panel.getAttribute('aria-labelledby') || '').split(/\s+/)[0];
      let tab = by ? page.getElementById(by) : null;
      if (!tab && panel.id) {
        tab = Array.from(root.querySelectorAll('[role="tab"][aria-controls]')).find((one) => one.getAttribute('aria-controls') === panel.id) || null;
      }
      const name = tab ? (tab.textContent || tab.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim() : '';
      if (name && name.length <= 40 && /\p{L}/u.test(name) && !/^\D{0,8}\d+(\D{1,5}\d+)?$/.test(name)) panels.set(panel, name);
    }
  }

  // A formula set by MathJax, which keeps it as it was typed in a script
  // beside what it draws: that, and not the drawing's letters one by one.
  function typeset(node) {
    const names = node.className;
    if (typeof names !== 'string' || !names.includes('MathJax') || names.includes('MathJax_Preview')) return false;
    const source = node.nextElementSibling;
    if (!source || source.localName !== 'script' || !/^math\/tex/i.test(source.type || '')) return false;
    const formula = (source.textContent || '').replace(/\s+/g, ' ').trim();
    if (!formula || hiddenAway(node)) return true;
    const mark = /mode=display/i.test(source.type) ? '$$' : '$';
    say(' ' + mark + formula + mark + ' ');
    return true;
  }

  // A frame. One of the page's own site is read as part of the page
  // (pageIn), two deep at the most and six in all. One from another site (a
  // board, a map, a film) is named and not read: the app has no way into
  // it. Small ones and advertisers' are passed over.
  function frame(node) {
    if (hiddenAway(node)) return;
    const box = node.getBoundingClientRect();
    if (box.width < 200 || box.height < 120) return;
    const inner = !running && framed < 2 && framesRead < 6 ? pageIn(node) : null;
    if (inner) {
      flush();
      const before = blocks.length;
      framesRead += 1;
      framed += 1;
      const wasX = shiftX;
      const wasY = shiftY;
      shiftX += box.left + node.clientLeft;
      shiftY += box.top + node.clientTop;
      // The part of it that it calls its content, where that holds anything.
      const part = start(inner);
      const from = (part.textContent || '').trim().length >= 200 ? part : inner.body;
      cast(from);
      enter(node, 'iframe', () => walk(from));
      flush();
      shiftX = wasX;
      shiftY = wasY;
      framed -= 1;
      // With nothing in it to read (a player, a drawing), it is named like any other.
      if (blocks.length > before || full) return;
      framesRead -= 1;
    }
    if (frames >= 12) return;
    let host = '';
    try {
      host = new URL(node.src, location.href).hostname;
    } catch (error) {
      host = '';
    }
    const called = (node.getAttribute('title') || '').replace(/\s+/g, ' ').trim().slice(0, 80);
    if (!called && (!host || host === location.hostname)) return;
    if (/\b(ads?|advert\w*|sponsor\w*)\b|광고/i.test(called) || advertisers.test(host)) return;
    frames += 1;
    // The page's own site's frame is as little read as another's, and is not said to be from elsewhere.
    const own = !host || host === location.hostname;
    note(own ? '[A frame, not read' + (called ? ': ' + called : '') + ']' : '[A frame from another site, not read: ' + [called, host].filter(Boolean).join(', ') + ']', node);
  }

  // A raised mark that points to a note: a link to a place on this page, or
  // what the page calls a footnote or a reference. Written as Markdown's, so
  // that "Max4" is not read as a word; where it points is kept for the notes.
  function footnote(node) {
    const label = (node.textContent || '').replace(/[\s\[\]()\u2060\u200b]/g, '');
    if (!label || label.length > 5) return '';
    // The link inside the mark, or one round it that holds nothing but the mark: "E = mc²" as a
    // link to a place on the page is a link, and its two is a two.
    let link = node.querySelector('a[href]');
    if (!link) {
      const around = node.closest('a[href]');
      if (around && (around.textContent || '').replace(/[\s\[\]()\u2060\u200b]/g, '') === label) link = around;
    }
    const given = link ? link.getAttribute('href') || '' : '';
    const names = ' ' + (node.getAttribute('class') || '').toLowerCase().replace(/[^a-z]+/g, ' ') + ' ';
    const called = / (footnote|footnotes|reference|fnref|noteref) /.test(names) || node.hasAttribute('data-footnote');
    // By where it points alone, only what has a mark's shape: a number, a letter or two, a sign,
    // "note 1". A raised "Top" that goes to the top of the page is not one.
    const shaped = /^(\d{1,4}|[a-z]{1,2}|[^\p{L}\p{N}]{1,2}|(?:n|nb|fn|note)\d{1,3})$/iu.test(label);
    const points = given.startsWith('#') && given.length > 1 && (shaped || called);
    if (!points && !called) return '';
    if (points && notes.length < 80 && !notes.some((one) => one.label === label)) {
      let id = given.slice(1);
      try {
        id = decodeURIComponent(id);
      } catch (error) {
        // As written, then.
      }
      notes.push({ label: label, id: id, within: node.ownerDocument || doc });
    }
    return '[^' + label + ']';
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
    tick(node);
    flush();
  }

  // The one chosen of several things is said to be, after its own words.
  function tick(node) {
    if (ticked !== node) return;
    ticked = null;
    say(' [chosen] ');
    noted = true;
  }

  // What a highlighter adds to code for the eye: the numbers down its side, a button to copy it.
  const gutters = /(^|[\s_-])(line-?numbers?|linenos?|lineno|gutter|blob-num|hljs-ln-numbers|copy|clipboard)([\s_-]|$)/i;

  // Code as it is laid out. A page that colours its code often writes no
  // line's end in it: each line is a box, or ends on a break, and read as
  // plain text the whole of it is one line. So line by line: a box or a
  // break ends one. Only the first levels are asked how they are laid out,
  // which is where lines are; the coloured words inside them are many.
  function typed(node) {
    let out = '';
    let asked = 0;
    const end = () => {
      if (out && !out.endsWith('\n')) out += '\n';
    };
    const go = (parent, depth) => {
      let boxedLast = false;
      for (const child of parent.childNodes) {
        if (out.length > most) return;
        if (child.nodeType === 3) {
          // A line's end written between two boxes is the same end twice.
          if (!(boxedLast && !child.data.trim())) out += child.data;
          continue;
        }
        if (child.nodeType !== 1) continue;
        const tag = child.localName;
        if (tag === 'br') {
          out += '\n';
          boxedLast = false;
          continue;
        }
        if (tag === 'button' || tag === 'script' || tag === 'style' || tag === 'svg' || tag === 'template' || tag === 'textarea'
          || child.hidden || child.getAttribute('aria-hidden') === 'true' || child.getAttribute('role') === 'button') continue;
        const names = child.getAttribute('class') || '';
        if (names && gutters.test(names)) continue;
        let boxed = tag === 'div' || tag === 'p' || tag === 'li' || tag === 'tr';
        if (!boxed && depth <= 3 && asked < 4000) {
          asked += 1;
          const display = getComputedStyle(child).display;
          if (display === 'none') continue;
          boxed = display === 'block' || display === 'flex' || display === 'grid' || display === 'list-item' || display === 'table-row';
        }
        if (boxed) end();
        const before = out.length;
        go(child, depth + 1);
        // A line with nothing on it is still a line.
        if (boxed && out.length === before && (boxedLast || /line|row/i.test(names))) out += '\n'; else if (boxed) end();
        boxedLast = boxed;
      }
    };
    go(node, 1);
    return out;
  }

  // What language code says it is in: by the names the page gives it or the boxes round it.
  function language(node) {
    const inner = node.querySelector('code');
    const above = node.parentElement;
    for (const one of [node, inner, above, above && above.parentElement, node.querySelector('[class*="language-"]')]) {
      if (!one || !one.getAttribute) continue;
      // By an attribute only on the code itself: on a box round it, "lang" is as often the language the page is in.
      const own = one === node || one === inner ? one.getAttribute('data-lang') || one.getAttribute('data-language') : '';
      const said = own
        || (/(?:^|\s)(?:lang(?:uage)?-|highlight-source-|brush:\s*)([\w+#.-]+)/.exec(one.getAttribute('class') || '') || [])[1] || '';
      const name = said.trim().toLowerCase();
      if (/^[\w+#.-]{1,20}$/.test(name) && !/^(none|plain|plaintext|text|txt|nohighlight)$/.test(name)) return name;
    }
    return '';
  }

  function fenced(node) {
    flush();
    let code = typed(node).replace(/^\n+/, '').replace(/\s+$/, '');
    // All of it kept from assistive technology, or in a field: as it is written, then.
    if (!code.trim()) code = (node.textContent || '').replace(/^\n+/, '').replace(/\s+$/, '');
    if (!code.trim()) return;
    const room = most - size;
    if (code.length > room) code = code.slice(0, Math.max(0, room));
    // Longer than any run of the mark the code has in it, or the code's own would end it.
    const fence = '`'.repeat(Math.max(3, ...(code.match(/`{3,}/g) || []).slice(0, 200).map((one) => one.length + 1)));
    emit([fence + language(node)].concat(code.split('\n'), [fence]), 'code', 0, node);
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
      // A row that is not shown (filtered out, a copy kept for sorting) is not the table's as it stands.
      if (!unseen && (row.hidden || !shows(row))) continue;
      const cells = Array.from(row.cells).map((cell) => run(cell).replace(/\|/g, '\\|'));
      if (!cells.length || cells.every((one) => !one)) continue;
      lines.push('| ' + cells.join(' | ') + ' |');
      // Under the first row that has cells, which is not always the table's first.
      if (lines.length === 1) lines.push('|' + cells.map(() => ' --- |').join(''));
      length += lines[lines.length - 1].length + 1;
      if (size + length > most) full = true;
    }
    if (lines.length) emit(lines, 'table', 0, node);
  }

  function marked(node, mark) {
    // Italics inside italics are italics: marked once, by the outer of the two.
    if (marking[mark] || node.querySelector(blocky)) return each(node);
    marking[mark] += 1;
    const words = run(node);
    marking[mark] -= 1;
    if (!words) return;
    // The marks stand against the words, and a space the page had inside them stands outside.
    const inside = node.textContent || '';
    if (/^\s/.test(inside)) say(' ');
    if (closed.mark === mark && closed.upTo === text && text.endsWith(mark)) {
      // Two runs of it with nothing between them are one run: "**a****b**" is read as neither.
      text = text.slice(0, -mark.length);
      say(words + mark, ran);
    } else {
      say(mark + words + mark, ran);
    }
    closed = { mark: mark, upTo: text };
    if (/\s$/.test(inside)) say(' ');
  }

  function link(node) {
    const address = node.href;
    const given = node.getAttribute('href') || '';
    // A way past the menus, or down the page to a part of it ("Jump to recipe"), leads nowhere in the file.
    const says = (node.textContent || '').trim();
    if (given.startsWith('#') && (skips.test(says) || /^(skip|jump) to( the)? [\p{L}'-]+( [\p{L}'-]+)?[\s.:!›»→↓]*$/iu.test(says))) return;
    if (!address || given.startsWith('#') || !/^https?:/i.test(address)) return each(node);
    // A link to a film's or a recording's own file says what it is, and its address would say nothing more.
    const file = address.split(/[?#]/)[0];
    const stream = /\.(m3u8|mpd|mp4|m4v|mov|webm)$/i.test(file) ? 'video' : /\.(mp3|m4a|aac|oga|ogg|wav|flac)$/i.test(file) ? 'audio' : '';
    if (stream) {
      const label = run(node);
      if (label) {
        say(label + ' [' + stream + ']', ran);
        noted = true;
      }
      return;
    }
    // An advertiser's link is not the page's, whatever it says.
    if (advertisers.test(node.hostname || '')) return;
    const drawn = labelled;
    let words = run(node);
    // Only named: by its own name, or by that of the mark it holds (a customer's mark in a row of them).
    let named = labelled > drawn && labelled - drawn >= ran.length;
    if (!ran) {
      // A link with nothing to read in it (a mark, a picture that says nothing, a card's whole face) by the name it is given.
      const label = (node.getAttribute('aria-label') || node.getAttribute('title') || '').replace(/\s+/g, ' ').trim();
      if (label && label.length <= 120) {
        words = label.replace(/[\[\]]/g, '');
        ran = words;
        named = true;
      }
    }
    if (!words) return;
    // A wiki's "edit" beside each heading is its tool, and not what the page says.
    if (/[?&]action=edit\b/.test(address) && words.length <= 12) return;
    // The same link again right after itself says nothing more: a carousel's slides, written in a row.
    const made = '[' + words + '](' + readable(address) + ')';
    if (made === lastLink.made && text.replace(/\s+$/, '') === lastLink.upTo) return;
    // For the page, as Markdown, which is what the kinds were measured by, and without the links
    // that are only named: a row of customers' marks is not a page's links as a menu's are. For
    // the block, its words: a picture's address inside a link is not what the link says.
    if (!named) {
      links += 1;
      linked += words.length;
    }
    blockLinks += 1;
    blockLinked += ran.length;
    if (!firstLink) firstLink = readable(address);
    say(made, ran);
    lastLink = { made: made, upTo: text.replace(/\s+$/, '') };
  }

  // An address with the letters of its own language as letters. Written byte
  // by byte, a word of Korean is nine characters a letter, and a page of
  // links is mostly that. Only what is a letter: a space or a mark that
  // Markdown reads stays as it was.
  function readable(address) {
    if (!address.includes('%')) return address;
    return address.replace(/(?:%[89A-Fa-f][0-9A-Fa-f])+/g, (bytes) => {
      try {
        const letters = decodeURIComponent(bytes);
        return /[^\p{L}\p{N}\p{M}]/u.test(letters) ? bytes : letters;
      } catch (error) {
        return bytes;
      }
    });
  }

  function picture(node) {
    const says = (node.getAttribute('alt') || '').replace(/\s+/g, ' ').trim();
    let address = node.currentSrc || node.src || '';
    // A picture not yet loaded stands as an empty one, with its own address kept beside it.
    if (!/^https?:/i.test(address) || /(?:blank|spacer|placeholder|loading|transparent|1x1|pixel|lazy)[\w.-]*\.(?:gif|png|svg|jpe?g|webp)(?:[?#]|$)/i.test(address)) {
      for (const name of ['data-src', 'data-lazy-src', 'data-original', 'data-lazy', 'data-url']) {
        const kept = node.getAttribute(name);
        if (!kept) continue;
        try {
          const real = new URL(kept, node.baseURI).href;
          if (/^https?:/i.test(real)) {
            address = real;
            break;
          }
        } catch (error) {
          // Not an address: the next.
        }
      }
    }
    address = readable(address);
    if (!says) {
      // A thing to see between two words stood between them.
      if (text && !/\s$/.test(text)) say(' ');
      // Said to say nothing, inside a link: the small picture beside a title that the link is of.
      if (node.hasAttribute('alt') && node.closest('a[href]')) return;
      // A large picture with nothing said of it is still part of the page: counted,
      // and shown by its address. A small one is an ornament.
      const box = node.getBoundingClientRect();
      if (box.width < 200 || box.height < 150) return;
      unnamed += 1;
      unnamedTall += box.height;
      if (/^https?:/i.test(address)) {
        say('![](' + address + ')', '');
        drawn = true;
      }
      return;
    }
    // Never a picture written into the page as data: megabytes that say nothing.
    say(/^https?:/i.test(address) ? '![' + says + '](' + address + ')' : says, says);
  }

  // A site's top and foot, which a page's own sections also have: only the site's are left out.
  function isSites(node) {
    return !node.closest('article, main, section, [role="main"]');
  }

  // Kept from sight until it is looked for: a section a phone's page folds away
  // under its heading (Wikipedia's are all so), a part under a button that
  // opens it, a tab's panel. The page's own word that the text is there to be
  // found, and read as a closed section is.
  function folded(node) {
    if (node.getAttribute('hidden') === 'until-found') return true;
    return (folds.has(node) || panels.has(node)) && !shows(node);
  }

  // Not to be seen. What is only kept from assistive technology is not
  // seen either, as a rule: an ornament, a label said twice. Not so when a
  // page has put a sheet over itself and marked all the rest as hidden,
  // which is read for what it is, since it is all there is (`covered`).
  function hiddenAway(node) {
    const kept = folded(node);
    if (node.hidden && !kept) return true;
    // What is kept from assistive technology is not read, as a rule; a part folded away is kept from it too while it is shut.
    if (node.getAttribute('aria-hidden') === 'true' && !covered && !kept) return true;
    if (kept) {
      opened = node;
      return false;
    }
    if (unseen) {
      // Inside a part that is read though it is not drawn, nothing is drawn, and what would still
      // not show with the part open is told by its own style: a box set not to be displayed is a
      // menu or a sheet waiting in it (every language a translator knows, in a tab not open).
      // Only boxes are asked: what runs on in a line is kept from sight for other ends (a formula
      // as it is read aloud), and asking every word of a long part costs more than it tells.
      if (inline.has(node.localName) || getComputedStyle(node).display !== 'none') return false;
    } else if (shows(node)) {
      return false;
    }
    if (!tucked(node)) return true;
    opened = node;
    return false;
  }

  // Not drawn, right under a heading, and called by the page what folds
  // away: a section a phone's page keeps shut under its heading until the
  // heading is pressed (an encyclopedia's are all so on a phone, and the
  // page read there was its first paragraph and its notes). The heading,
  // or the small box it is in, comes right before; the name is the page's
  // own or the button's word that it opens something.
  function tucked(node) {
    const before = node.previousElementSibling;
    if (!before) return false;
    const heads = /^h[1-6]$/.test(before.localName) || before.getAttribute('role') === 'heading'
      || (before.children.length <= 4 && !!before.querySelector('h1, h2, h3, h4, h5, h6, [role="heading"], summary'));
    if (!heads) return false;
    const names = (node.getAttribute('class') || '') + ' ' + (before.getAttribute('class') || '');
    if (!/collaps|accordion|expand|toggl|fold/i.test(names) && !before.hasAttribute('aria-expanded') && !before.querySelector('[aria-expanded]')) return false;
    return inWords(node);
  }

  // Whether an element has words in it at all, without reading them all.
  function inWords(node) {
    const walker = (node.ownerDocument || doc).createTreeWalker(node, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      if (walker.currentNode.data.trim()) return true;
    }
    return false;
  }

  // A button the page's own words are in: one inside a heading, and one that
  // opens a part of the page (an accordion's question, which the page says
  // opens the answer: survey), where it says more than "show more".
  function told(node) {
    if (titling) return true;
    if (!openers.has(node)) return false;
    const words = (node.textContent || '').replace(/\s+/g, ' ').trim();
    return words.length >= 2 && words.length <= 300 && !toggles.test(words);
  }

  // A button that is the one chosen of several, by what the page tells
  // assistive technology: the colour or the size picked on a shop's page.
  function picked(node) {
    const role = node.getAttribute('role') || '';
    if (role === 'radio' || role === 'option') return node.getAttribute('aria-checked') === 'true' || node.getAttribute('aria-selected') === 'true';
    return node.getAttribute('aria-pressed') === 'true' && !!node.closest('[role="group"], [role="radiogroup"], [role="listbox"], fieldset');
  }

  // Not the page's content, or not to be seen. What a page calls its banner
  // or its foot by role is the site's only where a header or a footer would
  // be: inside the page's own part it is the page's (a recipe's title, its
  // author and its times).
  function leftOut(node, tag) {
    if (skipped.has(tag)) return !(tag === 'button' && told(node));
    const role = node.getAttribute('role') || '';
    if (skippedRoles.has(role) && (isSites(node) || (role !== 'banner' && role !== 'contentinfo'))) return true;
    if ((tag === 'header' || tag === 'footer') && isSites(node)) return true;
    return hiddenAway(node);
  }

  // What a name's words say the part is: the first of them that says anything.
  function hintIn(name) {
    if (!name) return '';
    const known = named.get(name);
    if (known !== undefined) return known;
    let hint = '';
    if (name.toLowerCase().replace(/[^a-z]/g, '').includes('tableofcontents')) hint = 'contents';
    if (!hint) {
      const words = name.replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase().split(/[^a-z0-9]+/);
      for (let index = 0; index < words.length && !hint; index += 1) {
        const found = hintOf.get(words[index]);
        if (!found || having.has(words[index - 1]) || standing.has(words[index + 1])) continue;
        if (weak.has(words[index]) && !words.some((one) => ofWhat.has(one))) continue;
        hint = found;
      }
    }
    if (named.size < 5000) named.set(name, hint);
    return hint;
  }

  // What a container calls itself: by its own name and what it tells
  // assistive technology first, by its id and class after. Not the page's
  // outermost boxes: what they are called is said of the whole page. Nor a
  // heading, whose name is of the section under it ("related-work"), nor a
  // box with the page's own title in it, which is the page and no part
  // set beside it, whatever a class on it says.
  function hintFor(node, tag) {
    if (node === from || tag === 'body' || tag === 'html' || tag === 'main' || tag === 'article' || /^h[1-6]$/.test(tag)) return '';
    if (node.getAttribute('role') === 'heading') return '';
    const label = node.getAttribute('aria-label') || '';
    const told = (tag.includes('-') ? tag + ' ' : '') + (label.length <= 60 ? label + ' ' : '') + (node.getAttribute('role') || '');
    const hint = hintIn(told.trim()) || hintIn(((node.id || '') + ' ' + (node.getAttribute('class') || '')).trim());
    if (hint && besides.has(hint) && headline && node !== headline && node.contains(headline)) return '';
    return hint;
  }

  // Marks a parent's children as repeated siblings where they are: five or
  // more with a link, most of the children, each a small thing. Search
  // results, cards and replies are; the sections of a page are not. Says
  // true where the run is not to be read at all.
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
    // A run of links that stands whole off the page's left or top edge is a menu waiting to be
    // opened, drawn where it cannot be seen: the site's, and left out like its other menus.
    if (!unseen) {
      const box = parent.getBoundingClientRect();
      const view = (parent.ownerDocument && parent.ownerDocument.defaultView) || window;
      if (box.width >= 50 && box.height >= 50 && (box.right + (view.scrollX || 0) <= 0 || box.bottom + (view.scrollY || 0) <= 0)) {
        parked += (parent.textContent || '').replace(/\s+/g, ' ').trim().length;
        return true;
      }
    }
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
    visited.add(node);
    const container = !inline.has(tag);
    const hint = container ? hintFor(node, tag) : '';
    if (hint) hints.push(hint);
    let away = false;
    if (!member) {
      member = members.get(node) || null;
      // Only the outermost: a result's own row of links is part of the result.
      if (!member && container) away = scan(node) === true;
    }
    if (!away) body();
    if (hint) hints.pop();
    member = wasMember;
    at = wasAt;
  }

  function walk(node) {
    if (full) return;
    if (node.nodeType === 3) {
      // Without what is written to be invisible (a joiner before a footnote's mark, a soft hyphen), and without
      // the letters a font of pictures draws its marks with, which are no letters anywhere else.
      const data = node.data.replace(/[\u2060\u200b\ufeff\u00ad\ue000-\uf8ff]/g, '');
      if (data.trim()) {
        if (!firstText) firstText = node;
        lastText = node;
      }
      say(data.replace(/\s+/g, ' '));
      return;
    }
    if (node.nodeType !== 1) return;
    const tag = node.localName;
    // What is not text and is still said of: a film, a menu's choice, a frame from another site.
    const media = players.get(node);
    if (media) {
      if (!hiddenAway(node)) played(node, media);
      return;
    }
    if (tag === 'select') {
      if (!hiddenAway(node)) choice(node);
      return;
    }
    if (tag === 'iframe') return frame(node);
    // The one chosen of several buttons, by its name: what the page is showing (a colour, a size).
    if (tag === 'button' && picked(node)) {
      const name = (node.textContent || '').replace(/\s+/g, ' ').trim() || (node.getAttribute('aria-label') || node.getAttribute('title') || '').replace(/\s+/g, ' ').trim();
      if (name && name.length <= 80 && !hiddenAway(node)) {
        say(' ' + name + ' [chosen] ');
        noted = true;
      }
      return;
    }
    // A drawing with a name and no words in it (a mark for "yes" in a table's cell, stars for a rating): its name.
    if (tag === 'svg' || (tag !== 'img' && node.getAttribute('role') === 'img')) {
      const label = (node.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim();
      if (label && label.length <= 160 && (tag === 'svg' || !(node.textContent || '').trim())) {
        if (!hiddenAway(node)) {
          say(' ' + label + ' ');
          labelled += label.length;
        }
        return;
      }
    }
    if ((tag === 'span' || tag === 'div') && typeset(node)) return;
    if (leftOut(node, tag)) {
      // A thing to see or to press between two words stood between them: they are two words.
      if (spaced.has(tag) && text && !/\s$/.test(text) && node.type !== 'hidden') say(' ');
      return;
    }
    // A tab's panel is under its tab's name, open or not.
    const tab = panels.get(node);
    if (tab && !running && (node.textContent || '').trim()) note('[Tab: ' + tab + (shows(node) ? '' : ', not open') + ']', node);
    // In a run of words a block is only its words, set apart by a space: a
    // heading inside a link, a list inside a table's cell.
    if (running && !inline.has(tag) && tag !== 'br') {
      visited.add(node);
      say(' ');
      each(node);
      say(' ');
      return;
    }
    // A span that is a box of its own is not next to its neighbours' words,
    // though no space is written between them: a label and its value at
    // the two ends of a row.
    let apart = false;
    if (inline.has(tag) && tag !== 'br' && tag !== 'wbr') {
      const style = getComputedStyle(node);
      apart = boxes.has(style.display);
      // Next to the thing before it with no space written and a gap to see: two things, as the eye has them.
      const before = node.previousSibling;
      if (!apart && before && before.nodeType === 1 && text && !/\s$/.test(text)) {
        let gap = (parseFloat(style.marginLeft) || 0) + (parseFloat(style.paddingLeft) || 0);
        if (gap < 4 && inline.has(before.localName)) {
          const other = getComputedStyle(before);
          gap += (parseFloat(other.marginRight) || 0) + (parseFloat(other.paddingRight) || 0);
        }
        if (gap >= 4) say(' ');
      }
    }
    if (apart) say(' ');
    const kept = opened === node;
    opened = null;
    if (kept) unseen += 1;
    if (tag !== 'button' && node.hasAttribute('role') && picked(node)) ticked = node;
    enter(node, tag, () => element(node, tag));
    tick(node);
    if (kept) unseen -= 1;
    if (apart) say(' ');
  }

  function element(node, tag) {
    // A heading by what the page tells assistive technology, whatever element it is.
    if (node.getAttribute('role') === 'heading' && !/^h[1-6]$/.test(tag)) {
      tag = 'h' + Math.min(6, Math.max(1, Number(node.getAttribute('aria-level')) || 2));
    }
    switch (tag) {
      case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6': {
        flush();
        titling += 1;
        const words = run(node);
        titling -= 1;
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
          const shut = opened === item;
          opened = null;
          const mark = number ? number + '. ' : '- ';
          if (number) number += 1;
          prefixes.push({ first: mark, rest: ' '.repeat(mark.length), used: false, listed: true });
          if (item.hasAttribute('role') && picked(item)) ticked = item;
          if (shut) unseen += 1;
          enter(item, 'li', () => block(item));
          if (shut) unseen -= 1;
          prefixes.pop();
        }
        return;
      }
      case 'blockquote': {
        flush();
        const first = blocks.length;
        prefixes.push({ first: '> ', rest: '> ', used: false, listed: false });
        each(node);
        flush();
        prefixes.pop();
        gather(first);
        return;
      }
      case 'sup': {
        const mark = footnote(node);
        if (mark) say(mark, ''); else each(node);
        return;
      }
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
        const raw = node.textContent || '';
            // Code set as a box of its own, keeping its spaces, is a block of code, in a `pre` or not.
        // Of several lines, or the only thing in its box: only then is it asked how it is laid out.
        const alone = () => !Array.from(node.parentNode ? node.parentNode.childNodes : []).some((one) => one !== node && one.nodeType === 3 && one.data.trim());
        if (tag === 'code' && !running && raw.trim() && (raw.includes('\n') || node.querySelector('br, div') || alone())) {
          const style = getComputedStyle(node);
          if (boxes.has(style.display) && /^pre/.test(style.whiteSpace)) return fenced(node);
        }
        const words = raw.replace(/\s+/g, ' ').trim();
        // Code with the mark in it is written between two of them.
        if (words) say(words.includes('`') ? '`` ' + words + ' ``' : '`' + words + '`', words);
        return;
      }
      case 'q':
        say('"');
        each(node);
        say('"');
        return;
      case 'math': {
        // As it is written out, where the page says how: in the formula's own name (Wikipedia), or beside it as it was typed (KaTeX).
        const typed = node.querySelector('annotation[encoding="application/x-tex"]');
        let formula = (node.getAttribute('alttext') || (typed ? typed.textContent || '' : '')).replace(/\s+/g, ' ').trim();
        // Without what only says how large to set it, where that is wrapped round the whole of it (Wikipedia's are all so).
        const set = /^\{\\(?:displaystyle|textstyle)\s+(.*)\}$/.exec(formula);
        if (set) {
          let depth = 0;
          let whole = true;
          for (const letter of set[1]) {
            depth += letter === '{' ? 1 : letter === '}' ? -1 : 0;
            if (depth < 0) whole = false;
          }
          if (whole && depth === 0) formula = set[1].trim();
        }
        say(formula ? '$' + formula + '$' : (node.textContent || '').replace(/\s+/g, ' '));
        return;
      }
      case 'label': {
        // What is ticked or picked in a form of the page's says what the page is showing.
        each(node);
        const control = node.control;
        if (control && (control.type === 'radio' || control.type === 'checkbox') && control.checked) {
          say(' [chosen] ');
          noted = true;
        }
        return;
      }
      default:
        if (inline.has(tag)) each(node); else if (!figure(node)) block(node);
    }
  }

  // Whether an element has `most` elements inside it or fewer, without counting past that.
  function within(node, most) {
    const walker = doc.createTreeWalker(node, NodeFilter.SHOW_ELEMENT);
    let count = 0;
    while (walker.nextNode()) {
      count += 1;
      if (count > most) return false;
    }
    return true;
  }

  // A thing to be seen with what the page writes under it, as one block: the
  // words are of the thing over them, and say little apart from it ("Before",
  // "After"). Told from a box of two, the first with nothing written in it,
  // which is how a figure and its caption are built whatever the page calls
  // them. A heading or a list under a picture is a card's, and stays its own.
  function figure(node) {
    const kids = node.children;
    if (kids.length !== 2 || node.shadowRoot) return false;
    const shown = kids[0];
    const under = kids[1];
    // Small things both: asked first, and counted no further than it takes to say no, so that a page's
    // two halves are not gone through at every box of two around them.
    if (!within(under, 12) || !within(shown, 40)) return false;
    const words = (under.textContent || '').trim();
    if (!words || words.length > 200 || /^(h[1-6]|ul|ol|table|pre|blockquote|figure)$/.test(under.localName)) return false;
    if (under.matches(seen) || under.querySelector(seen + ', h1, h2, h3, h4, h5, h6, ul, ol, table, pre, blockquote')) return false;
    if (!shown.matches(seen) && !shown.querySelector(seen)) return false;
    // Nothing to read in it: what a film or a frame holds for a browser that cannot show it is not read.
    const held = shown.textContent || '';
    if (held.length > 400 || (held.trim() && (shown.innerText || '').trim())) return false;
    for (const child of node.childNodes) {
      if (child.nodeType === 3 && child.data.trim()) return false;
    }
    flush();
    const film = shown.matches('video') ? shown : shown.querySelector('video');
    if (film) captioned.add(film);
    const first = blocks.length;
    walk(shown);
    flush();
    const middle = blocks.length;
    walk(under);
    flush();
    if (full || middle !== first + 1 || blocks.length !== first + 2) return true;
    const above = blocks[first];
    const below = blocks[first + 1];
    if (above.kind !== below.kind || above.kind === 'heading') return true;
    above.plain = (above.plain === undefined ? above.characters : above.plain) + (below.plain === undefined ? below.characters : below.plain);
    above.text += '\n' + below.text;
    above.characters = above.text.length;
    above.links += below.links;
    above.linked += below.linked;
    if (below.onScreen) above.onScreen = true;
    if (below.selected) above.selected = true;
    if (below.note) above.note = true;
    if (!above.link && below.link) above.link = below.link;
    blocks.length = first + 1;
    // One line's end between them where two blocks have two.
    size -= 1;
    lastSaid = '';
    return true;
  }

  // A quotation of several paragraphs is one quotation, its paragraphs parted
  // by a quoted empty line: not as many quotations as it has paragraphs, which
  // is how a title and what it is the title of came apart.
  function gather(first) {
    const parts = blocks.slice(first);
    if (parts.length < 2 || parts.length > 12 || full) return;
    if (parts.some((one) => one.kind !== 'quote' || one.note)) return;
    const head = parts[0];
    const gap = ((/^(\s*(?:>\s?)+)/.exec(parts[1].text) || [])[1] || '> ').replace(/\s+$/, '');
    let plainly = 0;
    for (const one of parts) {
      size -= one.text.length + 2;
      plainly += one.plain === undefined ? one.characters : one.plain;
    }
    head.text = parts.map((one) => one.text).join('\n' + gap + '\n');
    head.characters = head.text.length;
    head.plain = plainly;
    head.links = parts.reduce((sum, one) => sum + one.links, 0);
    head.linked = parts.reduce((sum, one) => sum + one.linked, 0);
    if (parts.some((one) => one.onScreen)) head.onScreen = true;
    if (parts.some((one) => one.selected)) head.selected = true;
    if (!head.link) {
      const linked = parts.find((one) => one.link);
      if (linked) head.link = linked.link;
    }
    if (head.start === undefined) head.start = parts.map((one) => (one.start === undefined ? one.text.replace(/^(?:\s*>\s?)+/, '') : one.start)).join(' ').slice(0, 220);
    blocks.length = first + 1;
    size += head.text.length + 2;
    lastSaid = '';
  }

  // The part of the page that is its content, where the page says which:
  // its one main part, or its one article. Otherwise all of it.
  function start(page) {
    // Where one main part holds the others, it is the page's.
    const mains = Array.from(page.querySelectorAll('main, [role="main"]')).filter((one) => !one.parentElement || !one.parentElement.closest('main, [role="main"]'));
    if (mains.length === 1) return mains[0];
    const articles = page.querySelectorAll('article');
    if (articles.length === 1) return articles[0];
    return page.body || page.documentElement;
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
    headline = root.querySelector('h1');
    visited = new WeakSet();
    notes = [];
    captioned = new WeakSet();
    lastLink = { made: '', upTo: '' };
    closed = { mark: '', upTo: '' };
    labelled = 0;
    lastSaid = '';
    unseen = 0;
    frames = 0;
    framesRead = 0;
    framed = 0;
    shiftX = 0;
    shiftY = 0;
    unnamed = 0;
    unnamedTall = 0;
    marking['**'] = 0;
    marking['*'] = 0;
    marking['~~'] = 0;
    clear();
    players = new Map();
    folds = new WeakSet();
    panels = new Map();
    openers = new WeakSet();
    ticked = null;
    opened = null;
    titling = 0;
    parked = 0;
    cast(root);
    walk(root);
    flush();
  }

  // What the page's head says of it, in the page's own words.
  function meta(names, length) {
    for (const name of names) {
      const found = doc.querySelector('meta[property="' + name + '"], meta[name="' + name + '"]');
      const content = found ? (found.getAttribute('content') || '').replace(/\s+/g, ' ').trim() : '';
      if (content) return content.slice(0, length || 300);
    }
    return '';
  }

  // A value the page declares, as a short line of words.
  function word(value, length) {
    if (typeof value === 'number') return String(value);
    return typeof value === 'string' ? value.replace(/\s+/g, ' ').trim().slice(0, length) : '';
  }

  // The things a page declares, by the name each is given (@id): a thing is
  // often declared in one place and pointed to from another, its author above all.
  let ids = new Map();

  // Who, of a person or an organisation declared as one, as a list of them, or by pointing to one.
  function who(value) {
    const one = Array.isArray(value) ? value[0] : value;
    if (!one || typeof one !== 'object') return word(one, 80);
    return word(one.name || (ids.get(one['@id']) || {}).name, 80);
  }

  // What a declared thing says of itself that a reader would ask: the few
  // properties that name it, date it, place it, price it and rate it.
  function said(thing) {
    const facts = {};
    const set = (key, value) => {
      if (value) facts[key] = value;
    };
    const one = (value) => (Array.isArray(value) ? value[0] : value);
    // A job's name is its title: what a posting calls its name is as often the employer's.
    const job = [].concat(thing['@type'] || []).some((type) => String(type).toLowerCase() === 'jobposting');
    set('name', word(thing.headline || (job ? thing.title || thing.name : thing.name || thing.title), 150));
    set('author', who(thing.author));
    set('publisher', who(thing.publisher));
    set('published', word(thing.datePublished || thing.uploadDate || thing.dateCreated || thing.datePosted, 40));
    set('modified', word(thing.dateModified, 40));
    set('duration', word(thing.duration, 20));
    // An event's day and place, a recipe's times and what it makes, a book's number, a job's terms, a shop's street.
    set('starts', word(thing.startDate, 40));
    set('ends', word(thing.endDate, 40));
    const place = one(thing.location || thing.jobLocation);
    if (place && typeof place === 'object') {
      const address = place.address && typeof place.address === 'object' ? word(place.address.addressLocality, 60) : word(place.address, 100);
      set('place', [word(place.name, 80), address].filter(Boolean).join(', '));
    } else {
      set('place', word(place, 100));
    }
    if (thing.address && typeof thing.address === 'object') {
      set('address', [word(thing.address.streetAddress, 80), word(thing.address.addressLocality, 60)].filter(Boolean).join(', '));
    } else {
      set('address', word(thing.address, 100));
    }
    set('phone', word(thing.telephone, 30));
    set('priceRange', word(thing.priceRange, 20));
    set('prep', word(thing.prepTime, 20));
    set('cook', word(thing.cookTime, 20));
    set('total', word(thing.totalTime, 20));
    set('yield', word(one(thing.recipeYield), 40));
    if (thing.nutrition && typeof thing.nutrition === 'object') set('calories', word(thing.nutrition.calories, 30));
    set('brand', who(thing.brand));
    set('isbn', word(thing.isbn, 20));
    set('pages', word(thing.numberOfPages, 8));
    set('employer', who(thing.hiringOrganization));
    set('employment', word(one(thing.employmentType), 30).replace(/_/g, ' ').toLowerCase());
    set('closes', word(thing.validThrough, 40));
    const pay = thing.baseSalary && typeof thing.baseSalary === 'object' ? thing.baseSalary : null;
    if (pay && pay.value !== undefined && pay.value !== null) {
      // A board with no figure to give declares nought ("0 KRW a year"), which would read as no pay at all.
      const figure = (value) => (/^\s*0+(\.0+)?\s*$/.test(String(value)) ? '' : word(value, 12));
      // A figure given as it is, or a range with what time it is for.
      const value = typeof pay.value === 'object' ? pay.value : { value: pay.value };
      const low = figure(value.minValue !== undefined ? value.minValue : value.value);
      const high = figure(value.maxValue);
      const amount = low && high && low !== high ? low + ' to ' + high : low || high;
      const unit = word(value.unitText, 10).toLowerCase();
      const per = unit === 'hour' ? 'an hour' : unit ? 'a ' + unit : '';
      if (amount) set('salary', [amount, word(pay.currency, 8), per].filter(Boolean).join(' '));
    }
    const rating = thing.aggregateRating;
    if (rating && typeof rating === 'object') {
      set('rating', word(rating.ratingValue, 10));
      set('ratings', word(rating.reviewCount || rating.ratingCount, 12));
    }
    // A price with its own currency, from the same offer. Several offers
    // in one currency give the range they span; in more than one, nothing.
    const prices = [];
    const currencies = new Set();
    const stock = new Set();
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
      // Whether it can be had: "InStock", as the web names it, in words.
      const had = word(offer.availability, 80).split('/').pop().replace(/([a-z])([A-Z])/g, '$1 $2').toLowerCase();
      if (/^[a-z ]{3,30}$/.test(had)) stock.add(had);
    }
    if (prices.length && currencies.size === 1) {
      const low = Math.min(...prices);
      const high = Math.max(...prices);
      set('price', (low === high ? String(low) : low + ' to ' + high) + ' ' + Array.from(currencies)[0]);
    }
    if (stock.size === 1) set('availability', Array.from(stock)[0]);
    return facts;
  }

  // What the page declares itself and its things to be, to search engines
  // (schema.org's names): the kinds, and each thing with what it says of
  // itself. A thing is the page's own where the page says so (mainEntity,
  // mainEntityOfPage); which of the others is, Handoff decides by the kind.
  // A thing declared in two places under one name is one thing. What the
  // page's head says of a piece of writing in its own way (who wrote it and
  // when, and for a paper where it was printed) is added to the one piece
  // of writing declared, or stands as one where none is.
  function declared() {
    const types = [];
    const things = [];
    const placed = new Map();
    const add = (thing, main) => {
      const kinds = [].concat(thing['@type'] || []).filter((one) => typeof one === 'string').map((one) => one.slice(0, 40));
      for (const kind of kinds) {
        if (types.length < 8 && !types.includes(kind)) types.push(kind);
      }
      if (!kinds.length) return;
      const id = typeof thing['@id'] === 'string' ? thing['@id'] : '';
      const known = id ? placed.get(id) : undefined;
      if (known !== undefined) {
        const first = things[known];
        first.main = first.main || main;
        first.facts = Object.assign(said(thing), first.facts);
        for (const kind of kinds) {
          if (!first.types.includes(kind)) first.types.push(kind);
        }
        return;
      }
      if (things.length >= 12) return;
      if (id) placed.set(id, things.length);
      things.push({ types: kinds, main: main, facts: said(thing) });
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
    const name = (thing, depth) => {
      if (!thing || typeof thing !== 'object' || depth > 3 || ids.size >= 300) return;
      if (Array.isArray(thing)) {
        for (const one of thing) name(one, depth + 1);
        return;
      }
      if (typeof thing['@id'] === 'string' && thing.name && !ids.has(thing['@id'])) ids.set(thing['@id'], thing);
      name(thing['@graph'], depth + 1);
    };
    const parsed = [];
    ids = new Map();
    for (const script of doc.querySelectorAll('script[type="application/ld+json"]')) {
      const json = script.textContent || '';
      if (json.length > 300000 || parsed.length >= 20) continue;
      try {
        parsed.push(JSON.parse(json));
      } catch (error) {
        // Not what it says it is: nothing declared.
      }
    }
    for (const one of parsed) name(one, 0);
    for (const one of parsed) take(one, 0);

    const head = {};
    const fill = (key, value) => {
      if (value) head[key] = value;
    };
    const paper = meta(['citation_title'], 150);
    const by = meta(['citation_author', 'author', 'parsely-author', 'dc.creator', 'DC.creator'], 80);
    fill('author', /^https?:/i.test(by) ? '' : by);
    fill('published', meta(['article:published_time', 'citation_publication_date', 'citation_date', 'citation_online_date', 'parsely-pub-date', 'dc.date', 'DC.date'], 40));
    fill('modified', meta(['article:modified_time'], 40));
    if (paper) {
      fill('name', paper);
      fill('journal', meta(['citation_journal_title', 'citation_conference_title'], 100));
      fill('doi', meta(['citation_doi'], 80));
    }
    if (Object.keys(head).length) {
      const writing = /article|posting|report|scholarly|webpage/i;
      const pieces = things.filter((thing) => thing.types.some((one) => writing.test(one) && !/webpageelement/i.test(one)));
      // Only one of several kinds of writing is the article: a page it is on is not it.
      const articles = pieces.filter((thing) => thing.types.some((one) => /article|posting|report/i.test(one)));
      const target = articles.length === 1 ? articles[0] : pieces.length === 1 && !articles.length ? pieces[0] : null;
      if (target) {
        target.facts = Object.assign(head, target.facts);
      } else if (!articles.length && things.length < 12 && (head.author || head.published || paper)) {
        things.push({ types: [paper ? 'ScholarlyArticle' : 'Article'], main: false, facts: head });
      }
    }
    return { types: types, things: things };
  }

  // An element's words, without what is in it for the browser alone (a style, a script).
  function wordsOf(node) {
    if (!node.querySelector('style, script, template')) return node.textContent || '';
    const walker = (node.ownerDocument || doc).createTreeWalker(node, NodeFilter.SHOW_TEXT);
    let out = '';
    while (walker.nextNode()) {
      const parent = walker.currentNode.parentElement;
      if (!parent || !/^(style|script|template)$/.test(parent.localName)) out += walker.currentNode.data;
    }
    return out;
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
  // What the page has beside the part it calls its main one, not counting
  // what is the site's by its own word (a header, a foot, menus): how much
  // it says, and whether a title or a table is among it.
  function beside(main) {
    let said = 0;
    let weighty = false;
    for (let node = main; node && node !== whole && node.parentElement; node = node.parentElement) {
      for (const other of node.parentElement.children) {
        if (other === node) continue;
        const tag = other.localName;
        if (skipped.has(tag) || tag === 'header' || tag === 'footer' || skippedRoles.has(other.getAttribute('role') || '')) continue;
        let words = 0;
        try {
          words = shows(other) && other.getAttribute('aria-hidden') !== 'true' ? (other.innerText || '').replace(/\s+/g, ' ').trim().length : 0;
        } catch (error) {
          words = 0;
        }
        if (!words) continue;
        said += words;
        if (other.matches('h1, table') || other.querySelector('h1, table')) weighty = true;
      }
    }
    return { said: said, weighty: weighty };
  }

  const main = start(doc);
  let used = main;
  read(main);
  if (main !== whole) {
    // A main part with next to nothing in it is a page that doesn't say which part is which. And one
    // that leaves out the page's title, a table, or as much again as it holds is not all of the page:
    // a timetable set before it, a shop's name and rating over it.
    const rest = size < 200 ? null : beside(main);
    if (!rest || (rest.weighty && rest.said >= 10) || (rest.said >= 1500 && rest.said * 2 >= size)) {
      used = whole;
      read(whole);
    }
  }
  // Still next to nothing, on a page that has a great deal marked as hidden from assistive technology
  // and drawn all the same: a sheet is open over it ("Open in the app"), and the page under it is read.
  let under = false;
  if (size < 200 && whole.querySelector('[aria-hidden="true"]')) {
    const before = size;
    covered = true;
    read(whole);
    used = whole;
    under = size >= 200 && size > before * 2;
    if (!under) {
      covered = false;
      read(whole);
    }
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

  // One of a run of repeated things that says, word for word, what one before
  // it in the run said, and has a link: a carousel's slide shown again. All of
  // it or none: a card that shares its author's name with the card before it
  // has a title of its own, and keeps both.
  const things = new Map();
  for (const one of blocks) {
    if (one.group === undefined || one.item === undefined) continue;
    const key = one.group + ' ' + one.item;
    const thing = things.get(key) || { group: one.group, said: '', linked: false, blocks: [] };
    thing.said += one.text.replace(/^[ \t]*(?:[-*] |\d+\. )?/gm, '') + '\n';
    thing.linked = thing.linked || one.links > 0;
    thing.blocks.push(one);
    things.set(key, thing);
  }
  const shownAlready = new Set();
  const again = new Set();
  for (const thing of things.values()) {
    const key = thing.group + '\n' + thing.said;
    if (thing.linked && shownAlready.has(key)) {
      for (const one of thing.blocks) again.add(one);
    } else {
      shownAlready.add(key);
    }
  }
  if (again.size) {
    for (const one of again) size -= one.text.length + 2;
    blocks = blocks.filter((one) => !again.has(one));
  }

  // What was counted on the walk, as it stood when the walk ended: the notes
  // read after it are not what the page's kind is told by.
  const counted = { characters: Math.max(0, size - 2) };

  // The notes the text points to, from wherever the page keeps them (its
  // foot, most often, which the walk leaves out): each as Markdown writes a
  // note. One the walk already read where it stands is not read again.
  const taken = [];
  for (const one of notes) {
    if (full || blocks.length >= mostBlocks) break;
    const target = one.within.getElementById(one.id);
    if (!target || visited.has(target)) continue;
    // A note, not a part of the page: what a mark points to and is this long is a section.
    const held = wordsOf(target);
    if (held.length > 4000) continue;
    // Without the way back to the text a wiki puts before it: "^" or an arrow, and "a b c" or "1 2 3" where the note is pointed to more than once.
    let words = held.replace(/[\u2060\u200b\ufeff\u00ad]/g, '').replace(/\s+/g, ' ').trim().replace(/^[\^\u2191]\s*(?:a b (?:[c-z]{1,2} )*)?/, '').replace(/^1 2(?: \d{1,2})* (?=\S)/, '');
    // A note of great length is cut at a word, and says so.
    if (words.length > 600) words = words.slice(0, 600).replace(/\s+\S*$/, '') + '…';
    // A note that begins with its own mark has it once: "◊ For those who" under [^◊].
    if (words.length > one.label.length && words.startsWith(one.label) && /[\s.:)\]]/.test(words[one.label.length])) {
      words = words.slice(one.label.length).replace(/^[\s.:)\]]+/, '');
    }
    if (!words) continue;
    const made = '[^' + one.label + ']: ' + words;
    if (size + made.length + 2 > most) break;
    blocks.push({ kind: 'paragraph', text: made, characters: made.length, links: 0, linked: 0, hint: 'footnotes' });
    size += made.length + 2;
    taken.push(target);
  }

  // What of the page the walk was never in, by how much each says: the
  // site's own foot and top, its menus, what stands beside the content. So
  // that the file can say what is not in it. A menu inside the foot is the
  // foot's, and counted once; a note read out of it is in the file, and not counted.
  const left = { foot: 0, top: 0, menus: 0, beside: 0 };
  const out = [];
  for (const [name, selector] of [['foot', 'footer, [role="contentinfo"]'], ['top', 'header, [role="banner"]'],
    ['menus', 'nav, [role="navigation"]'], ['beside', 'aside, [role="complementary"]']]) {
    for (const element of Array.from(doc.querySelectorAll(selector)).slice(0, 60)) {
      if (visited.has(element) || out.some((one) => one.contains(element))) continue;
      let said = 0;
      try {
        said = shows(element) ? (element.innerText || '').replace(/\s+/g, ' ').trim().length : 0;
      } catch (error) {
        said = 0;
      }
      for (const note of taken) {
        if (said && element.contains(note)) said = Math.max(0, said - (note.innerText || '').replace(/\s+/g, ' ').trim().length);
      }
      if (!said) continue;
      out.push(element);
      left[name] += said;
    }
  }
  left.menus += parked;

  // Headings the walk never came to, on a page that went on past the limit:
  // what the file does not have, by name.
  const unread = [];
  if (full) {
    for (const heading of Array.from(used.querySelectorAll('h2, h3')).slice(0, 400)) {
      if (unread.length >= 30) break;
      // Not the site's, nor the heading of the page's own list of its contents, which names them all again.
      if (visited.has(heading) || heading.closest('nav, aside, footer, header, dialog, [hidden]:not([hidden="until-found"]), [aria-hidden="true"], #toc, .toc, [role="directory"]')) continue;
      const title = (heading.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80);
      if (title && !unread.includes(title)) unread.push(title);
    }
  }

  // The page says it is not done: it ends on a line that only says it is
  // loading, or a part of it that shows is marked as busy.
  let busy = /^(loading|로딩\s*중|불러오는\s*중(입니다)?|読み込み中)[\s.…]*$/i.test(blocks.length ? blocks[blocks.length - 1].text : '');
  if (!busy) {
    for (const one of Array.from(used.querySelectorAll('[aria-busy="true"]')).slice(0, 20)) {
      const box = one.getBoundingClientRect();
      if (box.width >= 40 && box.height >= 20 && shows(one)) {
        busy = true;
        break;
      }
    }
  }

  // How much of the window is drawn on, in hundredths: a page whose words are
  // drawn (a document or a sheet in an editor) has none of them to read.
  let drawnOn = 0;
  const wide = window.innerWidth || 0;
  const high = window.innerHeight || 0;
  for (const canvas of Array.from(doc.querySelectorAll('canvas')).slice(0, 40)) {
    const box = canvas.getBoundingClientRect();
    const across = Math.min(box.right, wide) - Math.max(box.left, 0);
    const down = Math.min(box.bottom, high) - Math.max(box.top, 0);
    if (across > 0 && down > 0 && shows(canvas)) drawnOn += across * down;
  }
  const canvas = wide * high > 0 ? Math.min(100, Math.round(drawnOn * 100 / (wide * high))) : 0;

  const says = declared();
  const result = {
    blocks: blocks,
    truncated: full,
    facts: {
      description: meta(['description', 'og:description', 'twitter:description'], 600),
      // What the page is called where it is shared: its own title, where the one shown was translated or has the site's name on it.
      titled: meta(['og:title', 'twitter:title']),
      type: meta(['og:type']),
      site: meta(['og:site_name', 'application-name', 'apple-mobile-web-app-title']),
      schema: says.types,
      headings: headings.slice(),
      characters: counted.characters,
      long: long,
      written: written,
      links: links,
      linked: linked,
      // Large pictures with no description, how tall they are together, and how tall the window is.
      unnamed: unnamed,
      unnamedTall: Math.round(unnamedTall),
      tall: Math.round(window.innerHeight || 0),
      left: left,
      // Things to press and things to fill in, over the whole page: what a
      // tool is made of, and a page to read has few of.
      controls: doc.querySelectorAll('button, [role="button"], [role="tab"], [role="menuitem"], [role="switch"]').length,
      fields: doc.querySelectorAll('input:not([type="hidden"]), textarea, select, [contenteditable]:not([contenteditable="false"])').length,
      drawn: doc.querySelectorAll('canvas').length,
      // And how much of the window they cover, in hundredths.
      canvas: canvas,
      // The page says it was still loading, or has a sheet over it that hides the rest from
      // assistive technology (read all the same), and what was not come to past the limit.
      busy: busy,
      covered: under,
      unread: unread,
      // Whether the page says which part of it is its content.
      marked: used !== whole,
    },
    things: says.things,
  };
  if (focus) result.focus = focus;
  return result;
})
