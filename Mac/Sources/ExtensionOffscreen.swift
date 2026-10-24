import AppKit
import WebKit

/// `chrome.offscreen`: a page with a DOM for an extension's worker, which
/// has none, never a tab anyone sees. One for each extension in each space,
/// as Chrome allows one an extension; made, found and closed through the
/// same record, also while its page is loading. After Search's
/// (github.com/driceroland/Search, MIT, its ExtensionOffscreen.swift), keyed
/// by space and extension; without its recording, which eGlu doesn't
/// offer extensions.
@MainActor
final class ExtensionOffscreen: NSObject, WKNavigationDelegate, WKUIDelegate, WKWebExtensionTab {
    private static var documents: [String: ExtensionOffscreen] = [:]

    private static func key(_ id: String, _ space: UUID) -> String { "\(space.uuidString)/\(id)" }

    struct Refused: LocalizedError {
        let why: String
        var errorDescription: String? { why }
    }

    static func create(_ path: String, for context: WKWebExtensionContext, in space: UUID) async throws {
        let key = key(context.uniqueIdentifier, space)
        guard documents[key] == nil else { throw Refused(why: "Only a single offscreen document may be created.") }
        guard let url = URL(string: path, relativeTo: context.baseURL)?.absoluteURL,
              url.scheme == context.baseURL.scheme, url.host() == context.baseURL.host(),
              url.user == nil, url.password == nil,
              let configuration = context.webViewConfiguration,
              let preferences = configuration.preferences.copy() as? WKPreferences
        else { throw Refused(why: "The offscreen document must belong to this extension.") }
        // It has no window by design: its DOM and its answers keep working,
        // with WebKit's throttling of pages out of sight still on.
        preferences.inactiveSchedulingPolicy = .throttle
        configuration.preferences = preferences
        let document = ExtensionOffscreen(context: context, space: space, url: url, key: key, configuration: configuration)
        // Its place taken before the first wait, so two at once can't
        // leave two pages for one extension.
        documents[key] = document
        // WebKit needs a tab for it to know the content scripts in its
        // frames. Only it knows of this one; no window lists it.
        context.didOpenTab(document)
        try await document.load()
    }

    static func close(_ id: String, in space: UUID) {
        documents[key(id, space)]?.close(error: Refused(why: "The offscreen document was closed."))
    }

    /// Every one of a space's, when the space goes; or of every space, when
    /// the extension does.
    static func closeAll(in space: UUID? = nil, of id: String? = nil) {
        for document in documents.values where (space == nil || document.space == space) && (id == nil || document.extensionID == id) {
            document.close(error: Refused(why: "The offscreen document was closed."))
        }
    }

    static func hasDocument(_ id: String, in space: UUID) -> Bool { documents[key(id, space)] != nil }

    /// Where it is now, for the extension's list of its own pages.
    static func url(_ id: String, in space: UUID) -> URL? {
        documents[key(id, space)].flatMap { $0.ready ? $0.web.url : nil }
    }

    /// What runtime.getContexts says of it.
    static func contexts(_ id: String, in space: UUID, matching filter: [String: Any]) -> [[String: Any]] {
        guard let document = documents[key(id, space)], document.ready else { return [] }
        let value = document.record
        let fields = ["contextIds": "contextId", "contextTypes": "contextType",
                      "documentIds": "documentId", "documentOrigins": "documentOrigin",
                      "documentUrls": "documentUrl", "frameIds": "frameId",
                      "tabIds": "tabId", "windowIds": "windowId"]
        for (plural, singular) in fields {
            guard let asked = filter[plural] else { continue }
            guard let choices = asked as? NSArray, let actual = value[singular], choices.contains(actual) else { return [] }
        }
        if let incognito = filter["incognito"] as? Bool, incognito { return [] }
        return [value]
    }

    private let extensionID: String
    private let space: UUID
    private let key: String
    private weak var extensionContext: WKWebExtensionContext?
    private let url: URL
    private let contextID = UUID().uuidString
    private let documentID = UUID().uuidString
    private let web: WKWebView
    private var loading: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?
    private var closed = false
    private var ready = false

    private var record: [String: Any] {
        ["contextId": contextID, "contextType": "OFFSCREEN_DOCUMENT",
         "documentId": documentID, "documentUrl": url.absoluteString,
         "documentOrigin": "\(url.scheme ?? "")://\(url.host() ?? "")",
         "frameId": 0, "tabId": -1, "windowId": -1, "incognito": false]
    }

    private init(context: WKWebExtensionContext, space: UUID, url: URL, key: String, configuration: WKWebViewConfiguration) {
        extensionContext = context
        extensionID = context.uniqueIdentifier
        self.space = space
        self.key = key
        self.url = url
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
    }

    private func load() async throws {
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.close(error: Refused(why: "The offscreen document did not finish loading."))
            }
            web.load(URLRequest(url: url))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        deadline?.cancel()
        deadline = nil
        let continuation = loading
        loading = nil
        continuation?.resume(with: result)
    }

    private func close(error: Error) {
        guard !closed else { return }
        closed = true
        if Self.documents[key] === self { Self.documents[key] = nil }
        extensionContext?.didCloseTab(self, windowIsClosing: false)
        web.navigationDelegate = nil
        web.uiDelegate = nil
        web.stopLoading()
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !closed, !ready else { return }
        ready = true
        finish(.success(()))
    }

    // The document stays on the extension's own pages, as Chrome keeps it:
    // a site loaded in its place would run out of sight, for as long as it
    // liked, with the extension's configuration. Its frames may go
    // anywhere; reading sites in them is what it is for. Nothing is saved
    // from it: no one asked for a file from a page no one sees.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { return decisionHandler(.cancel) }
        guard navigationAction.targetFrame?.isMainFrame != false else { return decisionHandler(.allow) }
        let to = navigationAction.request.url
        decisionHandler(to?.scheme == url.scheme && to?.host() == url.host() ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    // Only its first page failing ends it: once it is there, a later
    // navigation that fails leaves it where it was.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if !ready { close(error: error) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if !ready { close(error: error) }
    }

    // A page no one sees doesn't get the camera or the microphone.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        close(error: Refused(why: "The offscreen document's web process exited."))
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { nil }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { NSNotFound }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { web }
    func title(for context: WKWebExtensionContext) -> String? { web.title }
    func url(for context: WKWebExtensionContext) -> URL? { web.url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !web.isLoading }
    func isSelected(for context: WKWebExtensionContext) -> Bool { false }
    func close(for context: WKWebExtensionContext) async throws { close(error: Refused(why: "The offscreen document was closed.")) }
}
