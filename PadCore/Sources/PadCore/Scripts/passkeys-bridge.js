// The app's side of passkeys.js, in eGlu's own world, where the handler is
// and a page can't look (Mac/Sources/Passkeys.swift). A request the page's
// script dispatches is handed over as it is (the frame it comes from is
// WebKit's to say, not the event's), and the answer dispatched back for the
// page's script to pick up. From Search (github.com/driceroland/Search, MIT,
// PasskeyRelay.bridge in its Passkeys.swift).
//
// In the page itself it also says where the sign-in field is while it has
// the keyboard: a field marked for passkeys (autocomplete="… webauthn", as
// the standard asks of a page that offers them there), so the app can show
// the passkeys it holds for the site under it. Only where it is, never what
// is typed in it.
(function () {
  var handler = window.webkit && webkit.messageHandlers && webkit.messageHandlers.egluPasskeys;
  if (!handler || window.__egluPasskeys) return;
  var asked = 'eglu-passkeys-ask', answered = 'eglu-passkeys-answer';

  window.addEventListener(asked, function (event) {
    var message;
    try { message = JSON.parse(event.detail); } catch (e) { return; }
    if (!message || typeof message !== 'object' || typeof message.token !== 'string') return;
    // The field's word is this script's alone.
    if (message.kind === 'field') return;
    function answer(reply) {
      window.dispatchEvent(new CustomEvent(answered, { detail: JSON.stringify({ token: message.token, reply: reply }) }));
    }
    handler.postMessage(message).then(function (reply) {
      if (message.kind !== 'cancel') answer(reply);
    }, function () {
      if (message.kind !== 'cancel') answer(null);
    });
  });

  function forPasskeys(element) {
    if (!element || element.tagName !== 'INPUT') return false;
    var tokens = String(element.getAttribute('autocomplete') || '').toLowerCase().split(/\s+/);
    return tokens.indexOf('webauthn') >= 0;
  }
  // Where the field is, in the page's points from the view's top left corner.
  function place(element) {
    var r = element.getBoundingClientRect();
    return { x: r.left, y: r.top, width: r.width, height: r.height };
  }
  var field = null, pending = 0;
  function tell() {
    pending = 0;
    var rect = field && field.isConnected ? place(field) : null;
    handler.postMessage({ kind: 'field', token: '', rect: rect }).catch(function () {});
  }
  function soon() {
    if (!pending) pending = requestAnimationFrame(tell);
  }

  // What the app asks when its passkeys for the site come in after the field
  // already had the keyboard.
  window.__egluPasskeys = {
    field: function () {
      var focused = document.activeElement;
      return forPasskeys(focused) ? place(focused) : null;
    }
  };

  if (window.top !== window) return;
  document.addEventListener('focusin', function (event) {
    if (!forPasskeys(event.target)) return;
    field = event.target;
    soon();
  }, true);
  // A click in the field the list was closed over brings it back.
  document.addEventListener('mousedown', function (event) {
    if (forPasskeys(event.target)) { field = event.target; soon(); }
  }, true);
  document.addEventListener('focusout', function (event) {
    if (event.target !== field) return;
    field = null;
    soon();
  }, true);
  // The list follows the field as the page moves under it.
  window.addEventListener('scroll', function () { if (field) soon(); }, true);
  window.addEventListener('resize', function () { if (field) soon(); });
})();
