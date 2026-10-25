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

    /// The bar's height: the page under it is that much shorter, and what
    /// stands at the card's top (the toast, the find bar) goes below it.
    static let height: CGFloat = 28

    /// Whether the card at the pages' top `edge` has the bar: what stands
    /// at that corner over the pages (the toast, an extension's popup) goes
    /// below it, off the bar's address and buttons.
    static func isOn(at edge: HorizontalEdge, in model: WindowModel) -> Bool {
        var page = model.page
        if let split = model.split, let partner = model.partner,
           (edge == .leading ? split.left : split.right) != model.tabID {
            page = partner
        }
        return isOn(page, url: page === model.page ? model.url : nil)
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
                    .onTapGesture(perform: type)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { type() }
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
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        // The bar's page is the card's, not the window's: its buttons act
        // on it through Page and WebKit's own calls, never on the window's.
        .environment(\.openURL, OpenURLAction { _ in .handled })
    }

    /// A click on the address: the command bar, holding it, for the card's page.
    private func type() {
        if let tab, !focused { model.focus(pane: tab) }
        model.commandBar = .here
    }

    /// The address whole: scheme, host, the port in the accent colour, and
    /// the path and query, as the Decided bar has it. One attributed string,
    /// so the address is never a key to look up in the String Catalog.
    private func addressText(_ url: URL) -> Text {
        var host = url.host() ?? ""
        if host.hasPrefix("[") == false, host.contains(":") { host = "[\(host)]" }
        var text = AttributedString("\(url.scheme ?? "")://\(host)")
        if let port = url.port {
            var colon = AttributedString(":\(port)")
            colon.swiftUI.foregroundColor = .accentColor
            text += colon
        }
        let tail = (url.path().isEmpty || url.path() == "/" ? "" : url.path())
            + (url.query().map { "?" + $0 } ?? "")
            + (url.fragment().map { "#" + $0 } ?? "")
        text += AttributedString(tail)
        return Text(text)
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
        .help(WindowModel.keys(for: command).map { String(localized: "\(command.macTitle) (\($0))") } ?? command.macTitle)
        .accessibilityLabel(command.macTitle)
    }

    /// The card's page is what each button works on, focused or not.
    private func act(_ command: Command) {
        switch command {
        case .inspector: inspector(.inspector)
        case .console: inspector(.console)
        case .selectElement: inspector(.elements)
        case .elementPicture: elementPicture()
        case .reloadOrigin: page.view.reloadFromOrigin()
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
