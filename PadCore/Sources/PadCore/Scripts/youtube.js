// What YouTube keeps where Handoff's reader does not come to it: what is said
// in a video, which the site shows in a panel of its own once "Show
// transcript" is pressed (Adapters.youtube). One function, run in the app's
// own world when Handoff is asked for on a page of the site, after
// markdown.js has read the page (Page.transcript). It takes how many
// characters to give at the most, how long to wait in milliseconds, and, for
// Tests/youtube.html alone, the address to go by in place of the page's.
//
// The site's own way to its transcript is the only one used: its button is
// pressed, and the panel it opens is kept from being seen for the second it
// is open and closed again, so that the page looks as it did. The site's
// captions are not fetched and its service is not asked: both answer only
// the site's own player, by a check this script has no business passing.
//
// It gives one of:
//   { state: 'read', lines: [[time, words], …], cut, generated }
//       the transcript, each line with the time it is said at ("1:02:03");
//       `cut` when it went on past the characters asked for; `generated`
//       when the page says every caption it has was made by speech
//       recognition, and so may have names and words wrong.
//   { state: 'none' }     not a video's page, or a video with no transcript.
//   { state: 'absent', captions }
//       the page has no way to a transcript (the site as a phone is served
//       it has none), or has another of its panels open, which opening this
//       one would close. `captions` says whether the page names any captions
//       for the video, where it could tell: with none, there is no
//       transcript to look for on another of the site's pages either.
(async function (limit, patience, address) {
  const doc = document;
  const most = Math.max(0, Number(limit) || 0);
  const longest = Math.min(15000, Math.max(0, Number(patience) || 0));
  const wait = (time) => new Promise((done) => setTimeout(done, time));
  const now = () => (typeof performance === 'object' ? performance.now() : Date.now());

  let where = null;
  try {
    where = new URL(address || location.href);
  } catch (error) {
    return { state: 'none' };
  }
  const video = where.pathname === '/watch' ? where.searchParams.get('v') || ''
    : (/^\/(?:shorts|live)\/([\w-]{6,})/.exec(where.pathname) || [])[1] || '';
  if (!video) return { state: 'none' };

  const panelName = 'ytd-engagement-panel-section-list-renderer';
  const ours = panelName + '[target-id*="transcript"]';
  const lineName = 'transcript-segment-view-model, ytd-transcript-segment-renderer';
  const open = 'ENGAGEMENT_PANEL_VISIBILITY_EXPANDED';

  // What the page says of the video's captions, in the data it was sent
  // with: the app's world sees the page's elements and not its variables.
  // Only where that data is of this video, which it is not once the site
  // has gone on to another without loading a page.
  function captions() {
    for (const script of doc.scripts) {
      const text = script.textContent || '';
      if (text.length < 200 || text.length > 4000000) continue;
      if (!text.includes('"videoDetails"')) continue;
      const about = /"videoDetails":\{"videoId":"([\w-]+)"/.exec(text);
      if (!about || about[1] !== video) continue;
      const at = text.indexOf('"captionTracks":[');
      if (at < 0) return { any: false, generated: false };
      const end = text.indexOf(']', at);
      const tracks = text.slice(at, end < 0 ? at + 20000 : Math.min(end, at + 20000));
      const all = (tracks.match(/"baseUrl"/g) || []).length;
      const made = (tracks.match(/"kind":"asr"/g) || []).length;
      return { any: all > 0, generated: all > 0 && made >= all };
    }
    return null;
  }

  // A line of the transcript: the time it is said at, and its words. The
  // time is written twice, once to be seen and once to be heard ("11
  // seconds"): the one to be seen is the one that is kept.
  function line(node) {
    const stamp = node.querySelector('[class*="Timestamp"]:not([class*="A11y"]), .segment-timestamp');
    let time = stamp ? (stamp.textContent || '').replace(/\s+/g, '') : '';
    if (!/^\d{1,3}(?::\d{2}){1,2}$/.test(time)) time = '';
    const said = node.querySelector('[role="text"], .segment-text') || node.lastElementChild || node;
    const words = (said.textContent || '').replace(/[​⁠﻿]/g, '').replace(/\s+/g, ' ').trim();
    return words ? [time, words.slice(0, 2000)] : null;
  }

  function read() {
    const lines = [];
    let size = 0;
    let cut = false;
    for (const node of doc.querySelectorAll(lineName)) {
      const one = line(node);
      if (!one) continue;
      if (lines.length >= 20000 || size + one[1].length + 8 > most) {
        cut = true;
        break;
      }
      lines.push(one);
      size += one[1].length + 8;
    }
    const known = captions();
    const result = { state: 'read', lines: lines, cut: cut };
    if (known && known.generated) result.generated = true;
    return result;
  }

  // Open already, by the person: read where it stands, and left as it is.
  if (doc.querySelector(lineName)) return read();

  // Which of the site's two pages this is. The one a phone is served is another page altogether,
  // with no transcript anywhere in it: nothing to wait for there. A page still on its way in (one
  // loaded out of sight is asked as soon as it is there to ask) is waited for until it can be told.
  const until = now() + longest;
  while (!doc.querySelector('ytd-app')) {
    if (doc.querySelector('ytm-app') || doc.readyState !== 'loading' || now() >= until) {
      const known = captions();
      return { state: 'absent', captions: known ? known.any : null };
    }
    await wait(100);
  }

  // The button the site has for it, in the video's description. It is there
  // before the description is opened, and can be pressed where it is.
  let opener = null;
  for (;;) {
    opener = doc.querySelector('ytd-video-description-transcript-section-renderer button');
    if (opener || now() >= until) break;
    await wait(150);
  }
  let panel = doc.querySelector(ours);
  if (!opener || !panel) {
    // The video's description is drawn and has no transcript in it: there is none. Not drawn yet
    // when the wait ran out is another matter, and is said as that.
    if (doc.querySelector('ytd-watch-metadata #description, ytd-structured-description-content-renderer')) return { state: 'none' };
    const known = captions();
    return { state: 'absent', captions: known ? known.any : null };
  }
  // Another of the site's panels is open (chapters, a live chat): this one would take its place.
  // The site has more than one panel for a transcript, and says which it opens only by opening it.
  for (const other of doc.querySelectorAll(panelName + '[visibility="' + open + '"]')) {
    if (!other.matches(ours)) return { state: 'absent', captions: true };
  }

  // Not to be seen for as long as it is open, nor touched, and out of the page's layout, so nothing
  // moves. In the window all the same, at its corner: one of the site's panels fetches its lines
  // only once it is there, and parked off the page's edge it waited for ever.
  const hide = doc.createElement('style');
  hide.textContent = ours + ' { position: fixed !important; left: 0 !important; top: 0 !important; width: 400px !important;'
    + ' height: 600px !important; max-height: 100vh !important; opacity: 0 !important; pointer-events: none !important; z-index: -1 !important; }';
  (doc.head || doc.documentElement).append(hide);
  let result = { state: 'none' };
  try {
    opener.click();
    // Until its lines have come, and then until no more are coming: for what is left of the wait, and two and a half seconds at the least.
    const by = now() + Math.max(2500, until - now());
    let count = 0;
    let steady = 0;
    while (now() < by) {
      await wait(120);
      const found = doc.querySelectorAll(lineName).length;
      steady = found && found === count ? steady + 1 : 0;
      count = found;
      if (steady >= 2) break;
    }
    if (count) result = read();
  } finally {
    // Closed again by its own button, and only then let back into the page's layout: whichever of
    // the site's panels for a transcript it was that opened.
    panel = doc.querySelector(ours + '[visibility="' + open + '"]') || panel;
    // Its button to close it, which is the last in its header where it is not named as that: the one before is for more to do.
    const titled = panel.querySelectorAll('ytd-engagement-panel-title-header-renderer button');
    const close = panel.querySelector('#visibility-button button') || (titled.length ? titled[titled.length - 1] : null);
    if (close && panel.getAttribute('visibility') === open) close.click();
    for (let tries = 0; tries < 8 && panel.getAttribute('visibility') === open; tries += 1) await wait(80);
    hide.remove();
  }
  return result;
})
