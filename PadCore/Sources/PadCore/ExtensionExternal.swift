import Foundation

/// A website talking to an extension that lists it (Search's #496).
///
/// An extension's manifest can name websites under `externally_connectable`,
/// and those pages may send it messages: claude.ai hands Claude in Chrome its
/// sign-in that way, with chrome.runtime.sendMessage(extensionId, …). WebKit
/// does the work: it puts a `browser.runtime` in the page's own world, and
/// what a listed page sends reaches the extension's runtime.onMessageExternal
/// with the page's origin and address as the sender. What it doesn't do is
/// name it `chrome`, the name every page written for Chrome calls.
///
/// WebKit gives every page that `browser` once any extension is loaded, so
/// the name can't simply follow it: a `chrome` on every site would tell them
/// all this is Chrome. Only a page an extension on in the space lists, by
/// Chrome's rules for match patterns, gets `chrome.runtime` (the same two
/// calls, with Chrome's callbacks as well as promises), and only if it has
/// no `chrome` of its own.
///
/// A message for an extension that isn't there, or doesn't list the page,
/// fails as in Chrome ("Receiving end does not exist") instead of going to
/// WebKit, which answers it with nothing. claude.ai's sign-in tries
/// Anthropic's own build of Claude in Chrome first and takes any answer but
/// a refusal for done: given nothing, it spun for good (Search's 5f1038c).
public enum ExtensionExternal {
    /// The patterns of an extension's `externally_connectable` Chrome would
    /// take, and no others.
    public static func listed(in manifest: [String: Any]) -> [String] {
        let listed = manifest["externally_connectable"] as? [String: Any]
        return Array(Set(((listed?["matches"] as? [String]) ?? []).filter(allowed))).sorted()
    }

    /// Chrome refuses a pattern for every site (`*://*/*`) and a wildcard
    /// over a whole top-level domain (`*.com`): a wildcard needs a domain
    /// with a dot in it, which fails closed where Chrome reads the public
    /// suffix list. Google's sites are left out too: a page there with a
    /// partial `chrome` and Safari's name is what its sign-in and reCAPTCHA
    /// look for to turn a browser away (HandsOff).
    public static func allowed(_ pattern: String) -> Bool {
        guard let start = pattern.range(of: "://") else { return false }
        let scheme = pattern[..<start.lowerBound]
        guard ["*", "http", "https"].contains(scheme) else { return false }
        let rest = pattern[start.upperBound...]
        var host = String(rest.prefix { $0 != "/" }).lowercased()
        guard rest.dropFirst(host.count).hasPrefix("/") else { return false }
        if let colon = host.lastIndex(of: ":"), !host.hasSuffix("]") { host = String(host[..<colon]) }
        guard host != "*", !host.isEmpty else { return false }
        if host.hasPrefix("*.") {
            let base = host.dropFirst(2)
            guard base.contains("."), !base.contains("*") else { return false }
        } else if host.contains("*") {
            return false
        }
        let labels = host.split(separator: ".")
        return !labels.dropLast().contains("google")
    }

    /// The script for a page about to load, in its own world before any of
    /// its scripts, given each extension's listed patterns by its id; nil
    /// with nothing listed.
    public static func script(listings: [String: [String]]) -> String? {
        let found = listings.filter { !$0.value.isEmpty }
        guard !found.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: found, options: [.sortedKeys, .withoutEscapingSlashes]),
              let list = String(data: data, encoding: .utf8)
        else { return nil }
        return """
        (function (listings) {
          var made = window.browser, runtime = made && made.runtime;
          if (typeof window.chrome !== 'undefined' || !runtime || typeof runtime.sendMessage !== 'function') return;
          // Chrome's match patterns: scheme, host, then path. A host with a
          // port matches that port only; one without, any.
          var glob = function (text) {
            return new RegExp('^' + text.replace(/[.+?^${}()|[\\]\\\\]/g, '\\\\$&').replace(/\\*/g, '.*') + '$');
          };
          var listed = function (pattern) {
            var parts = /^(\\*|https?):\\/\\/([^\\/]+)(\\/.*)$/.exec(pattern);
            if (!parts) return false;
            var scheme = location.protocol.slice(0, -1);
            if (parts[1] === '*' ? scheme !== 'http' && scheme !== 'https' : parts[1] !== scheme) return false;
            var host = parts[2], port = '';
            var colon = host.lastIndexOf(':');
            if (colon > 0 && host.indexOf(']') < colon) { port = host.slice(colon + 1); host = host.slice(0, colon); }
            if (port && port !== '*' && port !== location.port) return false;
            var here = location.hostname;
            if (host.indexOf('*.') === 0) {
              var base = host.slice(2);
              if (base.indexOf('.') < 0) return false;
              if (here !== base && here.slice(-base.length - 1) !== '.' + base) return false;
            } else if (host !== here) return false;
            return glob(parts[3]).test(location.pathname + location.search);
          };
          // The extensions that list this page: the only ones it can reach.
          var reached = Object.keys(listings).filter(function (id) { return listings[id].some(listed); });
          if (!reached.length) return;
          var chromeRuntime = {
            sendMessage: function (id, message, options, callback) {
              if (typeof options === 'function') { callback = options; options = undefined; }
              var sent = reached.indexOf(id) < 0
                ? Promise.reject(new Error('Could not establish connection. Receiving end does not exist.'))
                : options === undefined ? runtime.sendMessage(id, message) : runtime.sendMessage(id, message, options);
              if (typeof callback !== 'function') return sent;
              Promise.resolve(sent).then(function (reply) { callback(reply); }, function (error) {
                chromeRuntime.lastError = { message: String(error && error.message || error) };
                try { callback(); } finally { delete chromeRuntime.lastError; }
              });
            }
          };
          if (typeof runtime.connect === 'function') {
            // A port to an extension that doesn't list the page, or to none
            // named, is closed at once with Chrome's error, never opened.
            var closed = function (name) {
              var gone = [];
              var event = function (list) {
                return { addListener: function (f) { list.push(f); },
                  removeListener: function (f) { var i = list.indexOf(f); if (i >= 0) list.splice(i, 1); },
                  hasListener: function (f) { return list.indexOf(f) >= 0; } };
              };
              var port = { name: typeof name === 'string' ? name : '', sender: undefined, onMessage: event([]), onDisconnect: event(gone),
                postMessage: function () { throw new Error('Attempting to use a disconnected port object'); }, disconnect: function () {} };
              Promise.resolve().then(function () {
                chromeRuntime.lastError = { message: 'Could not establish connection. Receiving end does not exist.' };
                try { gone.slice().forEach(function (f) { f(port); }); } finally { delete chromeRuntime.lastError; }
              });
              return port;
            };
            chromeRuntime.connect = function (id, info) {
              if (typeof id !== 'string' || reached.indexOf(id) < 0) return closed((typeof id === 'string' ? info : id || info || {}).name);
              return runtime.connect.apply(runtime, arguments);
            };
          }
          try {
            Object.defineProperty(window, 'chrome', {
              value: { runtime: chromeRuntime }, configurable: true, writable: true, enumerable: false
            });
          } catch (e) {}
        })(\(list));
        """
    }
}
