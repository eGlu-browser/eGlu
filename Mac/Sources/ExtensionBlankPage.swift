import AppKit
import WebKit

/// An empty page of the app's own at an extension's address, never a
/// site's, from a stand-in context with no scripts or pages of the
/// extension's: what a removed extension's pages kept there (localStorage,
/// IndexedDB, caches) cleared from it, as Search does (its forgetData).
/// WebKit's removeData doesn't reach those.
@MainActor
final class ExtensionBlankPage: NSObject, WKNavigationDelegate {
    private let view: WKWebView
    private var loaded: CheckedContinuation<Bool, Never>?

    init(_ configuration: WKWebViewConfiguration) {
        view = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        view.navigationDelegate = self
    }

    /// Whether it loaded at `base`, an extension's own address, and was cleared.
    func clear(at base: URL) async throws -> Bool {
        guard base.scheme == Extensions.scheme else { return false }
        let ready = await withCheckedContinuation { done in
            loaded = done
            view.loadHTMLString("<!doctype html>", baseURL: base)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                MainActor.assumeIsolated { self?.finish(false) }
            }
        }
        guard ready else { return false }
        _ = try await view.callAsyncJavaScript(Self.clearing, contentWorld: .defaultClient)
        return true
    }

    private static let clearing = """
        localStorage.clear();
        for (const db of await indexedDB.databases()) {
            await new Promise(done => { const q = indexedDB.deleteDatabase(db.name); q.onsuccess = q.onerror = q.onblocked = done; });
        }
        for (const key of await caches.keys()) await caches.delete(key);
        """

    private func finish(_ ok: Bool) {
        loaded?.resume(returning: ok)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }
}
