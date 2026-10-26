import PadCore
import UIKit

/// The developer bar across a page's top, as the Mac's (Decided 2 and 3):
/// the whole address with its port and the response's status, and the
/// tools' buttons where the window is wide enough; a phone-width
/// window's are in the page's menu instead. One per pane, 28 points tall,
/// 24 on a phone-width window; the page starts under it.
@MainActor
final class DeveloperBar: UIView, UIContextMenuInteractionDelegate {
    /// Whether the pane's site has developer mode on, as Settings have it.
    static func isOn(_ page: Page?) -> Bool {
        // The Mac's and the iPad's: an iPhone has no developer mode.
        guard !Device.phone else { return false }
        let preferences = Session.shared.preferences
        return DeveloperMode.isOn(page?.displayURL ?? page?.view.url,
                                  choices: preferences.developerSites, local: preferences.developerLocal)
    }

    /// The pane's own page; the bar's buttons act on it, whichever is focused.
    private(set) weak var page: Page?
    /// Address and status only, on a phone-width window.
    private(set) var compact = false

    private let addressLabel = UILabel()
    private let statusLabel = UILabel()
    private var buttons: [UIButton] = []
    private var rawButton: UIButton?
    private var measureButton: UIButton?
    /// Hairlines between the buttons' groups: before each that starts one.
    private var groupStarts: Set<ObjectIdentifier> = []
    private var hairlines: [UIView] = []

    /// What each button runs on the bar's own page.
    var onElementPicture: (() -> Void)?
    var onMeasure: (() -> Void)?
    var onInspect: (() -> Void)?
    /// Developer mode off for the bar's page's site, from the address's menu.
    var onTurnOff: (() -> Void)?
    /// The address tapped: the command bar holding it, as the Mac's click.
    var onAddress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        addressLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.isUserInteractionEnabled = true
        addressLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(addressTapped)))
        // A tap types a new address, as on the Mac; VoiceOver says so, and a
        // long press copies the address as it is, whole.
        addressLabel.accessibilityTraits = .button
        addressLabel.addInteraction(UIContextMenuInteraction(delegate: self))
        statusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        statusLabel.textAlignment = .center
        // On a pill of its own colour, faint, as the Mac's bar has it.
        statusLabel.layer.cornerRadius = 8
        statusLabel.layer.cornerCurve = .continuous
        statusLabel.clipsToBounds = true
        addSubview(addressLabel)
        addSubview(statusLabel)
        autoresizesSubviews = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The pane's page and whether the window is phone-width: the buttons
    /// leave a compact bar, as the page's menu has them there.
    func show(_ page: Page, compact: Bool) {
        self.page = page
        self.compact = compact
        if buttons.isEmpty { makeButtons() }
        for button in buttons { button.isHidden = compact }
        refresh()
    }

    /// The page's address and status anew, as it loads and goes.
    func refresh() {
        guard let page else { return }
        addressLabel.attributedText = Self.address(page.displayURL ?? page.view.url)
        if let code = page.statusCode {
            statusLabel.text = String(code)
            statusLabel.textColor = Self.color(for: code)
            statusLabel.backgroundColor = Self.color(for: code).withAlphaComponent(0.14)
        } else {
            statusLabel.text = nil
        }
        // Raw, while the page has a JSON view: selected while it shows the
        // page's own text, the way back to the view.
        rawButton?.isHidden = compact || page.jsonView == nil
        rawButton?.isSelected = page.jsonView == false
        // Measure in the accent colour, on a faint chip of it, while it runs on the bar's page.
        let measuring = page.measure != nil
        measureButton?.tintColor = measuring ? .tintColor : .secondaryLabel
        measureButton?.backgroundColor = measuring ? UIColor.tintColor.withAlphaComponent(0.14) : .clear
        measureButton?.accessibilityTraits = measuring ? [.button, .selected] : .button
        // What it shows changes the room each part takes.
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var right = bounds.maxX - 4
        var lines = 0
        let height = min(bounds.height - 4, 22)
        for button in buttons.reversed() where !button.isHidden {
            // Raw's word as wide as it is in the person's language.
            let width = button === rawButton ? button.intrinsicContentSize.width + 12 : 28
            button.frame = CGRect(x: right - width, y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
            right = button.frame.minX - 1
            if groupStarts.contains(ObjectIdentifier(button)) {
                if lines == hairlines.count {
                    let line = UIView()
                    line.backgroundColor = .separator
                    addSubview(line)
                    hairlines.append(line)
                }
                hairlines[lines].isHidden = false
                hairlines[lines].frame = CGRect(x: right - 4, y: ((bounds.height - 14) / 2).rounded(), width: 1, height: 14)
                right -= 8
                lines += 1
            }
        }
        for line in hairlines.dropFirst(lines) { line.isHidden = true }
        var status = CGRect.zero
        if statusLabel.text != nil {
            statusLabel.sizeToFit()
            status = CGRect(x: right - statusLabel.bounds.width - 12, y: ((bounds.height - 16) / 2).rounded(),
                            width: statusLabel.bounds.width + 12, height: 16)
            statusLabel.frame = status
            right = status.minX - 8
        } else {
            statusLabel.frame = .zero
        }
        addressLabel.frame = CGRect(x: 10, y: 0, width: max(0, right - 10), height: bounds.height)
    }

    private func makeButtons() {
        let element = tool(Command.elementPicture.symbol, title: Command.elementPicture.title) { [weak self] in
            self?.onElementPicture?()
        }
        let reload = tool(Command.reloadOrigin.symbol, title: Command.reloadOrigin.title) { [weak self] in
            self?.page?.view.reloadFromOrigin()
        }
        // The tool's button pressed again ends it, as ⌃⌥M does.
        let measure = tool(Command.measure.symbol, title: Command.measure.title) { [weak self] in
            self?.onMeasure?()
        }
        measureButton = measure
        let raw = UIButton(type: .system)
        raw.setTitle(String(localized: "Raw"), for: .normal)
        raw.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        raw.addAction(UIAction { [weak self] _ in self?.page?.toggleJSONView() }, for: .touchUpInside)
        rawButton = raw
        let info = tool("info.circle", title: String(localized: "Inspect from Safari on a Mac")) { [weak self] in
            self?.onInspect?()
        }
        // In groups, a hairline before each: the page's own tools, the page reloaded, what it is.
        buttons = [element, measure, reload, raw, info]
        groupStarts = [ObjectIdentifier(reload), ObjectIdentifier(info)]
        for button in buttons {
            button.layer.cornerRadius = 6
            button.layer.cornerCurve = .continuous
            addSubview(button)
        }
    }

    private func tool(_ symbol: String, title: String, run: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)),
                        for: .normal)
        button.tintColor = .secondaryLabel
        button.accessibilityLabel = title
        button.addAction(UIAction { _ in run() }, for: .touchUpInside)
        return button
    }

    @objc private func addressTapped() {
        onAddress?()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let url = page?.displayURL ?? page?.view.url else { return nil }
        // The site's switch is here too, rather than a button of its own.
        let off = onTurnOff
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Copy Address"), image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = url.absoluteString
                },
                UIAction(title: String(localized: "Turn Developer Mode Off for This Site"),
                         image: UIImage(systemName: Command.developerMode.symbol)) { _ in off?() },
            ])
        })
    }

    /// The address whole: scheme, host, the port in the accent colour, and
    /// the path and query, as the Decided bar has it.
    private static func address(_ url: URL?) -> NSAttributedString {
        guard let url else { return NSAttributedString() }
        var host = url.host() ?? ""
        if host.hasPrefix("[") == false, host.contains(":") { host = "[\(host)]" }
        let tail = (url.path().isEmpty || url.path() == "/" ? "" : url.path())
            + (url.query().map { "?" + $0 } ?? "")
            + (url.fragment().map { "#" + $0 } ?? "")
        let text = NSMutableAttributedString(string: "\(url.scheme ?? "")://\(host)")
        if let port = url.port {
            text.append(NSAttributedString(string: ":\(port)", attributes: [.foregroundColor: UIColor.tintColor]))
        }
        text.append(NSAttributedString(string: tail))
        return text
    }

    /// 2xx green, 3xx grey, 4xx orange, 5xx red.
    private static func color(for code: Int) -> UIColor {
        switch code {
        case 200..<300: return .systemGreen
        case 300..<400: return .secondaryLabel
        case 400..<500: return .systemOrange
        case 500..<600: return .systemRed
        default: return .secondaryLabel
        }
    }
}
