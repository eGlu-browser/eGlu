import PadCore
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Back and forward by a swipe on a desktop page.
///
/// WebKit's own swipe is off there (Page.applyScrolling). It comes as one
/// switch for a finger and the trackpad both, and its trackpad half takes two
/// fingers sideways whenever WebKit's own scrolling has nothing to scroll.
/// With that scrolling off and the wheel bridged, that is always: a canvas
/// that pans with two fingers would go back instead.
///
/// So here a finger dragged in from the page's left edge goes back, and from
/// its right edge forward; and Pointer drives the same arrow for two fingers
/// on the trackpad, once the page has left them alone (TrackpadSwipe). The
/// arrow comes in from the edge with the swipe and fills when letting go
/// would take the step, in the space's colour. Nothing shows, and the drag
/// stays the page's, where there is no page to go to.
@MainActor
final class BackSwipe: NSObject, UIGestureRecognizerDelegate {
    private weak var page: Page?
    private let left = EdgePan(edge: .left)
    private let right = EdgePan(edge: .right)
    private let arrow = SwipeArrow()
    private var showing: HistorySwipe.Way?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            left.isEnabled = isEnabled
            right.isEnabled = isEnabled
            if !isEnabled { finish(taken: false) }
        }
    }

    init(page: Page) {
        self.page = page
        super.init()
        for pan in [left, right] {
            pan.addTarget(self, action: #selector(dragged(_:)))
            pan.delegate = self
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            pan.maximumNumberOfTouches = 1
            pan.isEnabled = false
            page.view.addGestureRecognizer(pan)
        }
        arrow.isHidden = true
        page.view.addSubview(arrow)
    }

    func stop() {
        for pan in [left, right] { pan.view?.removeGestureRecognizer(pan) }
        arrow.removeFromSuperview()
    }

    // MARK: The arrow

    /// The arrow for a swipe that has come `progress` of the way, 0 to 1.
    func show(_ way: HistorySwipe.Way, progress: Double) {
        guard isEnabled, let view = page?.view else { return }
        let armed = progress >= 1
        if showing != way {
            showing = way
            arrow.set(way: way)
            // Filled in the space's colour, as the line over the pane with the keys is.
            arrow.tintColor = page.flatMap { Session.shared.workspace.space($0.space) }?.color.uiColor
            arrow.set(armed: false)
            arrow.isHidden = false
            view.bringSubviewToFront(arrow)
        }
        if armed != arrow.armed {
            arrow.set(armed: armed)
            // The point past which letting go takes the step, felt as well as seen.
            if armed { UISelectionFeedbackGenerator().selectionChanged() }
        }
        arrow.place(in: view.bounds, way: way, progress: CGFloat(progress))
    }

    /// The swipe is over: the arrow leaves the way it came, quicker when the step was taken.
    func finish(taken: Bool) {
        guard let way = showing, let view = page?.view else { return }
        showing = nil
        let arrow = arrow
        let bounds = view.bounds
        UIView.animate(springDuration: taken ? 0.25 : 0.35, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            arrow.place(in: bounds, way: way, progress: 0)
        } completion: { [weak self] _ in
            // A new swipe may have begun meanwhile; the arrow is its then.
            if self?.showing == nil { arrow.isHidden = true }
        }
    }

    // MARK: A finger from the edge

    private func way(of pan: EdgePan) -> HistorySwipe.Way {
        pan.edge == .left ? .back : .forward
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? EdgePan, let page, let view = pan.view else { return true }
        // Into the page and mostly sideways, and only with somewhere to go.
        let velocity = pan.velocity(in: view)
        let inward = pan.edge == .left ? velocity.x : -velocity.x
        return inward > 0 && abs(velocity.x) > abs(velocity.y) * 1.5 && page.canGo(way(of: pan))
    }

    /// With WebKit's own recognizers, which neither wait for this one nor stop it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func dragged(_ pan: EdgePan) {
        guard let page, let view = pan.view else { return }
        let way = way(of: pan)
        let sign: CGFloat = way == .back ? 1 : -1
        let distance = Double(pan.translation(in: view).x * sign)
        switch pan.state {
        case .began, .changed:
            show(way, progress: HistorySwipe.progress(distance: distance))
        case .ended:
            let velocity = Double(pan.velocity(in: view).x * sign)
            let taken = HistorySwipe.commits(distance: distance, velocity: velocity) && page.canGo(way)
            finish(taken: taken)
            if taken { page.go(way) }
        default:
            finish(taken: false)
        }
    }
}

/// A pan that begins only within `band` of one edge of its view: the page's
/// own edge, which in a split window is not the screen's.
private final class EdgePan: UIPanGestureRecognizer {
    static let band: CGFloat = 24
    let edge: UIRectEdge

    init(edge: UIRectEdge) {
        self.edge = edge
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard state == .possible, let view, let touch = touches.first else { return }
        let x = touch.location(in: view).x
        let near = edge == .left ? x <= Self.band : x >= view.bounds.width - Self.band
        if !near { state = .failed }
    }
}

/// The arrow a swipe back or forward brings in from the page's edge.
private final class SwipeArrow: UIView {
    static let side: CGFloat = 40
    private let platter: UIVisualEffectView
    private let fill = UIView()
    private let chevron = UIImageView()
    private(set) var armed = false

    init() {
        if #available(iOS 26.0, *) {
            platter = UIVisualEffectView(effect: UIGlassEffect())
            platter.cornerConfiguration = .corners(radius: .fixed(Self.side / 2))
        } else {
            platter = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            platter.layer.cornerRadius = Self.side / 2
            platter.clipsToBounds = true
        }
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 3)
        platter.frame = bounds
        addSubview(platter)
        fill.frame = bounds
        fill.layer.cornerRadius = Self.side / 2
        fill.alpha = 0
        addSubview(fill)
        chevron.contentMode = .center
        chevron.frame = bounds
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        addSubview(chevron)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func set(way: HistorySwipe.Way) {
        chevron.image = UIImage(systemName: way == .back ? "chevron.left" : "chevron.right")
    }

    /// Filled in its tint once letting go would take the step.
    func set(armed: Bool) {
        self.armed = armed
        fill.backgroundColor = tintColor
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.fill.alpha = armed ? 1 : 0
            self.chevron.tintColor = armed ? .white : Palette.UI.ink
        }
    }

    /// In from outside the edge to 16 points inside it, halfway up the
    /// page. With Reduce Motion it stays where it ends and fades in.
    func place(in bounds: CGRect, way: HistorySwipe.Way, progress: CGFloat) {
        let still = UIAccessibility.isReduceMotionEnabled
        let inset = still ? 16 + Self.side / 2 : -Self.side / 2 + (16 + Self.side) * progress
        center = CGPoint(x: way == .back ? bounds.minX + inset : bounds.maxX - inset, y: bounds.midY)
        alpha = min(1, progress * 3)
    }
}
