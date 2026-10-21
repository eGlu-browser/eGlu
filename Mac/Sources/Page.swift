import AppKit
import PadCore
import UniformTypeIdentifiers
import WebKit

/// What a page asks of whoever is showing it: a window (WindowModel) or a
/// sign-in pop-up (Popup).
@MainActor
protocol PageHost: AnyObject {
    func pageDidChange(_ page: Page)
    func isShowing(_ page: Page) -> Bool
    /// A window the page opened (window.open, a link to a new window). The
    /// returned view must be made with `configuration`, as WebKit requires,
    /// for the new page to keep its tie to the one that opened it.
    func page(_ page: Page, open configuration: WKWebViewConfiguration, for action: WKNavigationAction,
              features: WKWindowFeatures) -> WKWebView?
    /// A ⌘-click's address, for a tab of its own (NewTabClick); false where
    /// there are no tabs, and the page goes there itself.
    func page(_ page: Page, openInNewTab url: URL, inFront: Bool) -> Bool
    func pageDidClose(_ page: Page)
    /// The window to put an alert or a sheet on.
    var hostWindow: NSWindow? { get }
}

/// A page of a site loaded out of sight, read once by the site's own reader
/// and let go: for what the page on screen does not have and another page
/// of the same site does (Page.transcript). The iPad's (App/Sources/Page.swift),
/// on a Mac: the same store as the page on screen, nothing played, none of
/// the app's scripts but the reader's one call, the content blocker's lists
/// where the page has them, and nowhere but its own site. It stands in the
/// window under the page on screen, unseen, where WebKit runs it as a page
/// that shows.
@MainActor
private final class Unseen: NSObject, WKNavigationDelegate {
    /// How long the page on screen is given to show its way to what is looked for, in milliseconds.
    static let patienceHere = 1_500
    /// How long a page out of sight is given to begin, and then to show the way, in milliseconds.
    private static let start: Duration = .seconds(6)
    private static let patienceThere = 9_000

    private let view: WKWebView
    /// The site it is a page of, and may not leave.
    private let site: SiteAdapter
    private var loaded: ((Bool) -> Void)?

    init(beside page: Page, of site: SiteAdapter) {
        self.site = site
        let config = WKWebViewConfiguration()
        config.websiteDataStore = page.view.configuration.websiteDataStore
        config.applicationNameForUserAgent = page.view.configuration.applicationNameForUserAgent
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.allowsAirPlayForMediaPlayback = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let controller = WKUserContentController()
        if page.blocksContent {
            for list in ContentBlocker.shared.lists { controller.add(list) }
        }
        config.userContentController = controller
        view = WKWebView(frame: page.view.frame, configuration: config)
        super.init()
        view.navigationDelegate = self
        view.alphaValue = 0
        view.setAccessibilityElement(false)
        view.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        page.view.superview?.addSubview(view, positioned: .below, relativeTo: page.view)
    }

    /// Loads the page, has the reader called on it, and lets the page go, whatever came of it.
    func transcript(at url: URL, call: String, limit: Int) async -> Transcript? {
        defer { stop() }
        guard !HandsOff.covers(url), await begin(url), !Task.isCancelled else { return nil }
        let said = try? await view.callAsyncJavaScript(call, arguments: ["limit": limit, "patience": Self.patienceThere], in: nil,
                                                       contentWorld: Page.world)
        if case .read(let transcript) = Transcript.answer(said) { return transcript }
        return nil
    }

    /// Whether the page began to load, in the time it is given.
    private func begin(_ url: URL) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            loaded = { done.resume(returning: $0) }
            view.load(URLRequest(url: url))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.start)
                self?.finish(false)
            }
        }
    }

    /// The one answer to whether it began, from whichever comes first: the page, a failure, or the time running out.
    private func finish(_ ok: Bool) {
        loaded?(ok)
        loaded = nil
    }

    /// The page goes, and whoever waits on its load hears that nothing came of it.
    func stop() {
        finish(false)
        view.navigationDelegate = nil
        view.stopLoading()
        view.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // The page itself may go only to its own site: a step anywhere else ends the reading.
        guard navigationAction.targetFrame?.isMainFrame ?? true else { return decisionHandler(.allow) }
        let url = navigationAction.request.url
        let own = ["http", "https"].contains(url?.scheme?.lowercased() ?? "") && site.covers(url)
        guard own, !HandsOff.covers(url), !navigationAction.shouldPerformDownload else {
            decisionHandler(.cancel)
            finish(false)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        finish(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(false)
    }
}

/// A page's web view: WebKit's, with its menu saying "Tab" where WebKit's says
/// "Window", since a page asking for a window gets a tab here as in Safari.
final class PageView: WKWebView {
    weak var page: Page?

    private static let renamed: [String: String] = [
        "WKMenuItemIdentifierOpenLinkInNewWindow": "Open Link in New Tab",
        "WKMenuItemIdentifierOpenImageInNewWindow": "Open Image in New Tab",
        "WKMenuItemIdentifierOpenMediaInNewWindow": "Open Video in New Tab",
        "WKMenuItemIdentifierOpenFrameInNewWindow": "Open Frame in New Tab",
    ]

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        for item in menu.items {
            if let id = item.identifier?.rawValue, let title = Self.renamed[id] { item.title = title }
        }
        super.willOpenMenu(menu, with: event)
    }
}

/// One tab's page while it is live: its web view, the content blocker's
/// lists and scripts it gets, and everything WebKit tells it.
///
/// On a Mac the trackpad, the mouse and every ⌘ key reach the page as they
/// do in Safari, so none of the iPad's bridges (bridge.js) go into a page
/// here. This is still the only place the app calls into a page or changes
/// what goes into one, and every such call first asks HandsOff whether it
/// may (PolicyTests keeps it that way).
@MainActor
final class Page: NSObject {
    /// The app's own content world: what it asks a page lives here, out of the page's sight.
    static let world = WKContentWorld.world(name: "Safience")

    let tab: UUID
    let space: UUID
    let view: PageView
    private let controller: WKUserContentController
    weak var host: PageHost?

    /// The site's adapter, for what its own reader can add to a handoff (a
    /// video's transcript) and how heavy its pages are; none of its bridges.
    private(set) var adapter = Adapters.standard
    /// The scripts installed for the next document: the scripted filters'
    /// stamp, "hands-off", or nil before the first page.
    private var installed: String?
    /// The content blocker's lists on this page, by identifier: none on a
    /// hands-off page, or where Settings or the site's switch turns it off.
    private var blocking: [String] = []
    private(set) var committed: URL?
    /// Why the last load failed, to show in place of the page; nil once one loads.
    private(set) var failure: String?
    /// The page's process kept ending; it waits for a click to load again.
    private(set) var exhausted = false
    private var crashes = CrashGuard()
    /// The question about a link for another app, while it is up, and how
    /// often this page has been told no (openElsewhere).
    private var askingElsewhere = false
    private var refusedElsewhere = 0
    /// The screen's light or dark, to the sites that ask for it as a header
    /// (ColorSchemeHint): for every page, and for the run only.
    private static var colorHint = ColorSchemeHint()
    /// Whether the page's last request had that header, and could be made again.
    private var hintCarried = false
    private var hintRepeatable = false
    /// A page another page opened (window.open, a link to a new window).
    private var wasOpened = false
    private var observations: [NSKeyValueObservation] = []
    /// The visit the document on screen is, in its space's history (PageHistory).
    private var history = PageHistory()

    /// The page is a tab coming back as it was (thawed, or at launch): its
    /// first document was visited already.
    func restoring() {
        history.restoring()
    }

    /// `configuration`: WebKit's, for a page opened by another page; a new
    /// one in the space's store otherwise. Either way the page gets a script
    /// controller of its own, so the scripts swapped for one page (none at
    /// all on a hands-off host) never touch another's.
    init(tab: UUID, space: UUID, configuration: WKWebViewConfiguration? = nil) {
        self.tab = tab
        self.space = space
        let config = configuration ?? Page.configuration(space: space)
        let controller = WKUserContentController()
        config.userContentController = controller
        self.controller = controller
        view = PageView(frame: .zero, configuration: config)
        super.init()
        view.page = self
        view.navigationDelegate = self
        view.uiDelegate = self
        setUp()
    }

    static func configuration(space: UUID) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Stores.store(for: space)
        // Safari, by name: the end of the user agent that WebKit leaves to
        // the app (Identity.swift). Without it sites read the app as a web
        // view inside an app, and Google refuses to sign in.
        config.applicationNameForUserAgent = Identity.applicationName(for: ProcessInfo.processInfo.operatingSystemVersion)
        config.mediaTypesRequiringUserActionForPlayback = .audio
        config.preferences.isElementFullscreenEnabled = true
        // window.open only from a click or a key, as Safari's pop-up
        // blocking has it; a sign-in window opened by its button opens.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return config
    }

    private func setUp() {
        // Safari's own: a two-finger swipe goes back and forward, a pinch zooms.
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        view.isInspectable = true
        observations = [
            view.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            view.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            // How a load is going is the window's to show and not the workspace's to keep.
            view.observe(\.isLoading) { [weak self] _, _ in MainActor.assumeIsolated { self?.progressed() } },
            view.observe(\.estimatedProgress) { [weak self] _, _ in MainActor.assumeIsolated { self?.progressed() } },
            view.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.progressed() } },
            view.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.progressed() } },
            view.observe(\.hasOnlySecureContent) { [weak self] _, _ in MainActor.assumeIsolated { self?.progressed() } },
        ]
    }

    /// Where the page is, or what it is called, is another: kept, and shown.
    private func changed() {
        if let url = view.url {
            Session.shared.record(tab, url: url, title: view.title)
        }
        history.changed(url: view.url, title: view.title, loading: view.isLoading, space: space, tab: tab)
        host?.pageDidChange(self)
    }

    private func progressed() {
        host?.pageDidChange(self)
    }

    /// Lets the page go: the view out of its window, its scripts gone.
    /// WebKit ends the page's process once nothing holds the view.
    func tearDown() {
        observations.forEach { $0.invalidate() }
        observations = []
        controller.removeAllUserScripts()
        controller.removeAllContentRuleLists()
        blocking = []
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.page = nil
        view.removeFromSuperview()
        host = nil
    }

    // MARK: Loading

    func load(_ url: URL) {
        failure = nil
        exhausted = false
        request(url)
    }

    /// A site by request; a file opened from Finder with leave for the page
    /// to read it, and only it, which a request for its address is refused,
    /// and readable again through its bookmark after a relaunch (FileAccess).
    private func request(_ url: URL) {
        if url.isFileURL {
            FileAccess.open(url)
            view.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            view.load(URLRequest(url: url))
        }
    }

    /// `byHand`: asked for, so the count of endings starts over.
    func reload(byHand: Bool = true) {
        failure = nil
        exhausted = false
        if byHand { crashes.reset() }
        if view.url == nil, let url = committed ?? Session.shared.workspace.tab(tab)?.url {
            request(url)
        } else {
            view.reload()
        }
        host?.pageDidChange(self)
    }

    var isHandsOff: Bool {
        HandsOff.covers(view.url) || HandsOff.covers(committed)
    }

    var isSignIn: Bool {
        SignIn.isSignInPage(view.url)
    }

    var isHeavy: Bool {
        adapter.isHeavy(view.url)
    }

    /// Only a live page can keep these going: a call, a recording, a download.
    var mustStay: Bool {
        isHandsOff || view.cameraCaptureState != .none || view.microphoneCaptureState != .none
            || Downloads.shared.isDownloading(for: self)
    }

    /// Puts in what the page about to load at `url` gets: the content
    /// blocker's lists and the scripts for what its filters ask that WebKit's
    /// rules can't do (ScriptedFilters), and nothing at all on a hands-off
    /// host. Called before each main-frame document is made, from the
    /// navigation's policy decision, so the document starts with them.
    private func prepare(for url: URL?) {
        let handsOff = HandsOff.covers(url)
        applyBlocking(for: url)
        adapter = Adapters.adapter(for: url)
        let filters = blocksContent ? ContentBlocker.shared.scriptedRules(for: url) : PageRules()
        let wanted = handsOff ? "hands-off" : (filters.isEmpty ? "" : filters.stamp)
        guard wanted != installed else { return }
        installed = wanted
        controller.removeAllUserScripts()
        guard !handsOff else { return }
        // The hiding from the app's own world, where the page can't reach
        // it; the scriptlets in the page's, since what they change is the
        // page's own.
        if let script = Scripts.blocker(for: filters) {
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: Page.world))
        }
        if let script = Scripts.scriptlets(for: filters) {
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: .page))
        }
    }

    /// The content blocker's lists for a document at `url` (ContentBlocker):
    /// WebKit blocks with them from the next load. Never on a hands-off
    /// host, where nothing of the app's may touch the page.
    private func applyBlocking(for url: URL?) {
        let on = !HandsOff.covers(url) && Session.shared.preferences.blocksContent(onHost: url?.host)
        let lists = on ? ContentBlocker.shared.lists : []
        let identifiers = lists.compactMap(\.identifier)
        guard identifiers != blocking else { return }
        controller.removeAllContentRuleLists()
        for list in lists { controller.add(list) }
        blocking = identifiers
    }

    /// Whether the page on screen has ads and trackers blocked, for its menu.
    var blocksContent: Bool {
        !blocking.isEmpty
    }

    /// The content blocker has new lists: this page's next load has them.
    func blockingChanged() {
        applyBlocking(for: committed ?? view.url)
    }

    /// After Settings changed: from the next page.
    func settingsChanged() {
        prepare(for: committed ?? view.url)
    }

    /// Whether a navigation is a ⌘-click (or ⌘⇧, or a middle click) to open
    /// in a new tab (NewTabClick), from the keys and the button WebKit says made it.
    private func newTabChoice(for action: WKNavigationAction) -> NewTabClick.Choice {
        let flags = action.modifierFlags
        let kind: NewTabClick.Kind
        switch action.navigationType {
        case .linkActivated: kind = .link
        case .formSubmitted: kind = .form
        case .other: kind = .script
        default: kind = .history
        }
        return NewTabClick.choice(kind: kind, command: flags.contains(.command), shift: flags.contains(.shift),
                                  middleButton: action.buttonNumber == 2, method: action.request.httpMethod,
                                  scheme: action.request.url?.scheme, mainFrame: action.targetFrame?.isMainFrame ?? true)
    }

    // MARK: Find, zoom, print

    /// The next place the words are on the page, after the selection or
    /// before it; `found` hears whether there is one.
    func find(_ text: String, backwards: Bool = false, found: @escaping (Bool) -> Void) {
        guard !text.isEmpty else { return found(false) }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        view.find(text, configuration: configuration) { result in found(result.matchFound) }
    }

    /// Safari's steps of zoom, from half to three times.
    private static let zooms: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    func zoom(by step: Int) {
        guard step != 0 else {
            view.pageZoom = 1
            return
        }
        let now = view.pageZoom
        let next = step > 0 ? Self.zooms.first { $0 > now + 0.01 } : Self.zooms.last { $0 < now - 0.01 }
        if let next { view.pageZoom = next }
    }

    func print() {
        guard let window = host?.hostWindow else { return }
        let operation = view.printOperation(with: NSPrintInfo.shared)
        operation.view?.frame = view.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Calls into the page

    /// The page as Markdown, for a handoff (markdown.js, the iPad's). Never on a hands-off page.
    func markdown(limit: Int) async -> PageReading? {
        guard !HandsOff.covers(view.url), !HandsOff.covers(committed) else { return nil }
        let value = try? await view.callAsyncJavaScript(Scripts.markdownCall, arguments: ["limit": limit], in: nil,
                                                        contentWorld: Page.world)
        return (value as? [String: Any]).flatMap(PageReading.init)
    }

    /// What is said in the page's recording, where the site has a reader of
    /// its own that can get it (SiteAdapter.reader: YouTube's presses the
    /// site's "Show transcript" out of sight). Asked of the page on screen
    /// first, and of another of the site's pages loaded out of sight where
    /// this one has no way to it (Unseen). Never on a hands-off page.
    func transcript(limit: Int) async -> Transcript? {
        guard !HandsOff.covers(view.url), !HandsOff.covers(committed), let call = Scripts.readerCall(for: adapter) else { return nil }
        let said = try? await view.callAsyncJavaScript(call, arguments: ["limit": limit, "patience": Unseen.patienceHere], in: nil,
                                                       contentWorld: Page.world)
        let here = Transcript.answer(said)
        if case .read(let transcript) = here { return transcript }
        guard here.looksElsewhere, !Task.isCancelled, let url = adapter.readerPage(for: view.url), !HandsOff.covers(url) else { return nil }
        let unseen = Unseen(beside: self, of: adapter)
        return await withTaskCancellationHandler {
            await unseen.transcript(at: url, call: call, limit: limit)
        } onCancel: {
            Task { @MainActor in unseen.stop() }
        }
    }

    /// The page as it looks, `pixels` wide, for Apple Intelligence's model
    /// to look at a page with too few words to go by (HandoffJob). A picture,
    /// not a script: nil when the page is not in a window.
    func picture(pixels: CGFloat) async -> CGImage? {
        guard view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        configuration.snapshotWidth = NSNumber(value: Double(pixels / max(1, view.window?.backingScaleFactor ?? 2)))
        return await withCheckedContinuation { continuation in
            view.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
        }
    }

    /// The icons the page names, best first, as bridge.js's siteIcons() has
    /// them on the iPad: the site's own icon, as browsers show it, a drawing
    /// before its largest picture; then Apple's touch icon, a square for a
    /// Home Screen; then /favicon.ico, the one every site had before <link>
    /// did. SiteIcons fetches the first that loads.
    private static let iconsCall = """
        const found = [];
        for (const link of document.querySelectorAll('link[rel][href]')) {
          const rel = String(link.rel || '').toLowerCase().split(/\\s+/);
          const touch = rel.includes('apple-touch-icon') || rel.includes('apple-touch-icon-precomposed');
          if (!touch && !rel.includes('icon')) continue;
          if (rel.includes('mask-icon')) continue;
          const href = link.href;
          if (!/^(https?:|data:image\\/)/i.test(href)) continue;
          const type = String(link.type || '').toLowerCase();
          const svg = type.includes('svg') || /^data:image\\/svg/i.test(href) || /\\.svg([?#]|$)/i.test(href);
          const sizes = String(link.getAttribute('sizes') || '').toLowerCase().split(/\\s+/);
          const size = Math.min(Math.max(0, ...sizes.map((each) => parseInt(each, 10) || 0)), 512);
          // The site's own icon first, as browsers show it: a drawing, then one
          // for any size (an .ico of several), then its largest picture, then an
          // alternate; Apple's touch icon (a square for a Home Screen) after them,
          // and a speck under 32 pixels after that.
          let score;
          if (touch) score = 1000 + size;
          else if (svg) score = 3000;
          else if (sizes.includes('any')) score = 2600;
          else if (size && size < 32) score = 500 + size;
          else score = (rel.includes('alternate') ? 1500 : 2000) + size;
          // One for a dark screen, or for another kind of screen, after the rest:
          // the icon kept is the one for a light screen.
          const media = String(link.media || '').toLowerCase();
          const scheme = /prefers-color-scheme/.test(media);
          if ((scheme && /prefers-color-scheme:\\s*dark/.test(media)) || (media && !scheme && !window.matchMedia(media).matches)) {
            score -= 2900;
          }
          found.push({ href, score });
        }
        found.sort((a, b) => b.score - a.score);
        const urls = found.map((icon) => icon.href);
        if (/^https?:$/.test(location.protocol)) urls.push(location.origin + '/favicon.ico');
        return Array.from(new Set(urls)).slice(0, 6);
        """

    /// Asks the page for its icons once it has loaded, unless SiteIcons has
    /// the site's already. Never on a hands-off host.
    private func learnIcons() {
        guard let url = view.url, ["http", "https"].contains(url.scheme ?? ""), !HandsOff.covers(url),
              SiteIcons.shared.needs(url) else { return }
        view.callAsyncJavaScript(Self.iconsCall, arguments: [:], in: nil, in: Page.world) { result in
            guard case .success(let value) = result, let strings = value as? [String] else { return }
            SiteIcons.shared.learn(strings.compactMap(URL.init(string:)), for: url)
        }
    }

    /// What the page says it is about (its meta description), for its
    /// history to be found by; never its own text, never on a hands-off host.
    private func learnAbout() {
        guard let url = view.url, ["http", "https"].contains(url.scheme ?? ""), !HandsOff.covers(url) else { return }
        let call = """
            const meta = document.querySelector('meta[name="description" i], meta[property="og:description" i]');
            return meta && meta.content ? String(meta.content).trim().slice(0, 400) : '';
            """
        view.callAsyncJavaScript(call, arguments: [:], in: nil, in: Page.world) { [weak self] result in
            guard let self, case .success(let value) = result, let text = value as? String else { return }
            history.described(text, url: url, space: space)
        }
    }

    // MARK: Another app's link

    fileprivate func openElsewhere(_ url: URL, clicked: Bool, mainFrame: Bool) {
        switch AppLink.answer(clicked: clicked, mainFrame: mainFrame, showing: host?.isShowing(self) == true,
                              asking: askingElsewhere, refusals: refusedElsewhere) {
        case .leave:
            closeIfOpenedForThis()
        case .open:
            hand(url)
        case .ask:
            guard let window = host?.hostWindow else { return }
            let alert = NSAlert()
            let asker = (committed ?? view.url)?.host ?? "This page"
            alert.messageText = "Open in Another App?"
            alert.informativeText = "\(asker) is opening a link for another app (\(url.scheme ?? ""):)."
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            askingElsewhere = true
            alert.beginSheetModal(for: window) { [weak self] answer in
                guard let self else { return }
                askingElsewhere = false
                if answer == .alertFirstButtonReturn {
                    hand(url)
                } else {
                    refusedElsewhere += 1
                    closeIfOpenedForThis()
                }
            }
        }
    }

    /// To whichever app opens it.
    private func hand(_ url: URL) {
        NSWorkspace.shared.open(url)
        closeIfOpenedForThis()
    }

    /// A window a page opened only to go to another app has nothing to
    /// show, and goes, as one that closed itself would.
    private func closeIfOpenedForThis() {
        guard wasOpened, committed == nil else { return }
        host?.pageDidClose(self)
    }

    // MARK: When the page's process ends

    /// The page went blank: loaded again by itself unless it keeps ending,
    /// when it waits for Reload.
    fileprivate func processEnded() {
        if crashes.shouldReload(at: Date()) {
            reload(byHand: false)
        } else {
            exhausted = true
            failure = "This page used too much memory and was closed several times. Reload to try again."
            host?.pageDidChange(self)
        }
    }
}

// MARK: - WebKit's questions

extension Page: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if let url = navigationAction.request.url, AppLink.isOne(scheme: url.scheme) {
            decisionHandler(.cancel)
            openElsewhere(url, clicked: navigationAction.navigationType == .linkActivated, mainFrame: mainFrame)
            return
        }
        if navigationAction.shouldPerformDownload {
            return decisionHandler(.download)
        }
        let choice = newTabChoice(for: navigationAction)
        if choice != .here, let url = navigationAction.request.url,
           host?.page(self, openInNewTab: url, inFront: choice == .inFront) == true {
            return decisionHandler(.cancel)
        }
        if mainFrame { history.decided(navigationAction.navigationType, url: navigationAction.request.url) }
        if mainFrame, let request = askingInLightOrDark(navigationAction) {
            decisionHandler(.cancel)
            webView.load(request)
            return
        }
        if mainFrame { prepare(for: navigationAction.request.url) }
        decisionHandler(.allow)
    }

    /// The request again with the screen's light or dark, for a host that
    /// asks for it as a header and a request without it; nil otherwise. A
    /// step back or a reload goes as it was made, and a hands-off page is
    /// never asked for twice. Notes what the request was, for its answer.
    private func askingInLightOrDark(_ action: WKNavigationAction) -> URLRequest? {
        let request = action.request
        let repeatable = ![.backForward, .reload, .formResubmitted].contains(action.navigationType)
            && (request.httpMethod ?? "GET").uppercased() == "GET" && !HandsOff.covers(request.url)
        hintCarried = ColorSchemeHint.carries(request.allHTTPHeaderFields)
        hintRepeatable = repeatable
        guard repeatable, let value = Self.colorHint.missing(url: request.url, method: request.httpMethod,
                                                             headers: request.allHTTPHeaderFields, dark: isDark)
        else { return nil }
        var again = request
        again.setValue(value, forHTTPHeaderField: ColorSchemeHint.header)
        return again
    }

    private var isDark: Bool {
        view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        // A page from a host that asks for the screen's light or dark, which came light on a dark screen: again, dark.
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse,
           let url = response.url, !HandsOff.covers(url),
           let value = Self.colorHint.answered(url: url, acceptCH: response.value(forHTTPHeaderField: "Accept-CH"),
                                               criticalCH: response.value(forHTTPHeaderField: "Critical-CH"),
                                               requestCarried: hintCarried, repeatable: hintRepeatable, dark: isDark) {
            decisionHandler(.cancel)
            var again = URLRequest(url: url)
            again.setValue(value, forHTTPHeaderField: ColorSchemeHint.header)
            webView.load(again)
            return
        }
        // What WebKit can't show (a ZIP, an installer) and what the server says to save is a download.
        let attachment = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased().hasPrefix("attachment") == true
        decisionHandler(navigationResponse.canShowMIMEType && !attachment ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloading(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloading(download)
    }

    /// A tab that was only ever the file's way in, with no page of its own
    /// to show, goes once the download has begun, as Safari's does.
    private func downloading(_ download: WKDownload) {
        Downloads.shared.adopt(download, from: self)
        if committed == nil, !view.canGoBack { host?.pageDidClose(self) }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        committed = webView.url
        failure = nil
        refusedElsewhere = 0
        history.committed(url: webView.url, title: webView.title, space: space, tab: tab)
        changed()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        learnIcons()
        learnAbout()
        host?.pageDidChange(self)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    /// A load that failed for a reason worth telling: not one that was
    /// stopped, nor one that became a download.
    private func failed(_ error: Error) {
        let error = error as NSError
        let quiet = (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && [102, 204].contains(error.code))
        guard !quiet else { return }
        history.failed()
        failure = error.localizedDescription
        host?.pageDidChange(self)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        processEnded()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Another app's link asked for in a window of its own: theirs to
        // open, with no tab made for a page that will never be.
        if let url = navigationAction.request.url, AppLink.isOne(scheme: url.scheme) {
            openElsewhere(url, clicked: navigationAction.navigationType == .linkActivated,
                          mainFrame: navigationAction.targetFrame?.isMainFrame ?? true)
            return nil
        }
        let made = host?.page(self, open: configuration, for: navigationAction, features: windowFeatures)
        if let child = (made as? PageView)?.page, child !== self {
            child.wasOpened = true
        }
        return made
    }

    func webViewDidClose(_ webView: WKWebView) {
        host?.pageDidClose(self)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page says" : "\(frame.securityOrigin.host) says"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page asks" : "\(frame.securityOrigin.host) asks"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page asks" : "\(frame.securityOrigin.host) asks"
        alert.informativeText = prompt
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    /// An alert on the page's window, or on its own when the page has none on screen.
    private func present(_ alert: NSAlert, _ done: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = host?.hostWindow {
            alert.beginSheetModal(for: window, completionHandler: done)
        } else {
            done(alert.runModal())
        }
    }

    /// A page's upload field: the files chosen in the system's panel, which
    /// the sandbox then lets the page read.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        let done: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window = host?.hostWindow {
            panel.beginSheetModal(for: window, completionHandler: done)
        } else {
            done(panel.runModal())
        }
    }
}
