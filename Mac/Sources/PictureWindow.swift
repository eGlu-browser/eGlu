import AppKit
import PadCore
import WebKit

/// A site's picture-in-picture window (DocumentPicture.swift): the blank
/// page picture.js opened, floating above every window and every app, on
/// every Space and over full-screen apps, as Chrome's does. Google Meet
/// moves its call there when asked, or when its tab is left mid-call.
///
/// The page in it is the site's own, in the opener's process: the site
/// fills it and takes its elements back when it closes, on `pagehide`,
/// which WebKit fires as the web view goes. So the window goes by one way
/// only, `finish`, whoever closes it: its close button, Back to Tab, the
/// site, or the tab that opened it (Page.picture).
///
/// It is the site's to fill, not the app's: no script of the app's, no
/// address bar, nowhere to go but the blank page and its frames. A link in
/// it opens in a tab beside its opener.
@MainActor
final class PictureWindow: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private(set) weak var opener: Page?
    let view: WKWebView
    private let panel: NSPanel
    /// Opened by the app when the tab was left (Page.leftScreen), and so
    /// closed when the tab is back on screen, as Chrome's is.
    var automatic = false
    private var finished = false

    /// The web view for the window picture.js opens, made with WebKit's
    /// `configuration` so the site keeps its hold on the page in it.
    init(opener: Page, configuration: WKWebViewConfiguration, features: WKWindowFeatures, request: DocumentPicture.Request) {
        self.opener = opener
        // None of the opener's scripts: the page in it is the site's to fill.
        configuration.userContentController = WKUserContentController()
        // A call's videos, moved here, play on in a page no one has clicked yet.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        view = PictureView(frame: .zero, configuration: configuration)
        let screen = opener.host?.hostWindow?.screen ?? NSScreen.main
        let room = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = DocumentPicture.size(width: features.width?.doubleValue, height: features.height?.doubleValue, within: room.size)
        panel = PicturePanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        super.init()
        view.navigationDelegate = self
        view.uiDelegate = self
        view.isInspectable = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let host = (opener.committed ?? opener.view.url)?.host() ?? ""
        panel.title = host
        panel.contentMinSize = DocumentPicture.smallest
        panel.contentView = PictureContent(page: view, backToTab: request.returnsToOpener ? backToTabButton() : nil)
        // Where and how big it was last for this site, as Chrome reopens it,
        // unless the site asks for where it first opens. Naming the frame to
        // keep puts a kept one back, so a first place is set again after.
        let name = "Picture \(host)"
        let reopened = !request.initialPlacement && panel.setFrameUsingName(name)
        let first = NSRect(origin: DocumentPicture.origin(for: panel.frame.size, in: room), size: panel.frame.size)
        panel.setFrameAutosaveName(name)
        if !reopened { panel.setFrame(first, display: false) }
        // In front, without taking the keys from the window or app in use.
        panel.orderFrontRegardless()
    }

    /// Back to Tab, as Chrome's window has: in the page's top corner while
    /// the pointer is over the window, as macOS's own picture-in-picture
    /// window shows its controls. Not in the title bar: in Safience, drawn in
    /// Liquid Glass on macOS 27, the system's title bar covered whatever was
    /// added there (an accessory, a subview, a bar of the window's own under
    /// a see-through title bar), though AppKit laid it out and drew it.
    private func backToTabButton() -> NSButton {
        let image = NSImage(systemSymbolName: "pip.exit", accessibilityDescription: "Back to Tab") ?? NSImage()
        let button = NSButton(image: image, target: self, action: #selector(backToTab))
        button.isBordered = false
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.layer?.cornerRadius = 7
        button.toolTip = "Back to Tab"
        button.setAccessibilityLabel("Back to Tab")
        return button
    }

    /// The tab that opened the window, in front, and the window gone, as in Chrome.
    @objc private func backToTab() {
        if let opener { Self.show(opener.tab, of: opener.space) }
        close()
    }

    /// The tab on screen: in the window showing it, or one showing its
    /// space, or the window in front; in a new window when none is open.
    private static func show(_ tab: UUID, of space: UUID) {
        let session = Session.shared
        NSApp.activate()
        guard let window = session.window(showing: tab) ?? session.allWindows.first(where: { $0.spaceID == space })
                ?? session.frontWindow
        else {
            session.change { $0.select(tab) }
            session.openWindow?(space)
            return
        }
        window.select(tab)
        window.window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.close()
    }

    /// The one way the window goes. The web view goes with it, and WebKit
    /// fires `pagehide` in its page as it does, for the site to take its
    /// elements home.
    private func finish() {
        guard !finished else { return }
        finished = true
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.removeFromSuperview()
        panel.contentView = nil
        panel.delegate = nil
        // The panel is in the middle of closing, and the opener lets go of
        // this window now: the panel is held until its close has run.
        let panel = self.panel
        DispatchQueue.main.async { withExtendedLifetime(panel) {} }
        opener?.pictureDidClose(self)
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }

    // MARK: The page in it

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // Its frames go where they like; the window itself stays on its blank page.
        guard navigationAction.targetFrame?.isMainFrame ?? true else { return decisionHandler(.allow) }
        let url = navigationAction.request.url
        if url?.scheme?.lowercased() == "about" { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        if let url { openBesideOpener(url) }
    }

    /// A link in the window asking for a window of its own: a tab beside the opener's.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { openBesideOpener(url) }
        return nil
    }

    private func openBesideOpener(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let opener else { return }
        // The opener's window, or with its tab off screen, the window in front;
        // with no window open, Safience opens it as it would a link from another app.
        NSApp.activate()
        guard let host: PageHost = opener.host ?? Session.shared.frontWindow else { return Session.shared.open([url]) }
        _ = host.page(opener, openInNewTab: url, inFront: true)
    }

    /// The site closed it (`pipWindow.close()`).
    func webViewDidClose(_ webView: WKWebView) {
        close()
    }

    /// The opener's process ended, and this page with it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        close()
    }
}

/// The window's panel: takes the keys when clicked, for a call's chat,
/// without bringing Safience in front of the app in use.
private final class PicturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The window's content: the site's page, and Back to Tab over its top
/// corner while the pointer is in the window.
private final class PictureContent: NSView {
    private let backToTab: NSButton?

    init(page: WKWebView, backToTab: NSButton?) {
        self.backToTab = backToTab
        super.init(frame: .zero)
        page.translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        var constraints = [
            page.topAnchor.constraint(equalTo: topAnchor),
            page.leadingAnchor.constraint(equalTo: leadingAnchor),
            page.trailingAnchor.constraint(equalTo: trailingAnchor),
            page.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        if let backToTab {
            backToTab.translatesAutoresizingMaskIntoConstraints = false
            backToTab.alphaValue = 0
            backToTab.isHidden = true
            addSubview(backToTab)
            constraints += [
                backToTab.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                backToTab.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                backToTab.widthAnchor.constraint(equalToConstant: 30),
                backToTab.heightAnchor.constraint(equalToConstant: 24),
            ]
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { show(true) }
    override func mouseExited(with event: NSEvent) { show(false) }

    /// Shown, or faded out and then hidden, so a click on the page's corner
    /// never lands on a button that can't be seen.
    private func show(_ shown: Bool) {
        guard let backToTab else { return }
        if shown { backToTab.isHidden = false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            backToTab.animator().alphaValue = shown ? 1 : 0
        } completionHandler: {
            if !shown, backToTab.alphaValue == 0 { backToTab.isHidden = true }
        }
    }
}

/// The window's web view: a click on a button in it works the first time,
/// with Safience behind another app, as the controls of a call must.
private final class PictureView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
