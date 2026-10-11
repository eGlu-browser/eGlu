import XCTest
@testable import PadCore

final class AppLinkTests: XCTestCase {
    func testAnotherAppsSchemesAreToldFromPages() {
        for scheme in ["instagram", "mailto", "tel", "itms-apps", "maps", "INSTAGRAM", "intent"] {
            XCTAssertTrue(AppLink.isOne(scheme: scheme), scheme)
        }
        for scheme in ["http", "https", "HTTPS", "about", "data", "blob", "file", "javascript"] {
            XCTAssertFalse(AppLink.isOne(scheme: scheme), scheme)
        }
        XCTAssertFalse(AppLink.isOne(scheme: nil))
        XCTAssertFalse(AppLink.isOne(scheme: ""))
    }

    func testAClickedLinkOpensAtOnce() {
        XCTAssertEqual(AppLink.answer(clicked: true, mainFrame: true, showing: true, asking: false, refusals: 0), .open)
        // In a frame too, and whatever was asked before: the click is the person's.
        XCTAssertEqual(AppLink.answer(clicked: true, mainFrame: false, showing: true, asking: true, refusals: 5), .open)
    }

    func testAPageGoingThereItselfAsksFirst() {
        // A site's "Open in app" button, whose script sets location: no longer dropped.
        XCTAssertEqual(AppLink.answer(clicked: false, mainFrame: true, showing: true, asking: false, refusals: 0), .ask)
    }

    func testOneNoIsASlipAndTwoStand() {
        XCTAssertEqual(AppLink.answer(clicked: false, mainFrame: true, showing: true, asking: false, refusals: 1), .ask,
                       "Cancel by mistake, and the button tried again")
        XCTAssertEqual(AppLink.answer(clicked: false, mainFrame: true, showing: true, asking: false, refusals: 2), .leave,
                       "a page that keeps trying asks twice at most")
    }

    func testNoOneIsAskedByAFrameABackgroundTabOrTwice() {
        XCTAssertEqual(AppLink.answer(clicked: false, mainFrame: false, showing: true, asking: false, refusals: 0), .leave,
                       "an ad's frame")
        XCTAssertEqual(AppLink.answer(clicked: false, mainFrame: true, showing: false, asking: false, refusals: 0), .leave,
                       "a tab that isn't on screen")
        XCTAssertEqual(AppLink.answer(clicked: false, mainFrame: true, showing: true, asking: true, refusals: 0), .leave,
                       "one question at a time")
    }
}
