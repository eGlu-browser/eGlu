import AppKit
import Combine
import PadCore
import WebKit

/// The Chrome Web Store's "Add to Safience" button (Scripts/extension-store.js,
/// after Search's StoreRelay). What gets installed is read from the tab's
/// own address, never from what the page says: the page only asks, and the
/// install sheet still stands between the asking and the installing.
@MainActor
final class StoreButton: NSObject, WKScriptMessageHandler {
    static let name = "safienceStore"

    private weak var page: Page?

    init(page: Page) {
        self.page = page
    }

    static func isStore(_ url: URL?) -> Bool {
        url?.scheme == "https" && url?.host() == "chromewebstore.google.com"
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            // Only the store page's main frame, in the app's own world.
            guard let page, message.frameInfo.isMainFrame, message.world == Page.world,
                  let url = page.view.url, Self.isStore(url), let body = message.body as? [String: Any] else { return }
            if body["add"] != nil {
                let window = Session.shared.allWindows.first { $0.tabID == page.tab }
                Extensions.shared.add(fromStorePage: url, in: window)
            }
            if body["placed"] != nil { Self.tell(page) }
        }
    }

    /// Tells a store page what is installed and what is on its way, so its
    /// button can say "Added to Safience" or "Adding…".
    static func tell(_ page: Page) {
        guard isStore(page.view.url) else { return }
        let extensions = Extensions.shared
        let state: [String: Any] = ["installed": extensions.installed.map(\.id), "busy": extensions.busy ?? NSNull()]
        guard let json = try? JSONSerialization.data(withJSONObject: state),
              let text = String(data: json, encoding: .utf8) else { return }
        page.tellStore(text)
    }

    /// And tells every store page again whenever either changes.
    static func follow() -> AnyCancellable {
        let extensions = Extensions.shared
        return extensions.$installed.map { _ in () }
            .merge(with: extensions.$busy.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink {
                MainActor.assumeIsolated {
                    for page in Session.shared.pages.live.values where isStore(page.view.url) { tell(page) }
                }
            }
    }
}
