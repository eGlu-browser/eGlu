import XCTest
@testable import PadCore

/// Whether a page stands clear of the phone's bar or runs on under it
/// (FootRoom). The sizes are an iPhone 17 Pro Max's: 894 points of window
/// for the page, of which the bar and the home indicator cover 138.
final class FootRoomTests: XCTestCase {
    private func clear(_ content: Double, standing: Bool = false, window: Double = 894, covered: Double = 138) -> Bool {
        FootRoom.standsClear(content: content, window: window, covered: covered, standing: standing)
    }

    func testAPageToScrollRunsUnderTheBar() {
        // Taller than the window: its end comes up over the bar as it is scrolled.
        XCTAssertFalse(clear(2_682))
        XCTAssertFalse(clear(896))
        // And one that stood clear runs under again once it has grown past the window.
        XCTAssertFalse(clear(2_682, standing: true))
        XCTAssertFalse(clear(896, standing: true))
    }

    func testAPageThatOnlyFillsTheWindowStandsClear() {
        // Built to the window's height (100vh), which is the whole view's.
        XCTAssertTrue(clear(894))
        // A little shorter than the window, with its foot under the bar and nothing to scroll by.
        XCTAssertTrue(clear(800))
        XCTAssertTrue(clear(758))
        // Within a point of the window's height either way is the window's height.
        XCTAssertTrue(clear(894.6))
    }

    func testAPageThatShowsWholeAboveTheBarIsLeftAsItIs() {
        // All of it shows above the bar: nothing is gained by moving it.
        XCTAssertFalse(clear(756))
        XCTAssertFalse(clear(756.5))
        XCTAssertFalse(clear(300))
    }

    func testOnceClearItStaysSoWhileItWouldFitTheWindow() {
        // Standing clear it is laid out in the window less the bar, and fills that: it does not go back for it.
        XCTAssertTrue(clear(756, standing: true))
        XCTAssertTrue(clear(300, standing: true))
        // Nor when it has a little to scroll by in the smaller window.
        XCTAssertTrue(clear(850, standing: true))
        XCTAssertTrue(clear(894, standing: true))
    }

    func testThereIsNoStandingClearWithoutABar() {
        // An iPad's window, or a phone's while its bar is put away.
        XCTAssertFalse(clear(894, covered: 0))
        XCTAssertFalse(clear(894, standing: true, covered: 0))
        // Nor before the window has a size, or the page a height.
        XCTAssertFalse(clear(100, window: 0))
        XCTAssertFalse(clear(100, window: 100, covered: 138))
        XCTAssertFalse(clear(0))
    }
}
