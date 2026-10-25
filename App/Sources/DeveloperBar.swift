import PadCore
import UIKit

/// The developer bar across a page's top, as the Mac's (Decided 2 and 3):
/// the whole address with its port and the response's status, and the
/// tools' buttons where the window is wide enough — a phone-width
/// window's are in the page's menu instead. One per pane, 28 points tall,
/// 24 on a phone-width window; the page starts under it.
@MainActor
final class DeveloperBar: UIView {
    /// Whether the pane's site has developer mode on, as Settings have it.
    static func isOn(_ page: Page?) -> Bool {
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

    /// What each button runs on the bar's own page.
    var onElementPicture: (() -> Void)?
    var onInspect: (() -> Void)?
    /// The address tapped: the command bar holding it, as the Mac's click.
    var onAddress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        addressLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.isUserInteractionEnabled = true
        addressLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(addressTapped)))
        statusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
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
        } else {
            statusLabel.text = nil
        }
        rawButton?.isHidden = compact || !page.jsonViewShown
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var right = bounds.maxX - 10
        for button in buttons.reversed() where !button.isHidden {
            button.frame = CGRect(x: right - 24, y: 0, width: 24, height: bounds.height)
            right = button.frame.minX - 4
        }
        var status = CGRect.zero
        if statusLabel.text != nil {
            statusLabel.sizeToFit()
            status = CGRect(x: right - statusLabel.bounds.width, y: 0,
                            width: statusLabel.bounds.width, height: bounds.height)
            statusLabel.frame = status
            right = status.minX - 8
        } else {
            statusLabel.frame = .zero
        }
        addressLabel.frame = CGRect(x: 10, y: 0, width: max(0, right - 10), height: bounds.height)
    }

    private func makeButtons() {
        let element = tool("camera.viewfinder", title: String(localized: "Element Screenshot")) { [weak self] in
            self?.onElementPicture?()
        }
        let reload = tool("arrow.clockwise.circle", title: String(localized: "Reload from Origin")) { [weak self] in
            self?.page?.view.reloadFromOrigin()
        }
        let raw = UIButton(type: .system)
        raw.setTitle(String(localized: "Raw"), for: .normal)
        raw.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        raw.addAction(UIAction { [weak self] _ in self?.page?.toggleJSONView() }, for: .touchUpInside)
        rawButton = raw
        let info = tool("info.circle", title: String(localized: "Inspect from Safari on a Mac")) { [weak self] in
            self?.onInspect?()
        }
        buttons = [element, reload, raw, info]
        for button in buttons { addSubview(button) }
    }

    private func tool(_ symbol: String, title: String, run: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = .secondaryLabel
        button.accessibilityLabel = title
        button.addAction(UIAction { _ in run() }, for: .touchUpInside)
        return button
    }

    @objc private func addressTapped() {
        onAddress?()
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
