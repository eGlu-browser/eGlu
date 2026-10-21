import Foundation
import PadCore
import WebKit

/// Whether the page on screen has a password field, as the iPad's bridge.js
/// tells its page (SignIn.swift): such a page is a sign-in page wherever it
/// is, so its visit is taken back from history before it can go to iCloud
/// (PageHistory.signInFound). The Mac runs no bridge.js, so this script,
/// in the app's own world where the page can't reach it, does that part.
@MainActor
final class PasswordWatch: NSObject, WKScriptMessageHandler {
    static let name = "safiencePassword"

    /// Looks again a little after the page changes, and not while it is off
    /// screen, where a tab kept live may go on changing for hours. Says the
    /// address too, so a word from a document already gone is let go.
    static let script = """
    (() => {
      let password = null;
      let pending = 0;
      function check() {
        pending = 0;
        const present = !!document.querySelector('input[type="password" i]');
        if (present === password) return;
        password = present;
        window.webkit.messageHandlers.\(name).postMessage({ present, url: location.href });
      }
      function soon() {
        if (!pending && !document.hidden) pending = setTimeout(check, 400);
      }
      check();
      new MutationObserver(soon).observe(document.documentElement, {
        childList: true, subtree: true, attributes: true, attributeFilter: ['type'],
      });
      document.addEventListener('visibilitychange', soon);
    })();
    """

    private weak var page: Page?

    init(page: Page) {
        self.page = page
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let page, message.frameInfo.isMainFrame, message.world == Page.world,
                  let body = message.body as? [String: Any], body["present"] as? Bool == true,
                  let said = (body["url"] as? String).flatMap(URL.init(string:)),
                  let url = page.view.url, History.pageKey(said) == History.pageKey(url) else { return }
            page.passwordFound()
        }
    }
}
