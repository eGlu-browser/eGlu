// Read-only, called once before the app lets an off-screen page go: whether
// a text field holds something typed that the page hasn't kept, a value
// changed from the one it came with (a deletion to empty too). Such a page
// stays while there is memory for it; for want of memory it goes anyway
// (Pages.freeze's `force`), as one heavy tab live and none under pressure
// asks (Docs/Requirements.md). A canvas or a rich editor doesn't hold it:
// the web apps that have them keep their own drafts, and Figma is the heavy
// tab the limit is for.
//
// Looks through open shadow roots and same-origin frames; a frame it can't
// read, or a page too large to read through, is taken as nothing typed.
function egluHasDraft(handsOff) {
  const host = location.hostname.toLowerCase().replace(/\.+$/, '');
  if (handsOff.some((h) => host === h || host.endsWith('.' + h))) return true;
  const untyped = /^(button|checkbox|color|file|hidden|image|radio|range|reset|submit)$/;
  const pending = [document];
  const seen = new Set();
  let remaining = 20000;
  while (pending.length) {
    const root = pending.pop();
    if (seen.has(root)) continue;
    seen.add(root);
    for (const element of root.querySelectorAll('*')) {
      if (--remaining < 0) return false;
      if (element.tagName === 'TEXTAREA' || (element.tagName === 'INPUT' &&
          !untyped.test((element.getAttribute('type') || '').toLowerCase()))) {
        if (element.value !== element.defaultValue) return true;
      }
      if (element.shadowRoot) pending.push(element.shadowRoot);
      if (element.tagName === 'IFRAME' || element.tagName === 'FRAME') {
        try {
          // Asked of its location first: another site's frame refuses that
          // quietly, where WebKit logs a refused contentDocument as an error.
          void element.contentWindow.location.href;
          const inner = element.contentDocument;
          if (inner) pending.push(inner);
        } catch (_) {}
      }
    }
  }
  return false;
}
