import Foundation

/// The arithmetic behind the pointer bridges, kept apart from UIKit so it can
/// be tested anywhere.
public enum Pinch {
    /// The wheel delta Chrome sends for one step of a trackpad pinch on a
    /// Mac: minus `factor` times the natural log of the step's scale, with
    /// ctrlKey set. Negative zooms in. Steps add up: two steps of 1.1 send the
    /// same total as one of 1.21.
    public static func wheelDelta(step: Double, factor: Double = 100) -> Double {
        guard step > 0, step.isFinite else { return 0 }
        return -factor * Foundation.log(step)
    }
}

public enum Wheel {
    /// A two-finger pan as the wheel delta a Mac sends for the same swipe.
    /// With natural scrolling the content follows the fingers, so fingers
    /// moving up (y falling) scroll down, a positive deltaY.
    public static func delta(translationX dx: Double, translationY dy: Double) -> (x: Double, y: Double) {
        (-dx, -dy)
    }
}

/// One step of a scroll or a pinch on its way into a page (WheelLine).
public protocol WheelStep {
    /// The same kind of step, so the two add up to one.
    func joins(_ other: Self) -> Bool
    mutating func add(_ other: Self)
}

/// Wheel steps into a page, one at a time. A trackpad makes over a hundred
/// a second; a page slower than that would have them pile up, and go on
/// scrolling after the fingers had stopped. So while the page is still
/// answering one, those that come wait, each added to the one before it when
/// they are of a kind, and the next goes when the answer is in. Another kind
/// (a pinch after a scroll) waits its turn behind, so the page hears them in
/// the order they were made.
public struct WheelLine<Step: WheelStep> {
    /// Whether the page has yet to answer one.
    public private(set) var out = false
    public private(set) var held: [Step] = []
    /// Which run of steps this is: an answer from before `drop()` says
    /// nothing about this one.
    public private(set) var run = 0

    public init() {}

    /// A step made: returned when it is to go now, kept otherwise.
    public mutating func take(_ step: Step) -> Step? {
        guard out else {
            out = true
            return step
        }
        if let last = held.indices.last, held[last].joins(step) {
            held[last].add(step)
        } else {
            held.append(step)
        }
        return nil
    }

    /// The page answered the step that went in `run`: the next to go, if one waits.
    public mutating func answered(in run: Int) -> Step? {
        guard run == self.run else { return nil }
        guard !held.isEmpty else {
            out = false
            return nil
        }
        return held.removeFirst()
    }

    /// The page's process ended, or the page is going: what it had yet to
    /// answer no longer keeps the next from going. Those that waited come
    /// back, to hear that nothing came of them.
    public mutating func drop() -> [Step] {
        let waited = held
        held = []
        out = false
        run += 1
        return waited
    }
}

/// Back and forward by a swipe sideways, where the app takes it and not
/// WebKit (a desktop page: Page.applyScrolling). A finger drags in from the
/// page's edge; two fingers go sideways on the trackpad, as on a Mac.
public enum HistorySwipe {
    public enum Way: Equatable, Sendable {
        case back, forward
    }

    /// How far, in points, a swipe travels before letting go takes the step.
    public static let reach = 110.0

    /// How much of the way there, from 0 to 1.
    public static func progress(distance: Double) -> Double {
        min(1, max(0, distance / reach))
    }

    /// Whether letting go now takes the step: far enough and not on the
    /// way back at speed, which takes it back; or a flick that has gone a
    /// third of the way. `velocity` is along the swipe, in points a second.
    public static func commits(distance: Double, velocity: Double) -> Bool {
        (distance >= reach && velocity > -300) || (distance >= reach / 3 && velocity >= 700)
    }
}

/// Two fingers going sideways on the trackpad. It is a scroll first, and the
/// page's to use. It becomes a step back or forward only when it set out
/// sideways and the page had no use for any of it: every wheel event it made
/// came back unused (bridge.js wheel(): 'free'), as a Mac's browsers go back
/// only when the page left the swipe alone. One answer that says otherwise,
/// or one that never comes, and it stays a scroll.
public struct TrackpadSwipe: Equatable, Sendable {
    /// How far the fingers go before a swipe sideways is told from a scroll.
    public static let slack = 16.0

    private var x = 0.0
    private var y = 0.0
    private var heading: HistorySwipe.Way?
    private var scroll = false
    private var sent = 0
    private var answers = 0
    private var used = false

    public init() {}

    /// One step of the pan, in the points the fingers moved, as it goes to
    /// the page as a wheel event. Fingers moving right go back: the content
    /// follows them, and what was there before is to the left.
    public mutating func moved(dx: Double, dy: Double) {
        x += dx
        y += abs(dy)
        sent += 1
        guard heading == nil, !scroll, max(abs(x), y) >= Self.slack else { return }
        if abs(x) >= 2 * y {
            heading = x > 0 ? .back : .forward
        } else {
            scroll = true
        }
    }

    /// The page's answer to one step: whether it left the sideways part unused.
    public mutating func answered(free: Bool) {
        answers += 1
        if !free { used = true }
    }

    /// Where it would go, once it has set out sideways and the page has
    /// answered at least once, never having used it.
    public var way: HistorySwipe.Way? {
        guard !used, answers > 0 else { return nil }
        return heading
    }

    /// How far it has gone that way; back toward where it began counts down to nothing.
    public var distance: Double {
        switch heading {
        case .back: return max(0, x)
        case .forward: return max(0, -x)
        case nil: return 0
        }
    }

    /// Every step sent has been answered.
    public var settled: Bool {
        answers >= sent
    }

    /// The step to take when the fingers leave at `velocity` (points a
    /// second, to the right): none while an answer is still to come.
    public func commits(velocity: Double) -> HistorySwipe.Way? {
        guard settled, let way else { return nil }
        let along = way == .back ? velocity : -velocity
        return HistorySwipe.commits(distance: distance, velocity: along) ? way : nil
    }
}

/// The glide after the fingers leave the trackpad, which a Mac's trackpad
/// sends as more wheel events and an iPad pan doesn't send at all.
///
/// The speed falls the way a UIScrollView's does at its normal deceleration
/// rate, 0.998 for each millisecond, and the glide ends below `stopSpeed`.
public struct Momentum: Equatable, Sendable {
    public var velocityX: Double
    public var velocityY: Double
    public var rate: Double
    public var stopSpeed: Double

    /// Velocities in wheel units (points) per second.
    public init(velocityX: Double, velocityY: Double, rate: Double = 0.998, stopSpeed: Double = 12) {
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.rate = rate
        self.stopSpeed = stopSpeed
    }

    public var isDone: Bool {
        (velocityX * velocityX + velocityY * velocityY).squareRoot() < stopSpeed
    }

    /// The distance covered in the next `seconds`, or nil once the glide is over.
    public mutating func advance(by seconds: Double) -> (x: Double, y: Double)? {
        guard !isDone, seconds > 0 else { return nil }
        let milliseconds = seconds * 1000
        let decay = Foundation.pow(rate, milliseconds)
        // The distance under exponential decay, not speed times time: the
        // same total whatever the frame rate.
        let k = Foundation.log(rate) * 1000
        let travelled = (decay - 1) / k
        let step = (velocityX * travelled, velocityY * travelled)
        velocityX *= decay
        velocityY *= decay
        return step
    }
}

/// Where the zoom is held.
///
/// At 1: no pinch, double tap or anything else zooms the page itself. The
/// exception is a window narrower than the page's desktop layout, which
/// WebKit can make wider than a narrow window (a portrait iPad, a small Stage
/// Manager window) and then scale down to fit. There WebKit's fit is kept,
/// the smallest scale it allows, so the whole page stays in view instead of
/// being cut off at the window's edge with no way to scroll to the rest.
public enum ZoomLock {
    public static func scale(webKitMinimum: Double?) -> Double {
        guard let minimum = webKitMinimum, minimum > 0, minimum.isFinite else { return 1 }
        return min(1, minimum)
    }
}
