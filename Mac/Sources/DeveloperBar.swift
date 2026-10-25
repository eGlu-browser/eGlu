import PadCore
import SwiftUI
import WebKit

/// The developer bar across a page's top, as Arc's own bar: the whole
/// address with its port, the response's status, and the tools' buttons.
/// One per page's card, shown while the site has developer mode on
/// (DeveloperMode.isOn); its commands act on the card's own page, so the
/// bar on the page beside acts on that page.
struct DeveloperBar: View {
    @ObservedObject var model: WindowModel
    let tab: UUID?
    let page: Page
    let focused: Bool

    /// Where the card's page is, with what it is loading while one goes.
    private var address: URL? {
        focused ? model.url : (page.displayURL ?? page.view.url)
    }

    private var statusCode: Int? {
        focused ? model.statusCode : page.statusCode
    }

    /// Whether the card's page has developer mode on, as the window's
    /// settings have it (a choice on either site repaints both bars).
    static func isOn(_ page: Page?, url: URL?) -> Bool {
        let preferences = Session.shared.preferences
        return DeveloperMode.isOn(url ?? page?.displayURL ?? page?.view.url,
                                  choices: preferences.developerSites, local: preferences.developerLocal)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let address {
                addressText(address)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
                    .onTapGesture {
                        if let tab, !focused { model.focus(pane: tab) }
                        model.commandBar = .here
                    }
            }
            Spacer(minLength: 4)
            if let code = statusCode {
                Text(verbatim: String(code))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Self.color(for: code))
            }
            buttons
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        // The bar's page is the card's, not the window's: its buttons act
        // on it through Page and WebKit's own calls, never on the window's.
        .environment(\.openURL, OpenURLAction { _ in .handled })
    }

    /// The address whole: scheme, host, the port in the accent colour, and
    /// the path and query, as the Decided bar has it.
    private func addressText(_ url: URL) -> Text {
        var text = Text(verbatim: "\(url.scheme ?? "")://")
        var host = url.host() ?? ""
        if host.hasPrefix("[") == false, host.contains(":") { host = "[\(host)]" }
        text = text + Text(verbatim: host)
        if let port = url.port {
            text = text + Text(verbatim: ":\(port)").foregroundStyle(Color.accentColor)
        }
        let tail = (url.path().isEmpty || url.path() == "/" ? "" : url.path())
            + (url.query().map { "?" + $0 } ?? "")
            + (url.fragment().map { "#" + $0 } ?? "")
        return text + Text(verbatim: tail)
    }

    /// 2xx green, 3xx grey, 4xx orange, 5xx red.
    private static func color(for code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .secondary
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .secondary
        }
    }

    @ViewBuilder
    private var buttons: some View {
        button(.inspector) { act(.inspector) }
        button(.console) { act(.console) }
        button(.selectElement) { act(.selectElement) }
        button(.elementPicture) { act(.elementPicture) }
        button(.reloadOrigin) { act(.reloadOrigin) }
        // The tool's button pressed again ends it, as ⌃⌥M does.
        button(.measure) { act(.measure) }
        sizeMenu
        // Raw, on a page the JSON view is drawn over (Page.jsonViewShown).
        if page.jsonViewShown {
            Button(String(localized: "Raw")) { page.toggleJSONView() }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func button(_ command: Command, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: command.symbol)
                .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(command.macTitle + (WindowModel.keys(for: command).map { " \($0)" } ?? ""))
    }

    /// The page at a device's size with its user agent (Decided 9):
    /// iPhone 393 by 852, iPad 820 by 1180, Full as the card is.
    private var sizeMenu: some View {
        Menu {
            Button(String(localized: "Full")) { page.size(nil, pad: false) }
            Button(String(localized: "iPhone")) { page.size(Self.iPhone, pad: false) }
            Button(String(localized: "iPad")) { page.size(Self.iPad, pad: true) }
        } label: {
            Image(systemName: "iphone")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help(String(localized: "Size"))
    }

    private static let iPhone = CGSize(width: 393, height: 852)
    private static let iPad = CGSize(width: 820, height: 1180)

    /// The card's page is what each button works on, focused or not.
    private func act(_ command: Command) {
        switch command {
        case .inspector: inspector(.inspector)
        case .console: inspector(.console)
        case .selectElement: inspector(.elements)
        case .elementPicture: elementPicture()
        case .reloadOrigin: page.view.reloadFromOrigin()
        // On the card's own page, as the rest: the page beside's too.
        case .measure: page.toggleMeasuring()
        default: model.perform(command)
        }
    }

    private func inspector(_ part: WebInspector.Part) {
        if !WebInspector.show(part, for: page.view) {
            model.show(ActionToast(symbol: "hammer", text: WebInspector.unavailable))
        }
    }

    /// The card's own page gives up an element's picture, as the window's
    /// command does on its page (WindowModel.elementPicture).
    private func elementPicture() {
        let model = self.model
        Task { @MainActor [page] in
            guard let picked = await page.pickElement(),
                  let image = await page.picture(of: picked),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
            let board = NSPasteboard.general
            board.clearContents()
            board.setData(png, forType: .png)
            model.show(ActionToast(symbol: "camera.viewfinder", text: String(localized: "Picture copied"),
                                   action: (title: String(localized: "Save"), run: { WindowModel.saveElementPicture(png) })))
        }
    }
}
