import PadCore
import SwiftUI
import UIKit

// A pinned tab on the phone: its button, before the address on the phone bar
// and on the iPhone Duo's strip above the page's menu, while the tab on
// screen is pinned; and the panel the button opens. A tap has the tab's
// options. Held a moment, or moved up or down at once, it has the space's
// pinned tabs, a highlight following the finger from one to the next and
// letting go going there, as a menu held open is used. Lifted without
// going anywhere, the list stays for a tap.
//
// Motion: the panel grows out of the button (scale 0.9 to 1 about the
// button, its glass materialising) on a critically damped spring of 0.28
// seconds, and goes back into it faster, in 0.15 seconds, easing out. The
// highlight moves between rows on a 0.2 second spring, a selection tick
// with each row it reaches. The button gives to 0.96 under the finger.
// Under Reduce Motion nothing scales or moves: the glass and the rows fade.

/// What the phone shows of a pinned tab.
@MainActor
enum Pinned {
    /// Open: its page is loaded, or it has gone on from the address it was
    /// pinned with. Closed: back at that address with its page let go, as
    /// closing a pinned tab leaves it (Workspace.closeTab).
    static func isOpen(_ tab: TabRecord) -> Bool {
        tab.isPinned && (Session.shared.pages.isLive(tab.id) || (tab.url != nil && tab.url != tab.pinned))
    }

    /// The space's pinned tabs as the dock has them: without those this device hides.
    static func tabs(in space: UUID) -> [TabRecord] {
        let session = Session.shared
        return (session.workspace.space(space)?.tabs ?? []).filter { $0.isPinned && session.preferences.shows($0) }
    }
}

// MARK: The press

/// A press on a pinned tab's button. A tap; or, held a moment or moved up
/// or down at once, the list of pinned tabs, which then follows the finger
/// until it lifts. Moved sideways first, it lets go, and the phone bar's
/// swipe to the tab beside has the touch.
final class PinnedPress: UIGestureRecognizer {
    enum Event {
        case down
        case tap
        /// The list opens, the finger where it is, in the window.
        case hold(CGPoint)
        case move(CGPoint)
        case lift(CGPoint)
        case cancel
    }

    var handle: ((Event) -> Void)?
    /// The list is open and follows the finger.
    private(set) var holding = false
    private var start = CGPoint.zero
    private var timer: Timer?

    /// How long a press is held before the list opens: less than a context
    /// menu's half second, as the keyboard's accents are, for a list used
    /// several times a day.
    static let hold: TimeInterval = 0.35
    /// How far a finger goes before it means to.
    static let slop: CGFloat = 10

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard numberOfTouches == 1, let touch = touches.first else {
            if holding { return }
            state = .failed
            return
        }
        start = touch.location(in: nil)
        handle?(.down)
        let timer = Timer(timeInterval: Self.hold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.open(at: nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let point = touches.first?.location(in: nil) else { return }
        if holding {
            state = .changed
            handle?(.move(point))
            return
        }
        let (dx, dy) = (point.x - start.x, point.y - start.y)
        guard hypot(dx, dy) > Self.slop, state == .possible else { return }
        if abs(dy) > abs(dx) {
            // Up or down at once: the list, without waiting for the hold.
            open(at: point)
        } else {
            timer?.invalidate()
            state = .failed
            handle?(.cancel)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.invalidate()
        let point = touches.first?.location(in: nil) ?? start
        if holding {
            state = .ended
            handle?(.lift(point))
        } else if state == .possible {
            state = .ended
            handle?(.tap)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.invalidate()
        state = holding ? .cancelled : .failed
        handle?(.cancel)
    }

    override func reset() {
        super.reset()
        timer?.invalidate()
        timer = nil
        holding = false
    }

    private func open(at point: CGPoint?) {
        guard state == .possible, !holding else { return }
        timer?.invalidate()
        holding = true
        state = .began
        handle?(.hold(point ?? start))
    }
}

/// Where the phone bar's pinned button (PinnedButton) takes its touches,
/// and says when it is pressed.
class PinnedTouchView: UIView {
    weak var control: PinnedControl? {
        didSet { if control !== oldValue { control?.button = self } }
    }
    var pressed: ((Bool) -> Void)?
    let press = PinnedPress()

    override init(frame: CGRect) {
        super.init(frame: frame)
        press.handle = { [weak self] in self?.handle($0) }
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func handle(_ event: PinnedPress.Event) {
        switch event {
        case .down:
            pressed?(true)
            control?.prepare()
        case .tap:
            pressed?(false)
            control?.showOptions(from: self)
        case .hold(let point):
            control?.showList(from: self, at: point)
        case .move(let point):
            control?.scrub(to: point)
        case .lift(let point):
            pressed?(false)
            control?.release(at: point)
        case .cancel:
            pressed?(false)
            control?.pressCancelled()
        }
    }
}

/// The phone bar's pinned button: the tab's site icon on a disc of glass,
/// as the page's menu (…) is drawn at the other end.
struct PinnedButton: View {
    let tab: TabRecord
    let window: WindowModel
    let act: (BarAction) -> Void
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PinnedDisc(url: tab.url ?? tab.pinned)
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: pressed)
            .overlay { PinnedTouch(control: window.pinned) { pressed = $0 } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pinned Tab, \(tab.label)")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows its options. Its actions go to the other pinned tabs.")
            .accessibilityAction { window.pinned?.showOptions(from: nil) }
            .accessibilityActions {
                ForEach(Pinned.tabs(in: window.spaceID).filter { $0.id != tab.id }) { other in
                    Button("Go to \(other.label)") { act(.select(other.id)) }
                }
            }
    }
}

/// A pinned tab's icon on its disc: the button, and the same drawn alone in
/// the row a sideways drag brings in.
struct PinnedDisc: View {
    let url: URL?

    var body: some View {
        SiteIconView(url: url, size: 22)
            .frame(width: 44, height: 44)
            .liquidGlass(in: Circle(), otherwise: Palette.wash)
    }
}

private struct PinnedTouch: UIViewRepresentable {
    let control: PinnedControl?
    let pressed: (Bool) -> Void

    func makeUIView(context: Context) -> PinnedTouchView {
        let view = PinnedTouchView()
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: PinnedTouchView, context: Context) {
        view.control = control
        view.pressed = pressed
    }
}

// MARK: The control

/// A window's pinned button and its panel: which panel opens, where, and
/// what letting go of it does. One a window, whichever button pressed it.
@MainActor
final class PinnedControl {
    private let window: WindowModel
    private let act: (BarAction) -> Void
    /// Where the panel is put: over everything of the window, the strip too.
    private let host: () -> UIView?
    private var panel: PinnedPanel?
    /// The last button that took a touch, for VoiceOver's activation, which has no touch to go by.
    weak var button: UIView?
    private let opening = UIImpactFeedbackGenerator(style: .medium)
    private let ticking = UISelectionFeedbackGenerator()

    init(window: WindowModel, host: @escaping () -> UIView?, act: @escaping (BarAction) -> Void) {
        self.window = window
        self.host = host
        self.act = act
    }

    var isOpen: Bool {
        panel != nil
    }

    /// Ready, at the touch, for what a hold will feel like.
    func prepare() {
        opening.prepare()
        ticking.prepare()
    }

    private var tab: TabRecord? {
        guard let id = window.tabID, let tab = Session.shared.workspace.tab(id), tab.isPinned else { return nil }
        return tab
    }

    /// The tab's options: back to its page and this page as its page, while
    /// it has gone on from it; unpinning it. A second tap puts them away.
    func showOptions(from source: UIView?) {
        guard let host = host(), let source = source ?? button else { return }
        showOptions(beside: source.convert(source.bounds, to: host))
    }

    /// The same from the iPhone Duo strip's item, which has no view of its
    /// own to take touches: a tap there, beside where the strip draws it.
    func showOptions(from item: UIBarButtonItem) {
        guard let host = host(), let frame = item.frame(in: host) else { return }
        showOptions(beside: frame)
    }

    private func showOptions(beside anchor: CGRect) {
        if panel != nil {
            close()
            return
        }
        guard let tab else { return }
        var rows: [PinnedPanel.Row] = []
        if let url = tab.url, url != tab.pinned {
            rows.append(.option("Back to Pinned Page", symbol: "arrow.uturn.backward") { [act] in act(.backToPinned(tab.id)) })
            rows.append(.option("Set as Pinned Page", symbol: "pin") { [act] in act(.repin(tab.id)) })
        }
        rows.append(.option("Unpin Tab", symbol: "pin.slash") { [act] in act(.unpin(tab.id)) })
        let header = tab.pinned.flatMap { Self.site($0) }.map { "Pinned to \($0)" }
        open(PinnedPanel(header: header, rows: rows), beside: anchor, scrubbing: nil)
    }

    /// The space's pinned tabs, held open by the finger at `point` (in the window).
    func showList(from source: UIView, at point: CGPoint) {
        let tabs = Pinned.tabs(in: window.spaceID)
        guard !tabs.isEmpty else { return }
        panel?.dismiss(animated: false)
        panel = nil
        let rows = tabs.map { tab in
            PinnedPanel.Row(title: tab.label, symbol: nil, site: tab.url ?? tab.pinned, current: tab.id == window.tabID,
                            open: Pinned.isOpen(tab)) { [act] in act(.select(tab.id)) }
        }
        guard let host = host() else { return }
        open(PinnedPanel(header: nil, rows: rows), beside: source.convert(source.bounds, to: host), scrubbing: point)
        // On the frame the list comes in.
        opening.impactOccurred(intensity: 0.7)
    }

    /// The finger, at `point` in the window, moved while it holds the list open.
    func scrub(to point: CGPoint) {
        guard let panel, let host = host() else { return }
        if panel.follow(host.convert(point, from: nil)) {
            ticking.selectionChanged()
            ticking.prepare()
        }
    }

    /// The finger lifted at `point`: on a row, to it; where it held the list
    /// open, the list stays for a tap; anywhere else, away.
    func release(at point: CGPoint) {
        guard let panel, let host = host() else { return }
        let point = host.convert(point, from: nil)
        if let row = panel.row(at: point) {
            choose(row)
        } else if panel.moved {
            close()
        } else {
            panel.stopFollowing()
        }
    }

    /// The press ended without a lift of its own (the system took it): a list it held goes.
    func pressCancelled() {
        if panel?.following == true { close() }
    }

    func close(animated: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        panel.dismiss(animated: animated)
    }

    private func choose(_ row: PinnedPanel.Row) {
        close()
        row.action()
    }

    private func open(_ panel: PinnedPanel, beside anchor: CGRect, scrubbing start: CGPoint?) {
        guard let host = host() else { return }
        panel.frame = host.bounds
        panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        panel.chosen = { [weak self] row in self?.choose(row) }
        panel.dismissed = { [weak self, weak panel] in
            if self?.panel === panel { self?.close() }
        }
        host.addSubview(panel)
        panel.place(from: anchor, following: start.map { host.convert($0, from: nil) })
        self.panel = panel
        panel.present()
    }

    /// A site as the header names it: its host without "www.".
    private static func site(_ url: URL) -> String? {
        guard let host = url.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// MARK: The panel

/// The pinned button's panel: a card of glass beside the button, a row a
/// pinned tab or an option, over a layer that takes a tap anywhere else to
/// put it away. Followed by a finger, the row level with it is highlighted
/// (follow), and the finger lifting chooses it (PinnedControl.release).
final class PinnedPanel: UIView {
    struct Row {
        var title: String
        var symbol: String?
        var site: URL?
        var current = false
        var open = false
        var action: () -> Void

        static func option(_ title: String, symbol: String, action: @escaping () -> Void) -> Row {
            Row(title: title, symbol: symbol, site: nil, action: action)
        }
    }

    var chosen: ((Row) -> Void)?
    var dismissed: (() -> Void)?
    /// A finger holds it open: the highlight follows it.
    private(set) var following = false
    /// The finger has gone somewhere since it opened the list.
    private(set) var moved = false

    private let header: String?
    private let rows: [Row]
    private let plate = UIView()
    private let glass: UIVisualEffectView
    private let scroller = UIScrollView()
    private let highlight = UIView()
    private var rowViews: [PinnedRowView] = []
    private var headerLabel: UILabel?
    private var anchor = CGRect.zero
    private var start = CGPoint.zero
    private var highlighted: Int?

    static let width: CGFloat = 260
    static let rowHeight: CGFloat = 44
    /// Round the rows, inside the card: the card's corners are the rows' and this, concentric.
    static let inset: CGFloat = 6
    static let corner: CGFloat = 22
    static let gap: CGFloat = 10
    static let headerHeight: CGFloat = 30
    /// Rows shown before the rest scroll.
    static let most = 8

    init(header: String?, rows: [Row]) {
        self.header = header
        self.rows = rows
        if #available(iOS 26.0, *) {
            glass = UIVisualEffectView(effect: nil)
            glass.cornerConfiguration = .corners(radius: .fixed(Self.corner))
        } else {
            glass = UIVisualEffectView(effect: nil)
            glass.layer.cornerRadius = Self.corner
            glass.layer.cornerCurve = .continuous
            glass.clipsToBounds = true
        }
        super.init(frame: .zero)
        // Depth from a soft shadow, not an outline: it reads on any page.
        plate.layer.shadowColor = UIColor.black.cgColor
        plate.layer.shadowOpacity = 0.14
        plate.layer.shadowRadius = 18
        plate.layer.shadowOffset = CGSize(width: 0, height: 6)
        addSubview(plate)
        plate.addSubview(glass)
        highlight.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.06) }
        highlight.layer.cornerRadius = Self.corner - Self.inset
        highlight.layer.cornerCurve = .continuous
        highlight.alpha = 0
        scroller.showsVerticalScrollIndicator = false
        scroller.alwaysBounceVertical = false
        scroller.addSubview(highlight)
        glass.contentView.addSubview(scroller)
        if let header {
            let label = UILabel()
            label.text = header
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
            label.lineBreakMode = .byTruncatingMiddle
            glass.contentView.addSubview(label)
            headerLabel = label
        }
        for (index, row) in rows.enumerated() {
            let view = PinnedRowView(row: row)
            view.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.chosen?(self.rows[index])
            }, for: .touchUpInside)
            view.addAction(UIAction { [weak self] _ in self?.light(index) }, for: .touchDown)
            view.addAction(UIAction { [weak self] _ in self?.light(nil) }, for: [.touchCancel, .touchDragExit])
            scroller.addSubview(view)
            rowViews.append(view)
        }
        let away = UITapGestureRecognizer(target: self, action: #selector(tappedAway(_:)))
        away.cancelsTouchesInView = false
        addGestureRecognizer(away)
        accessibilityViewIsModal = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func accessibilityPerformEscape() -> Bool {
        dismissed?()
        return true
    }

    @objc private func tappedAway(_ tap: UITapGestureRecognizer) {
        guard !plate.frame.contains(tap.location(in: self)) else { return }
        dismissed?()
    }

    // MARK: Where it stands

    /// Beside `anchor`, the button's frame here: above or under it on the
    /// phone bar, to its left on a strip at the window's right edge.
    /// `finger`: where a finger holds it open.
    func place(from anchor: CGRect, following finger: CGPoint?) {
        self.anchor = anchor
        let shown = min(rows.count, Self.most)
        let headed = header == nil ? 0 : Self.headerHeight
        let height = Self.inset * 2 + headed + CGFloat(shown) * Self.rowHeight
        let width = min(Self.width, bounds.width - 24)
        let safe = bounds.inset(by: safeAreaInsets).insetBy(dx: 12, dy: 8)
        var frame = CGRect(x: 0, y: 0, width: width, height: height)
        if anchor.midX > bounds.width * 0.75 {
            // A strip at the right edge: to its left, level with the button's top.
            frame.origin.x = anchor.minX - Self.gap - width
            frame.origin.y = min(max(anchor.minY, safe.minY), safe.maxY - height)
        } else {
            frame.origin.x = min(max(anchor.minX, safe.minX), safe.maxX - width)
            frame.origin.y = anchor.midY > bounds.midY ? anchor.minY - Self.gap - height : anchor.maxY + Self.gap
        }
        plate.frame = frame
        plate.layer.shadowPath = UIBezierPath(roundedRect: plate.bounds, cornerRadius: Self.corner).cgPath
        glass.frame = plate.bounds
        headerLabel?.frame = CGRect(x: 16, y: Self.inset + 6, width: width - 32, height: 18)
        scroller.frame = CGRect(x: Self.inset, y: Self.inset + headed, width: width - Self.inset * 2,
                                height: CGFloat(shown) * Self.rowHeight)
        scroller.contentSize = CGSize(width: scroller.bounds.width, height: CGFloat(rows.count) * Self.rowHeight)
        for (index, view) in rowViews.enumerated() {
            view.frame = CGRect(x: 0, y: CGFloat(index) * Self.rowHeight, width: scroller.bounds.width, height: Self.rowHeight)
        }
        // The tab on screen in view, where the rows scroll.
        if let current = rows.firstIndex(where: \.current), current >= shown {
            scroller.contentOffset.y = min(CGFloat(current + 1) * Self.rowHeight - scroller.bounds.height,
                                           scroller.contentSize.height - scroller.bounds.height)
        }
        following = finger != nil
        start = finger ?? .zero
        moved = false
        if let finger, anchor.contains(finger) == false { moved = true }
    }

    // MARK: Coming and going

    /// Grows out of the button, its glass materialising; under Reduce Motion it only fades.
    func present() {
        let still = UIAccessibility.isReduceMotionEnabled
        plate.transform = still ? .identity : grown(0.9)
        plate.layer.shadowOpacity = 0
        scroller.alpha = 0
        headerLabel?.alpha = 0
        UIView.animate(springDuration: 0.28, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.plate.transform = .identity
            self.glass.effect = Self.material
            self.scroller.alpha = 1
            self.headerLabel?.alpha = 1
        }
        let shadow = CABasicAnimation(keyPath: "shadowOpacity")
        shadow.fromValue = 0
        shadow.toValue = 0.14
        shadow.duration = 0.2
        plate.layer.add(shadow, forKey: "shadow")
        plate.layer.shadowOpacity = 0.14
        UIAccessibility.post(notification: .screenChanged, argument: rowViews.first(where: { $0.row.current }) ?? rowViews.first)
    }

    /// Back into the button, faster than it came.
    func dismiss(animated: Bool) {
        isUserInteractionEnabled = false
        guard animated else {
            removeFromSuperview()
            return
        }
        let still = UIAccessibility.isReduceMotionEnabled
        plate.layer.shadowOpacity = 0
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.plate.transform = still ? .identity : self.grown(0.95)
            self.glass.effect = nil
            self.scroller.alpha = 0
            self.headerLabel?.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    private static var material: UIVisualEffect {
        if #available(iOS 26.0, *) { return UIGlassEffect() }
        return UIBlurEffect(style: .systemThickMaterial)
    }

    /// The card at `scale` about the button's centre, which is where it grows from.
    private func grown(_ scale: CGFloat) -> CGAffineTransform {
        let origin = CGPoint(x: anchor.midX, y: anchor.midY)
        let centre = CGPoint(x: plate.frame.midX, y: plate.frame.midY)
        return CGAffineTransform(translationX: (origin.x - centre.x) * (1 - scale), y: (origin.y - centre.y) * (1 - scale))
            .scaledBy(x: scale, y: scale)
    }

    // MARK: Following a finger

    /// The finger at `point` here: the row level with it highlighted, in
    /// the card's column or the button's. True when that is a new row.
    func follow(_ point: CGPoint) -> Bool {
        guard following else { return false }
        if hypot(point.x - start.x, point.y - start.y) > PinnedPress.slop { moved = true }
        let index = rowIndex(level: point)
        guard index != highlighted else { return false }
        light(index)
        return index != nil
    }

    /// The finger lifted: what stays is for a tap.
    func stopFollowing() {
        following = false
        light(nil)
    }

    /// The row the finger lifted on, while it held the list open.
    func row(at point: CGPoint) -> Row? {
        guard following, let index = rowIndex(level: point) else { return nil }
        return rows[index]
    }

    private func rowIndex(level point: CGPoint) -> Int? {
        let column = plate.frame.union(anchor).insetBy(dx: -24, dy: 0)
        let inRows = scroller.convert(point, from: self)
        guard column.minX...column.maxX ~= point.x,
              scroller.bounds.minY...scroller.bounds.maxY ~= inRows.y, inRows.y >= 0
        else { return nil }
        let index = Int(inRows.y / Self.rowHeight)
        return rows.indices.contains(index) ? index : nil
    }

    /// The highlight on a row: moved there on a spring from the row it was
    /// on; shown in place where there was none; faded where there is none.
    private func light(_ index: Int?) {
        let was = highlighted
        highlighted = index
        guard let index else {
            UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) { self.highlight.alpha = 0 }
            return
        }
        let target = rowViews[index].frame
        if was == nil || highlight.alpha == 0 || UIAccessibility.isReduceMotionEnabled {
            highlight.layer.removeAllAnimations()
            highlight.frame = target
            UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) { self.highlight.alpha = 1 }
        } else {
            UIView.animate(springDuration: 0.2, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.highlight.frame = target
                self.highlight.alpha = 1
            }
        }
    }
}

/// One row of the panel: a pinned tab's icon and name, a check by the one on
/// screen and a dot by one that is open; or an option's symbol and name.
private final class PinnedRowView: UIControl {
    let row: PinnedPanel.Row
    private let site = SiteIconUIView()
    private let symbol = UIImageView()
    private let title = UILabel()
    private let mark = UIImageView()
    private let dot = UIView()

    init(row: PinnedPanel.Row) {
        self.row = row
        super.init(frame: .zero)
        if row.symbol == nil {
            site.size = 22
            site.isUserInteractionEnabled = false
            addSubview(site)
            site.url = row.site
        } else {
            symbol.image = UIImage(systemName: row.symbol ?? "")
            symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            symbol.tintColor = .label
            symbol.contentMode = .center
            addSubview(symbol)
        }
        title.text = row.title
        title.font = .systemFont(ofSize: 16)
        title.textColor = .label
        addSubview(title)
        mark.image = UIImage(systemName: "checkmark",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        mark.tintColor = .label
        mark.isHidden = !row.current
        addSubview(mark)
        dot.backgroundColor = Palette.UI.ink.withAlphaComponent(0.55)
        dot.layer.cornerRadius = 2.5
        dot.isHidden = row.current || !row.open
        addSubview(dot)
        isAccessibilityElement = true
        accessibilityLabel = row.title
        accessibilityValue = row.current ? "Current" : row.open ? "Open" : nil
        accessibilityTraits = row.current ? [.button, .selected] : .button
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let mid = bounds.midY
        site.frame = CGRect(x: 11, y: mid - 11, width: 22, height: 22)
        symbol.frame = CGRect(x: 11, y: mid - 11, width: 22, height: 22)
        mark.frame = CGRect(x: bounds.width - 30, y: mid - 9, width: 18, height: 18)
        dot.frame = CGRect(x: bounds.width - 23.5, y: mid - 2.5, width: 5, height: 5)
        title.frame = CGRect(x: 44, y: 0, width: bounds.width - 44 - 36, height: bounds.height)
    }
}
