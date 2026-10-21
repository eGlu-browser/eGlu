import AppKit
import PadCore
import SwiftUI
import WebKit

/// An extension's own page beside a website's: its popup or its side panel,
/// each in a view made from the extension's configuration, as Search's are
/// (its ExtensionPopup.swift): WebKit's own popup loses messages to the
/// worker for some extensions. To WebKit each is a tab of the space's
/// window at no place in its row, as Chrome puts a popup, since WebKit
/// carries a page's messages only when it can name the tab it is in.
@MainActor
final class ExtensionSurface: NSObject, WKWebExtensionTab, WKUIDelegate, WKNavigationDelegate {
    let extensionID: String
    let space: UUID
    let web: WKWebView
    weak var context: WKWebExtensionContext?
    /// The page asked to go: window.close(), or a link out of it.
    var onClose: (() -> Void)?

    /// Nil unless `url` is the extension's own: no site is ever loaded here.
    init?(_ url: URL, for context: WKWebExtensionContext, in space: UUID) {
        guard url.scheme == Extensions.scheme, url.host() == context.uniqueIdentifier,
              let configuration = context.webViewConfiguration else { return nil }
        extensionID = context.uniqueIdentifier
        self.space = space
        self.context = context
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 25, height: 25), configuration: configuration)
        super.init()
        web.uiDelegate = self
        web.navigationDelegate = self
        web.isInspectable = true
        // White behind the page, as Chrome paints a popup: many leave their
        // background unset, and their dark text over glass would vanish.
        web.underPageBackgroundColor = .white
        context.webExtensionController?.didOpenTab(self)
        web.load(URLRequest(url: url))
    }

    func close() {
        context?.webExtensionController?.didCloseTab(self, windowIsClosing: false)
        web.navigationDelegate = nil
        web.uiDelegate = nil
        web.stopLoading()
    }

    // MARK: Chrome's measure of a popup (Search's)

    /// The size Chrome would give the popup (Blink's auto-size, between
    /// 25 × 25 and 800 × 600), worked out in the page while its view is
    /// still the 25-point square: the width the page names for itself if it
    /// names one, else its narrowest (min-content), else, for a page with
    /// next to no width of its own, what its content spans; then, laid out
    /// at that width, the height it names or spans. Nothing of it is left
    /// on the page.
    static let preferred = """
    (() => {
      const d = document.documentElement;
      if (!d) return null;
      const m = window.__safienceSizing || (window.__safienceSizing = {});
      const saved = d.getAttribute("style");
      const back = () => saved === null ? d.removeAttribute("style") : d.setAttribute("style", saved);
      const box = d.getBoundingClientRect();
      let w;
      if (Math.abs(box.width - innerWidth) > 1) w = m.w = box.width;
      else if (m.w && Math.abs(m.w - innerWidth) <= 1) w = m.w;
      else {
        d.style.setProperty("width", "min-content", "important");
        const narrowest = d.getBoundingClientRect().width;
        back();
        w = narrowest >= 100 ? narrowest : Math.max(narrowest, d.scrollWidth);
      }
      w = Math.min(800, Math.max(25, Math.ceil(w)));
      d.style.setProperty("width", w + "px", "important");
      let h = d.getBoundingClientRect().height;
      if (Math.abs(h - innerHeight) > 1) m.h = h;
      else if (m.h && Math.abs(m.h - innerHeight) <= 1) h = m.h;
      else {
        d.style.setProperty("height", "auto", "important");
        d.style.setProperty("min-height", "0", "important");
        h = d.getBoundingClientRect().height;
      }
      back();
      return [w, Math.min(600, Math.max(25, Math.ceil(h)))];
    })()
    """

    /// The page's own measure of itself, nil until it has one.
    func measure() async -> NSSize? {
        guard let pair = try? await web.evaluateJavaScript(Self.preferred) as? [Double], pair.count == 2 else { return nil }
        return NSSize(width: pair[0], height: pair[1])
    }

    // MARK: The page asking

    func webViewDidClose(_ webView: WKWebView) { onClose?() }

    /// A link that asks for a new window becomes a tab, and the surface
    /// goes, as a popup does in Chrome when you follow a link out of it.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, ["http", "https"].contains(url.scheme ?? ""), let context {
            _ = Extensions.shared.tabs.open(url, in: space, active: true, pinned: false, context: context)
        }
        onClose?()
        return nil
    }

    // Its page stays the extension's: a site loaded here would run with the
    // extension's configuration.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != false else { return decisionHandler(.allow) }
        let to = navigationAction.request.url
        if to?.scheme == Extensions.scheme, to?.host() == extensionID { return decisionHandler(.allow) }
        if let to, ["http", "https"].contains(to.scheme ?? ""), let context {
            _ = Extensions.shared.tabs.open(to, in: space, active: true, pinned: false, context: context)
        }
        decisionHandler(.cancel)
    }

    // No camera or microphone from a popup or a panel yet.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    // MARK: As WebKit's tab

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { Extensions.shared.tabs.window(for: space) }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { NSNotFound }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { web }
    func title(for context: WKWebExtensionContext) -> String? { web.title }
    func url(for context: WKWebExtensionContext) -> URL? { web.url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !web.isLoading }
    func isSelected(for context: WKWebExtensionContext) -> Bool { false }
    func close(for context: WKWebExtensionContext) async throws { onClose?() }
}

/// The popups up, one a window at most, as Chrome has one at a time.
@MainActor
final class ExtensionPopups: ObservableObject {
    static let shared = ExtensionPopups()

    final class Popup: ObservableObject, Identifiable {
        let id = UUID()
        let surface: ExtensionSurface
        let name: String
        let icon: NSImage?
        /// Its size, as the page measures itself; nil until it has, unseen till then.
        @Published var size: NSSize?
        /// How often it has been measured.
        var ticks = 0

        init(surface: ExtensionSurface, name: String, icon: NSImage?) {
            self.surface = surface
            self.name = name
            self.icon = icon
        }
    }

    @Published private(set) var shown: [ObjectIdentifier: Popup] = [:]
    private var measuring: [ObjectIdentifier: Timer] = [:]
    /// Each extension's last size, so the next opening starts there.
    private var lastSize: [String: NSSize] = [:]

    func popup(in window: WindowModel) -> Popup? { shown[ObjectIdentifier(window)] }

    /// Whether `id`'s popup is up in the window: a click on its button then closes it.
    func isUp(_ id: String, in window: WindowModel) -> Bool { popup(in: window)?.surface.extensionID == id }

    func show(_ url: URL, for context: WKWebExtensionContext, in window: WindowModel) {
        close(in: window)
        guard let surface = ExtensionSurface(url, for: context, in: window.spaceID) else { return }
        let key = ObjectIdentifier(window)
        let package = context.webExtension
        let popup = Popup(surface: surface, name: package.displayName ?? context.uniqueIdentifier,
                          icon: package.icon(for: CGSize(width: 32, height: 32)))
        surface.onClose = { [weak self, weak window] in
            guard let self, let window, self.shown[key] === popup else { return }
            self.close(in: window)
        }
        shown[key] = popup
        // Measured as it loads, then for as long as it is up: for its first
        // two seconds it follows the page either way, then it only grows,
        // so a page that settles doesn't set it rocking. Shown when first
        // measured, or after a moment regardless.
        let id = context.uniqueIdentifier
        measuring[key] = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak popup] _ in
            MainActor.assumeIsolated {
                guard let self, let popup else { return }
                popup.ticks += 1
                let ticks = popup.ticks
                Task {
                    guard let found = await popup.surface.measure() else {
                        if ticks >= 12, popup.size == nil { popup.size = self.lastSize[id] ?? NSSize(width: 360, height: 240) }
                        return
                    }
                    let now = popup.size
                    let size = ticks <= 8 || now == nil ? found
                        : NSSize(width: max(now!.width, found.width), height: max(now!.height, found.height))
                    if now.map({ abs($0.width - size.width) > 2 || abs($0.height - size.height) > 2 }) ?? true {
                        popup.size = size
                        self.lastSize[id] = size
                    }
                }
            }
        }
    }

    func close(in window: WindowModel) {
        let key = ObjectIdentifier(window)
        measuring.removeValue(forKey: key)?.invalidate()
        guard let popup = shown.removeValue(forKey: key) else { return }
        popup.surface.close()
    }

    /// Every popup of an extension, when it unloads, or of a space.
    func closeAll(of id: String? = nil, in space: UUID? = nil) {
        for window in Session.shared.allWindows {
            guard let popup = popup(in: window) else { continue }
            if (id == nil || popup.surface.extensionID == id) && (space == nil || popup.surface.space == space) { close(in: window) }
        }
    }
}

/// The popup as a pane of glass at the page's corner, as Handoff's stands
/// (HandoffPanel): the extension's icon and name over it, and its × to put
/// it away; Esc, another tab or another space puts it away too.
struct ExtensionPopupPane: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var popups = ExtensionPopups.shared

    var body: some View {
        if let popup = popups.popup(in: model) {
            PopupPaneBody(popup: popup) { popups.close(in: model) }
                .id(popup.id)
                .onChange(of: model.tabID) { _, _ in popups.close(in: model) }
                .onChange(of: model.spaceID) { _, _ in popups.close(in: model) }
                .transition(.offset(y: -12).combined(with: .opacity))
        }
    }
}

private struct PopupPaneBody: View {
    @ObservedObject var popup: ExtensionPopups.Popup
    let close: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HandoffGuide.corner, style: .continuous)
        let size = popup.size ?? NSSize(width: 25, height: 25)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let icon = popup.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(popup.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PlainIconStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .accessibilityLabel("Close \(popup.name)")
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            SurfaceView(web: popup.surface.web)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding([.horizontal, .bottom], 8)
                // Unseen until it has measured itself, as Chrome shows a popup.
                .opacity(popup.size == nil ? 0 : 1)
        }
        .frame(minWidth: 220, alignment: .leading)
        .fixedSize()
        .clipShape(shape)
        .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.75)), in: shape)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .animation(.bar, value: popup.size)
    }
}

/// An extension's page view, as it is: the surface owns it.
struct SurfaceView: NSViewRepresentable {
    let web: WKWebView

    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
