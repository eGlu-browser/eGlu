import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The gap between a split's two cards (Browser.layoutPanes), drawn as the
/// frame's other gaps are: the window's ground shows through it, as round
/// the cards, and a short grip stands in its middle, as the Mac's. Under the
/// pointer, pressed or dragged, the grip grows and darkens; dragged, the
/// pages follow it; tapped twice, they are made even.
final class SplitDivider: UIView {
    /// As wide as the frame's other gaps: between the cards and the sidebar,
    /// and the window's edges.
    static let width = Side.bezel

    /// Where the drag is, across the stage.
    var moved: ((CGFloat) -> Void)?
    var ended: (() -> Void)?
    var centered: (() -> Void)?

    private let grip = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        grip.backgroundColor = Palette.UI.faint
        grip.layer.cornerCurve = .continuous
        grip.isUserInteractionEnabled = false
        addSubview(grip)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        // A second finger doesn't join a drag already going.
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        let twice = UITapGestureRecognizer(target: self, action: #selector(tappedTwice))
        twice.numberOfTapsRequired = 2
        addGestureRecognizer(twice)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
        isAccessibilityElement = true
        accessibilityLabel = "Split divider"
        accessibilityHint = "Double-tap to make the two pages even"
        isHidden = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The grip's three states, as the Mac's: at rest, faint and short; under
    /// the pointer, darker and taller; held, taller still. The press shows
    /// the moment the finger lands, before the drag has moved far enough to begin.
    private enum Grip { case rest, hover, held }

    private var hovering = false { didSet { show() } }
    private var pressed = false { didSet { show() } }
    private var dragging = false { didSet { show() } }
    private var shown = Grip.rest

    private var wanted: Grip {
        pressed || dragging ? .held : hovering ? .hover : .rest
    }

    /// A state change says the divider heard: quick, and a spring without
    /// bounce from wherever the grip is, so a press let go halfway through
    /// growing shrinks back from there. In place under Reduce Motion.
    private func show() {
        let state = wanted
        guard state != shown else { return }
        shown = state
        let change = {
            self.grip.backgroundColor = state == .rest ? Palette.UI.faint : Palette.UI.muted
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        guard !UIAccessibility.isReduceMotionEnabled else { return change() }
        UIView.animate(springDuration: 0.25, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: change)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height: CGFloat = switch shown {
        case .rest: 44
        case .hover: 64
        case .held: 80
        }
        let width: CGFloat = 3
        grip.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
        grip.layer.cornerRadius = width / 2
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        pressed = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        pressed = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        pressed = false
    }

    /// The gap is narrow for a finger: ten points into each page take the
    /// drag too, at their very edges.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -10, dy: 0).contains(point)
    }

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            dragging = true
        case .changed:
            if let stage = superview { moved?(pan.location(in: stage).x) }
        case .ended, .cancelled, .failed:
            dragging = false
            ended?()
        default:
            break
        }
    }

    @objc private func hovered(_ hover: UIHoverGestureRecognizer) {
        hovering = hover.state == .began || hover.state == .changed
    }

    @objc private func tappedTwice() {
        centered?()
    }

    override func accessibilityActivate() -> Bool {
        centered?()
        return true
    }
}

/// Says where a touch or a click lands on the stage the moment it lands, and
/// takes nothing from the page under it: it fails at once, so the page gets
/// the touch as if it weren't there.
final class TouchDown: UIGestureRecognizer {
    var landed: ((CGPoint) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view { landed?(touch.location(in: view)) }
        state = .failed
    }
}
