import XCTest
@testable import PadCore

final class PinchTests: XCTestCase {
    func testSpreadingZoomsInWithANegativeDelta() {
        XCTAssertLessThan(Pinch.wheelDelta(step: 1.1), 0)
        XCTAssertGreaterThan(Pinch.wheelDelta(step: 0.9), 0)
        XCTAssertEqual(Pinch.wheelDelta(step: 1), 0)
    }

    func testDoublingSendsChromesAmount() {
        XCTAssertEqual(Pinch.wheelDelta(step: 2), -69.3147, accuracy: 0.001)
    }

    func testStepsAddUpToTheWholePinch() {
        let split = Pinch.wheelDelta(step: 1.1) + Pinch.wheelDelta(step: 1.1)
        XCTAssertEqual(split, Pinch.wheelDelta(step: 1.21), accuracy: 1e-9)
    }

    func testNonsenseScalesSendNothing() {
        XCTAssertEqual(Pinch.wheelDelta(step: 0), 0)
        XCTAssertEqual(Pinch.wheelDelta(step: -1), 0)
        XCTAssertEqual(Pinch.wheelDelta(step: .infinity), 0)
    }
}

final class WheelTests: XCTestCase {
    func testFingersUpScrollDown() {
        let delta = Wheel.delta(translationX: 3, translationY: -10)
        XCTAssertEqual(delta.x, -3)
        XCTAssertEqual(delta.y, 10)
    }
}

final class WheelLineTests: XCTestCase {
    struct Step: WheelStep, Equatable {
        var kind: String
        var amount: Double
        /// How many steps this one is made of: each has someone to tell.
        var made = 1

        func joins(_ other: Step) -> Bool { kind == other.kind }
        mutating func add(_ other: Step) {
            amount += other.amount
            made += other.made
        }
    }

    func testTheFirstGoesAtOnceAndTheNextOnItsAnswer() {
        var line = WheelLine<Step>()
        XCTAssertEqual(line.take(Step(kind: "scroll", amount: 4)), Step(kind: "scroll", amount: 4))
        XCTAssertNil(line.take(Step(kind: "scroll", amount: 6)), "the page is still answering the first")
        XCTAssertEqual(line.answered(in: line.run), Step(kind: "scroll", amount: 6))
        XCTAssertNil(line.answered(in: line.run))
        XCTAssertFalse(line.out)
        XCTAssertEqual(line.take(Step(kind: "scroll", amount: 1)), Step(kind: "scroll", amount: 1), "nothing owed: it goes at once")
    }

    func testThoseOfAKindAddUpWhileOneIsOut() {
        var line = WheelLine<Step>()
        _ = line.take(Step(kind: "scroll", amount: 1))
        for _ in 0..<50 { XCTAssertNil(line.take(Step(kind: "scroll", amount: 2))) }
        XCTAssertEqual(line.held.count, 1, "a slow page is sent one, not fifty")
        XCTAssertEqual(line.answered(in: line.run), Step(kind: "scroll", amount: 100, made: 50))
    }

    func testAnotherKindWaitsItsTurnBehind() {
        var line = WheelLine<Step>()
        _ = line.take(Step(kind: "scroll", amount: 1))
        _ = line.take(Step(kind: "scroll", amount: 2))
        _ = line.take(Step(kind: "pinch", amount: 5))
        _ = line.take(Step(kind: "pinch", amount: 5))
        _ = line.take(Step(kind: "scroll", amount: 3))
        XCTAssertTrue(line.out)
        // One at a time, in the order they were made; a scroll after the pinch is not added to the one before it.
        XCTAssertEqual(line.answered(in: line.run), Step(kind: "scroll", amount: 2))
        XCTAssertEqual(line.answered(in: line.run), Step(kind: "pinch", amount: 10, made: 2))
        XCTAssertEqual(line.answered(in: line.run), Step(kind: "scroll", amount: 3))
        XCTAssertNil(line.answered(in: line.run))
        XCTAssertFalse(line.out)
    }

    func testEveryStepReachesThePageOnce() {
        var line = WheelLine<Step>()
        var sent: [Step] = []
        var owed = 0
        // The page answers one in three of the moments a step is made.
        for index in 0..<300 {
            if let now = line.take(Step(kind: index % 40 < 30 ? "scroll" : "pinch", amount: 1)) {
                sent.append(now)
                owed += 1
            }
            if index % 3 == 0, owed > 0 {
                owed -= 1
                if let next = line.answered(in: line.run) {
                    sent.append(next)
                    owed += 1
                }
            }
            XCTAssertLessThanOrEqual(owed, 1, "never two with the page at once")
        }
        while owed > 0 {
            owed -= 1
            if let next = line.answered(in: line.run) {
                sent.append(next)
                owed += 1
            }
        }
        XCTAssertEqual(sent.reduce(0) { $0 + $1.amount }, 300)
        XCTAssertEqual(sent.reduce(0) { $0 + $1.made }, 300)
        XCTAssertLessThan(sent.count, 300)
        XCTAssertTrue(line.held.isEmpty)
    }

    func testAPageThatWentOwesNothing() {
        var line = WheelLine<Step>()
        let before = line.run
        _ = line.take(Step(kind: "scroll", amount: 1))
        _ = line.take(Step(kind: "scroll", amount: 2))
        _ = line.take(Step(kind: "pinch", amount: 3))
        // Its process ended with one unanswered: those that waited are handed back, and the next goes at once.
        XCTAssertEqual(line.drop(), [Step(kind: "scroll", amount: 2), Step(kind: "pinch", amount: 3)])
        XCTAssertFalse(line.out)
        XCTAssertEqual(line.take(Step(kind: "scroll", amount: 7)), Step(kind: "scroll", amount: 7))
        _ = line.take(Step(kind: "scroll", amount: 8))
        // The old answer, coming late, sends nothing and frees nothing.
        XCTAssertNil(line.answered(in: before))
        XCTAssertTrue(line.out)
        XCTAssertEqual(line.held, [Step(kind: "scroll", amount: 8)])
        XCTAssertEqual(line.answered(in: line.run), Step(kind: "scroll", amount: 8))
    }
}

final class MomentumTests: XCTestCase {
    func testASwipeGoesBackWhenItHasGoneFarEnoughOrFastEnough() {
        XCTAssertEqual(HistorySwipe.progress(distance: 55), 0.5, accuracy: 0.001)
        XCTAssertEqual(HistorySwipe.progress(distance: 400), 1)
        XCTAssertEqual(HistorySwipe.progress(distance: -20), 0)
        XCTAssertTrue(HistorySwipe.commits(distance: 110, velocity: 0))
        XCTAssertFalse(HistorySwipe.commits(distance: 100, velocity: 0))
        XCTAssertTrue(HistorySwipe.commits(distance: 40, velocity: 900), "a flick")
        XCTAssertFalse(HistorySwipe.commits(distance: 20, velocity: 900), "a twitch isn't one")
        XCTAssertFalse(HistorySwipe.commits(distance: 100, velocity: -900), "let go on the way back")
        XCTAssertFalse(HistorySwipe.commits(distance: 150, velocity: -900), "far enough, but flicked back")
        XCTAssertTrue(HistorySwipe.commits(distance: 150, velocity: -100), "a hand that eases off still means it")
    }

    func testTwoFingersSidewaysGoBackOnlyWhenThePageLeftEveryStep() {
        var swipe = TrackpadSwipe()
        for _ in 0..<12 {
            swipe.moved(dx: 10, dy: 0.5)
            XCTAssertNil(swipe.commits(velocity: 0), "an answer is still to come")
            swipe.answered(free: true)
        }
        XCTAssertEqual(swipe.way, .back, "fingers to the right: the page before")
        XCTAssertEqual(swipe.distance, 120, accuracy: 0.001)
        XCTAssertEqual(swipe.commits(velocity: 0), .back)

        var used = TrackpadSwipe()
        for step in 0..<12 {
            used.moved(dx: -10, dy: 0)
            used.answered(free: step != 5)
        }
        XCTAssertNil(used.way, "the page took one step: the swipe is its own")
        XCTAssertNil(used.commits(velocity: -2000))
    }

    func testTwoFingersGoBackSoonerThanAFinger() {
        var swipe = TrackpadSwipe()
        for _ in 0..<6 {
            swipe.moved(dx: 10, dy: 0)
            swipe.answered(free: true)
        }
        XCTAssertEqual(swipe.distance, 60, accuracy: 0.001)
        XCTAssertEqual(swipe.commits(velocity: 0), .back, "60 points on the trackpad is far enough")
        XCTAssertFalse(HistorySwipe.commits(distance: 60, velocity: 0), "a finger across the glass goes further")
        XCTAssertEqual(HistorySwipe.progress(distance: 30, reach: HistorySwipe.trackpadReach), 0.5, accuracy: 0.001)

        var short = TrackpadSwipe()
        for _ in 0..<5 {
            short.moved(dx: 10, dy: 0)
            short.answered(free: true)
        }
        XCTAssertNil(short.commits(velocity: 0), "50 points isn't")
    }

    func testAScrollThatTurnsSidewaysStaysAScroll() {
        var swipe = TrackpadSwipe()
        for _ in 0..<4 {
            swipe.moved(dx: 1, dy: 8)
            swipe.answered(free: true)
        }
        for _ in 0..<20 {
            swipe.moved(dx: 12, dy: 0)
            swipe.answered(free: true)
        }
        XCTAssertNil(swipe.way)
        XCTAssertEqual(swipe.distance, 0)
        XCTAssertNil(swipe.commits(velocity: 3000))
    }

    func testASwipeForwardAndOneTakenBack() {
        var swipe = TrackpadSwipe()
        XCTAssertNil(swipe.way, "nothing before the page has answered")
        for _ in 0..<6 {
            swipe.moved(dx: -10, dy: 0)
            swipe.answered(free: true)
        }
        XCTAssertEqual(swipe.way, .forward)
        XCTAssertEqual(swipe.commits(velocity: -900), .forward, "a flick the same way")
        for _ in 0..<5 {
            swipe.moved(dx: 10, dy: 0)
            swipe.answered(free: true)
        }
        XCTAssertEqual(swipe.distance, 10, accuracy: 0.001)
        XCTAssertNil(swipe.commits(velocity: 900), "back where it began, it goes nowhere")
    }

    func testAMacSwipeIsTakenOnceThePageLeftItsFirstScrollAlone() {
        var swipe = ScrollSwipe(dx: 4, dy: 0, at: 0, open: [.back])
        XCTAssertFalse(swipe.moved(dx: 6, dy: 0.5, at: 0.01), "under the slack it is still the page's")
        XCTAssertFalse(swipe.moved(dx: 8, dy: 0, at: 0.02), "sideways, but the page has yet to answer")
        XCTAssertTrue(swipe.awaitsAnswer)
        XCTAssertNil(swipe.way)
        swipe.firstLeftAlone()
        XCTAssertEqual(swipe.way, .back)
        XCTAssertTrue(swipe.moved(dx: 10, dy: 4, at: 0.03), "from now the fingers are the swipe's")
        XCTAssertEqual(swipe.distance, 28, accuracy: 0.001)
        XCTAssertNil(swipe.commits(velocity: 0))
        for step in 0..<4 { swipe.moved(dx: 8, dy: 0, at: 0.04 + Double(step) / 100) }
        XCTAssertEqual(swipe.distance, 60, accuracy: 0.001)
        XCTAssertEqual(swipe.commits(velocity: 0), .back, "the trackpad's reach")

        var late = ScrollSwipe(dx: -5, dy: 0, at: 0, open: [.back, .forward])
        for step in 1...6 { XCTAssertFalse(late.moved(dx: -5, dy: 0, at: Double(step) / 100)) }
        late.firstLeftAlone()
        XCTAssertEqual(late.way, .forward, "an answer that comes late still counts")
        XCTAssertEqual(late.distance, 35, accuracy: 0.001)
        XCTAssertEqual(late.commits(velocity: -900), .forward, "a flick")
    }

    func testAMacSwipeThePageUsedOrCannotGoIsAScroll() {
        var used = ScrollSwipe(dx: 6, dy: 0, at: 0, open: [.back])
        for step in 1...20 { XCTAssertFalse(used.moved(dx: 6, dy: 0, at: Double(step) / 100)) }
        XCTAssertNil(used.way, "no answer: the page used it")
        XCTAssertNil(used.commits(velocity: 2000))

        var edge = ScrollSwipe(dx: 6, dy: 0, at: 0, open: [.forward])
        edge.firstLeftAlone()
        for step in 1...10 { XCTAssertFalse(edge.moved(dx: 6, dy: 0, at: Double(step) / 100)) }
        XCTAssertTrue(edge.isScroll, "back is not open: not at the page's left edge, or nothing to go back to")
        XCTAssertNil(edge.way)

        var nowhere = ScrollSwipe(dx: 6, dy: 0, at: 0, open: [])
        nowhere.firstLeftAlone()
        XCTAssertTrue(nowhere.isScroll)
        XCTAssertFalse(nowhere.moved(dx: 30, dy: 0, at: 0.01))
    }

    func testAMacScrollThatHeadsDownFirstStaysAScroll() {
        var down = ScrollSwipe(dx: 1, dy: 6, at: 0, open: [.back])
        down.firstLeftAlone()
        down.moved(dx: 2, dy: 12, at: 0.01)
        XCTAssertTrue(down.isScroll)
        XCTAssertFalse(down.moved(dx: 40, dy: 0, at: 0.02))
        XCTAssertNil(down.way)

        var turned = ScrollSwipe(dx: 10, dy: 0, at: 0, open: [.back])
        turned.moved(dx: 10, dy: 0, at: 0.01)
        XCTAssertTrue(turned.awaitsAnswer)
        turned.moved(dx: 0, dy: 15, at: 0.02)
        turned.firstLeftAlone()
        XCTAssertTrue(turned.isScroll, "it turned down before the page answered")
        XCTAssertNil(turned.way)
    }

    func testAMacSwipesFirstScrollMustHeadTheWayItGoes() {
        // A first scroll with nothing sideways in it: that the page left it
        // alone says nothing of a carousel under the fingers, which the
        // scrolls after it may move.
        var still = ScrollSwipe(dx: 0, dy: 0, at: 0, open: [.back, .forward])
        still.firstLeftAlone()
        XCTAssertTrue(still.isScroll)
        XCTAssertFalse(still.moved(dx: -30, dy: 0, at: 0.01))
        XCTAssertNil(still.way)

        var aslant = ScrollSwipe(dx: 2, dy: 1, at: 0, open: [.back])
        aslant.firstLeftAlone()
        XCTAssertTrue(aslant.isScroll, "up or down half as much as sideways: not sideways, as WebKit has it")

        var other = ScrollSwipe(dx: 3, dy: 0, at: 0, open: [.back, .forward])
        other.firstLeftAlone()
        for step in 1...6 { XCTAssertFalse(other.moved(dx: -10, dy: 0, at: Double(step) / 100)) }
        XCTAssertTrue(other.isScroll, "it began back and went forward: the answer was for back")
        XCTAssertNil(other.way)

        var reversed = ScrollSwipe(dx: 18, dy: 0, at: 0, open: [.back])
        XCTAssertTrue(reversed.awaitsAnswer)
        reversed.moved(dx: -80, dy: 0, at: 0.01)
        reversed.firstLeftAlone()
        XCTAssertTrue(reversed.isScroll, "it turned back before the page answered")
        XCTAssertNil(reversed.way)
    }

    func testAMacSwipeTakenBackGoesNowhere() {
        var swipe = ScrollSwipe(dx: 10, dy: 0, at: 0, open: [.back])
        swipe.firstLeftAlone()
        for step in 1...6 { swipe.moved(dx: 10, dy: 0, at: Double(step) / 100) }
        XCTAssertEqual(swipe.commits(velocity: 0), .back)
        for step in 7...20 { XCTAssertTrue(swipe.moved(dx: -10, dy: 0, at: Double(step) / 100), "still the swipe's") }
        XCTAssertEqual(swipe.distance, 0)
        XCTAssertNil(swipe.commits(velocity: 900))
    }

    func testAMacSwipesSpeedIsTheFingersLastMoments() {
        var swipe = ScrollSwipe(dx: 10, dy: 0, at: 0, open: [.back])
        swipe.firstLeftAlone()
        for step in 1...20 { swipe.moved(dx: 10, dy: 0, at: Double(step) / 100) }
        XCTAssertEqual(swipe.speed(at: 0.205), 1000, accuracy: 1, "10 points every hundredth of a second")
        XCTAssertEqual(swipe.speed(at: 0.5), 0, "they had stopped before they left")
        XCTAssertEqual(swipe.commits(velocity: swipe.speed(at: 0.205)), .back)
    }

    func testGlideSlowsAndEnds() {
        var glide = Momentum(velocityX: 0, velocityY: 2000)
        var total = 0.0
        var steps = 0
        var last = Double.infinity
        while let step = glide.advance(by: 1.0 / 60) {
            XCTAssertLessThan(step.y, last)
            last = step.y
            total += step.y
            steps += 1
            XCTAssertLessThan(steps, 10_000)
        }
        XCTAssertTrue(glide.isDone)
        // Under exponential decay the whole glide comes to v / -ln(rate) / 1000.
        let whole = 2000 / (-Foundation.log(0.998) * 1000)
        XCTAssertEqual(total, whole, accuracy: whole * 0.01)
    }

    func testFrameRateDoesNotChangeTheDistance() {
        func distance(_ frame: Double) -> Double {
            var glide = Momentum(velocityX: 1500, velocityY: 0)
            var total = 0.0
            while let step = glide.advance(by: frame) { total += step.x }
            return total
        }
        XCTAssertEqual(distance(1.0 / 60), distance(1.0 / 120), accuracy: 2)
    }

    func testSlowReleaseDoesNotGlide() {
        var glide = Momentum(velocityX: 5, velocityY: 5)
        XCTAssertNil(glide.advance(by: 1.0 / 60))
    }
}

final class ZoomLockTests: XCTestCase {
    func testHeldAtOne() {
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: 1), 1)
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: 1.5), 1)
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: nil), 1)
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: 0), 1)
    }

    func testANarrowWindowKeepsWebKitsFit() {
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: 0.78), 0.78)
    }
}

final class ThrowTests: XCTestCase {
    func testAThrowCarriesAsAScrollViewDecelerates() {
        XCTAssertEqual(Throw.carry(0), 0)
        XCTAssertEqual(Throw.carry(1000), 499, accuracy: 0.001)
        XCTAssertEqual(Throw.carry(-1000), -499, accuracy: 0.001)
    }

    func testTheRubberBandGivesLessAndLessAndNeverReachesItsRange() {
        XCTAssertEqual(Throw.rubberband(0, range: 100), 0)
        XCTAssertEqual(Throw.rubberband(1, range: 100), 0.55, accuracy: 0.01)
        XCTAssertLessThan(Throw.rubberband(10_000, range: 100), 100)
        XCTAssertGreaterThan(Throw.rubberband(10_000, range: 100), 98)
        XCTAssertEqual(Throw.rubberband(-40, range: 100), -Throw.rubberband(40, range: 100))
    }

    func testTheTabSheetFollowsAFlickAndOtherwiseTheThrow() {
        // A flick up opens it from barely started; one down shuts it from nearly open.
        XCTAssertTrue(Throw.opens(progress: 0.05, speed: 400, distance: 600, line: 0.3))
        XCTAssertFalse(Throw.opens(progress: 0.95, speed: -400, distance: 600, line: 0.7))
        // Let go still, it goes to the side of the line it is on.
        XCTAssertTrue(Throw.opens(progress: 0.31, speed: 0, distance: 600, line: 0.3))
        XCTAssertFalse(Throw.opens(progress: 0.29, speed: 0, distance: 600, line: 0.3))
        // A slow push carries it over: 200 points a second goes about 100 points more.
        XCTAssertTrue(Throw.opens(progress: 0.2, speed: 200, distance: 600, line: 0.3))
    }

    func testTheSlideGoesOnlyWhenItWouldRestPastHalfway() {
        // Dragged left 150 of 400, let go still: back. Thrown on: to the tab on the right.
        XCTAssertFalse(Throw.slideGoes(offset: -150, velocity: 0, side: 1, width: 400))
        XCTAssertTrue(Throw.slideGoes(offset: -150, velocity: -300, side: 1, width: 400))
        // Thrown back the other way, it stays.
        XCTAssertFalse(Throw.slideGoes(offset: -250, velocity: 400, side: 1, width: 400))
        XCTAssertTrue(Throw.slideGoes(offset: 250, velocity: 0, side: -1, width: 400))
    }

    func testACardIsThrownAwayButNotBackTheWayItCame() {
        XCTAssertTrue(Throw.cardThrown(x: 120, speed: 0, width: 180, line: 100))
        XCTAssertTrue(Throw.cardThrown(x: 30, speed: 600, width: 180, line: 100))
        XCTAssertFalse(Throw.cardThrown(x: 30, speed: 0, width: 180, line: 100))
        // Past the line but flung back across where it started.
        XCTAssertFalse(Throw.cardThrown(x: 120, speed: -2000, width: 180, line: 100))
    }
}
