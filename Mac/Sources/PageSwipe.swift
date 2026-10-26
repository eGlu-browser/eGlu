import AppKit
import PadCore
import SwiftUI
import WebKit

/// Back and forward by two fingers sideways on the trackpad: eGlu's own,
/// not WebKit's.
///
/// WebKit's swipe hands the fingers to AppKit, which decides how far they
/// go before letting go takes the step, as in Safari: most of the
/// trackpad's width, with nothing to make it shorter. Here the step is
/// taken after the trackpad's reach, as on the iPad (HistorySwipe).
///
/// Whether two fingers are a swipe at all is decided as WebKit's own swipe
/// decides it (ScrollSwipe): they set out sideways from where the page
/// was at its edge that way (`_pinnedState`), there is a page to go to, and
/// the page left the first scroll unused (`_webView:didNotHandleWheelEvent:`,
/// the answer WebKit's swipe waits for). So a page that scrolls sideways
/// itself (a map, a canvas, a carousel, a wide table) keeps its scroll, as
/// in Safari. The page's edge doesn't bounce at the left with a page to go
/// back to, nor at the right with one to go forward to, as WebKit has it
/// for its own swipe: a scroll there is then left unused.
///
/// The arrow is the iPad's (BackSwipe): it comes in from the edge with the
/// swipe and fills, in the space's colour, when letting go would take the
/// step. System Settings › Trackpad › Swipe between pages is followed: off,
/// two fingers do nothing here; with three fingers AppKit sends a swipe of
/// its own (`swiped`).
///
/// It is all WebKit's private calls, as Safari's swipe is; a macOS without
/// them keeps WebKit's own swipe (Page.setUp).
@MainActor
final class PageSwipe {
    private weak var view: PageView?
    /// The two fingers on the trackpad now, or last.
    private var gesture: ScrollSwipe?
    /// Its first scroll, the one whose answer is waited for.
    private var first: NSEvent?
    /// The fingers have left.
    private var released = false
    /// They left at this speed before the page had answered.
    private var leftAt: Double?
    /// The glide after a swipe: the swipe's as the fingers were, and no page's.
    private var gliding = false
    private var edges: UInt?
    private let arrow = SwipeArrow()
    private var showing: HistorySwipe.Way?
    /// How many times the arrow has set out to leave: only the last hides it.
    private var leaving = 0

    /// Whether this macOS's WebKit has what the swipe asks of it.
    static func works(on view: WKWebView) -> Bool {
        ["_pinnedState", "_setRubberBandingEnabled:"].allSatisfy { view.responds(to: Selector($0)) }
    }

    init(view: PageView) {
        self.view = view
        arrow.isHidden = true
        view.addSubview(arrow)
        bounce()
    }

    func stop() {
        arrow.removeFromSuperview()
    }

    // MARK: The fingers

    /// A scroll on the page: whether the swipe has it, and it goes no further.
    func scrolled(_ event: NSEvent) -> Bool {
        // The glide's every step, to its end, even with the fingers down again meanwhile.
        if gliding, event.phase.isEmpty, !event.momentumPhase.isEmpty {
            if !event.momentumPhase.isDisjoint(with: [.ended, .cancelled]) { gliding = false }
            return true
        }
        if event.phase.contains(.began) {
            gliding = false
            begin(with: event)
            return false
        }
        guard var gesture, !released else { return false }
        if !event.phase.isDisjoint(with: [.changed, .stationary]) {
            let had = gesture.moved(dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY), at: event.timestamp)
            self.gesture = gesture
            if gesture.isScroll { bounce() }
            show()
            return had
        }
        guard !event.phase.isDisjoint(with: [.ended, .cancelled]) else { return false }
        released = true
        if gesture.taken {
            gliding = true
            if event.phase.contains(.cancelled) {
                finish(taken: false)
            } else {
                settle(at: gesture.speed(at: event.timestamp))
            }
            return true
        }
        if gesture.awaitsAnswer, event.phase.contains(.ended) { wait(at: gesture.speed(at: event.timestamp)) }
        return false
    }

    /// A new gesture's first scroll, which goes to the page. It may become a
    /// swipe only by a trackpad (or a Magic Mouse) with swiping between
    /// pages on, and no key held, which makes it something else.
    private func begin(with event: NSEvent) {
        finish(taken: false)
        released = false
        leftAt = nil
        first = event
        var open: Set<HistorySwipe.Way> = []
        if let view, NSEvent.isSwipeTrackingFromScrollEventsEnabled, event.hasPreciseScrollingDeltas,
           event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
           view.fullscreenState == .notInFullscreen {
            let pinned = (view.value(forKey: "pinnedState") as? NSNumber)?.uintValue ?? 0
            if pinned & Self.left != 0, view.canGoBack { open.insert(.back) }
            if pinned & Self.right != 0, view.canGoForward { open.insert(.forward) }
        }
        gesture = ScrollSwipe(dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY),
                              at: event.timestamp, open: open)
        // Before WebKit has the scroll, which it takes with the edges as they are then.
        bounce()
    }

    /// WebKit's word that the page left a scroll unused: for the gesture's
    /// first, the answer the swipe waits for.
    func leftAlone(_ event: NSEvent) {
        guard let first, event === first || (event.phase.contains(.began) && event.timestamp == first.timestamp),
              gesture != nil else { return }
        gesture?.firstLeftAlone()
        guard released else {
            show()
            return
        }
        guard let leftAt, gesture?.taken == true else { return }
        self.leftAt = nil
        // The page has had the whole gesture: the rest of its glide too, unless it goes elsewhere.
        gliding = settle(at: leftAt)
    }

    /// Somewhere else to go, or nowhere: an answer still to come no longer
    /// takes a step, which was perhaps taken meanwhile (⌘[).
    func wentSomewhere() {
        leftAt = nil
        bounce()
    }

    /// The fingers left before the page answered: as on the iPad
    /// (Pointer.leave), the answer gets a moment more, and without it the
    /// swipe goes nowhere.
    private func wait(at speed: Double) {
        leftAt = speed
        let first = first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.first === first, self.leftAt != nil else { return }
            self.leftAt = nil
        }
    }

    /// Whether the step is taken.
    @discardableResult
    private func settle(at speed: Double) -> Bool {
        guard let view, let way = gesture?.commits(velocity: speed), canGo(way) else {
            finish(taken: false)
            return false
        }
        finish(taken: true)
        if way == .back { view.goBack() } else { view.goForward() }
        return true
    }

    private func canGo(_ way: HistorySwipe.Way) -> Bool {
        guard let view else { return false }
        return way == .back ? view.canGoBack : view.canGoForward
    }

    /// Three fingers, where System Settings has them swipe between pages:
    /// AppKit sends one swipe, a step at once, as WebKit takes it with its own swipe on.
    func swiped(_ event: NSEvent) -> Bool {
        guard let view, view.fullscreenState == .notInFullscreen, event.deltaX != 0 else { return false }
        let way: HistorySwipe.Way = event.deltaX > 0 ? .back : .forward
        guard canGo(way) else { return false }
        leftAt = nil
        if way == .back { view.goBack() } else { view.goForward() }
        return true
    }

    // MARK: The page's edges

    /// `_WKRectEdge`'s left and right.
    private static let left: UInt = 1
    private static let right: UInt = 4
    private static let all: UInt = 15

    /// Which of the page's edges bounce: not the left with a page to go
    /// back to, nor the right with one to go forward to, while two fingers
    /// may be a swipe; every one once they are a scroll, to the gesture's
    /// end, as WebKit has it (rubberBandableEdgesRespectingHistorySwipe).
    /// Again whenever there is somewhere else to go.
    private func bounce() {
        guard let view else { return }
        var edges = Self.all
        if NSEvent.isSwipeTrackingFromScrollEventsEnabled, gesture?.isScroll != true {
            if view.canGoBack { edges &= ~Self.left }
            if view.canGoForward { edges &= ~Self.right }
        }
        guard edges != self.edges else { return }
        self.edges = edges
        // `_setRubberBandingEnabled:`, which the key without its underscore finds.
        view.setValue(NSNumber(value: edges), forKey: "rubberBandingEnabled")
    }

    // MARK: The arrow

    private func show() {
        guard !released, let way = gesture?.way, canGo(way), let view else {
            finish(taken: false)
            return
        }
        let progress = HistorySwipe.progress(distance: gesture?.distance ?? 0, reach: HistorySwipe.trackpadReach)
        let armed = progress >= 1
        if showing != way {
            showing = way
            arrow.set(way: way)
            // Filled in the space's colour, the chevron in the ink that reads on it (dark on yellow).
            let colour = view.page.flatMap { Session.shared.workspace.space($0.space) }?.color
            arrow.colour = colour?.nsColor ?? .controlAccentColor
            arrow.armedInk = colour.map { NSColor($0.ink) } ?? .white
            arrow.set(armed: false, animated: false)
            arrow.isHidden = false
            view.addSubview(arrow, positioned: .above, relativeTo: nil)
        }
        if armed != arrow.armed {
            arrow.set(armed: armed)
            // The point past which letting go takes the step, felt in the trackpad as well as seen.
            if armed { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }
        arrow.place(in: view.bounds, way: way, progress: CGFloat(progress))
    }

    /// The swipe is over: the arrow leaves the way it came, quicker when the step was taken.
    private func finish(taken: Bool) {
        guard let way = showing, let view else { return }
        showing = nil
        leaving += 1
        let leaving = leaving
        let arrow = arrow
        let bounds = view.bounds
        NSAnimationContext.runAnimationGroup { context in
            context.duration = taken ? 0.25 : 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            arrow.place(in: bounds, way: way, progress: 0, animated: true)
        } completionHandler: { [weak self] in
            // A new swipe may have begun meanwhile, and perhaps ended: the arrow is its then.
            guard let self, self.showing == nil, self.leaving == leaving else { return }
            arrow.isHidden = true
        }
    }
}

/// The arrow a swipe back or forward brings in from the page's edge, as the
/// iPad's: on glass, filled in its colour once letting go would take the step.
private final class SwipeArrow: NSView {
    static let side: CGFloat = 40
    private let glass = NSGlassEffectView()
    private let fill = NSView()
    private let chevron = NSImageView()
    private(set) var armed = false
    var colour = NSColor.controlAccentColor
    /// The chevron's colour on the filled disc: the space colour's ink.
    var armedInk = NSColor.white

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        glass.frame = bounds
        glass.cornerRadius = Self.side / 2
        addSubview(glass)
        fill.frame = bounds
        fill.wantsLayer = true
        fill.layer?.cornerRadius = Self.side / 2
        fill.alphaValue = 0
        addSubview(fill)
        chevron.frame = bounds
        chevron.imageScaling = .scaleNone
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        chevron.setAccessibilityElement(false)
        addSubview(chevron)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Clicks go through to the page.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func set(way: HistorySwipe.Way) {
        chevron.image = NSImage(systemSymbolName: way == .back ? "chevron.left" : "chevron.right", accessibilityDescription: nil)
    }

    /// Filled in its colour once letting go would take the step.
    func set(armed: Bool, animated: Bool = true) {
        self.armed = armed
        fill.layer?.backgroundColor = colour.cgColor
        chevron.contentTintColor = armed ? armedInk : .labelColor
        guard animated else {
            fill.layer?.removeAllAnimations()
            fill.alphaValue = armed ? 1 : 0
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fill.animator().alphaValue = armed ? 1 : 0
        }
    }

    /// In from outside the edge to 16 points inside it, halfway up the
    /// page. With Reduce Motion it stays where it ends and fades in.
    func place(in bounds: NSRect, way: HistorySwipe.Way, progress: CGFloat, animated: Bool = false) {
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let inset = still ? 16 + Self.side / 2 : -Self.side / 2 + (16 + Self.side) * progress
        let centre = NSPoint(x: way == .back ? bounds.minX + inset : bounds.maxX - inset, y: bounds.midY)
        let target = animated ? animator() : self
        target.frame = NSRect(x: centre.x - Self.side / 2, y: centre.y - Self.side / 2, width: Self.side, height: Self.side)
        target.alphaValue = min(1, progress * 3)
    }
}
