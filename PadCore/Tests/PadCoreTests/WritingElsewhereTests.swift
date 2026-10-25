import XCTest
@testable import PadCore

final class CaretSettleTests: XCTestCase {
    private let lints = [0..<3, 10..<15]

    func testAVisitAfterTheCaretRests() {
        var settle = CaretSettle()
        XCTAssertNil(settle.set(lints: lints, at: 0))
        XCTAssertNil(settle.moved(to: 1, at: 0, textChanged: false))
        XCTAssertNil(settle.tick(at: 0.10))
        XCTAssertEqual(settle.tick(at: 0.16), .visit(0))
    }

    func testAVisitFiresOnTheNextReadToo() {
        var settle = CaretSettle()
        settle.set(lints: lints, at: 0)
        settle.moved(to: 1, at: 0, textChanged: false)
        // The caret stayed through the settle window.
        XCTAssertEqual(settle.moved(to: 1, at: 0.20, textChanged: false), .visit(0))
    }

    func testMovingFromLintToLintEndsTheFirstVisit() {
        var settle = CaretSettle()
        settle.set(lints: lints, at: 0)
        settle.moved(to: 1, at: 0, textChanged: false)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertEqual(settle.moved(to: 12, at: 0.30, textChanged: false), .leave)
        XCTAssertEqual(settle.tick(at: 0.50), .visit(1))
    }

    func testLeavingTheLintsEndsTheVisit() {
        var settle = CaretSettle()
        settle.set(lints: lints, at: 0)
        settle.moved(to: 1, at: 0, textChanged: false)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertEqual(settle.moved(to: 8, at: 0.30, textChanged: false), .leave)
        XCTAssertNil(settle.tick(at: 1.0))
    }

    func testTypingHidesTheVisitAndOpensNothing() {
        var settle = CaretSettle()
        settle.set(lints: lints, at: 0)
        settle.moved(to: 1, at: 0, textChanged: false)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertEqual(settle.moved(to: 2, at: 0.25, textChanged: true), .leave)
        // The caret catching up with the typing is still typing.
        XCTAssertNil(settle.moved(to: 3, at: 0.30, textChanged: false))
        XCTAssertNil(settle.tick(at: 1.0))
    }

    func testASelectionEndsTheVisit() {
        var settle = CaretSettle()
        settle.set(lints: lints, at: 0)
        settle.moved(to: 1, at: 0, textChanged: false)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertEqual(settle.moved(to: nil, at: 0.30, textChanged: false), .leave)
    }

    func testACaretRightAfterAWordIsInIt() {
        var settle = CaretSettle()
        settle.set(lints: lints, at: 0)
        settle.moved(to: 3, at: 0, textChanged: false)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
    }

    func testARelintWithTheSameRangeKeepsTheVisit() {
        var settle = CaretSettle()
        settle.set(lints: lints, at: 0)
        settle.moved(to: 1, at: 0, textChanged: false)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertNil(settle.set(lints: lints, at: 0.30))
        XCTAssertEqual(settle.set(lints: [0..<4, 10..<15], at: 0.40), .leave)
    }
}

final class WritingAppsTests: XCTestCase {
    func testTheCuratedAppsAreOn() {
        for id in ["com.apple.TextEdit", "com.apple.mail", "com.apple.MobileSMS",
                   "com.apple.Notes", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
                   "com.bloombuilt.dayone-mac"] {
            XCTAssertTrue(WritingApps.isOn(id, choices: [:], newApps: false), id)
        }
    }

    func testAnUnknownAppIsOffUntilNewAppsIsOn() {
        XCTAssertFalse(WritingApps.isOn("com.example.any", choices: [:], newApps: false))
        XCTAssertTrue(WritingApps.isOn("com.example.any", choices: [:], newApps: true))
    }

    func testAPersonsChoiceWinsOverTheDefaults() {
        XCTAssertFalse(WritingApps.isOn("com.apple.TextEdit",
                                        choices: ["com.apple.TextEdit": false], newApps: false))
        XCTAssertTrue(WritingApps.isOn("com.example.any",
                                       choices: ["com.example.any": true], newApps: false))
    }

    func testHarperDesktopIsNeverChecked() {
        XCTAssertTrue(WritingApps.neverChecked.contains("com.elijahpotter.harper-desktop"))
    }
}

final class WritingSpanTests: XCTestCase {
    func testClip() {
        XCTAssertEqual(WritingSpan.clip(2..<5, toLength: 10), 2..<5)
        XCTAssertEqual(WritingSpan.clip(8..<12, toLength: 10), 8..<10)
        XCTAssertEqual(WritingSpan.clip(10..<12, toLength: 10), 0..<0)
        XCTAssertEqual(WritingSpan.clip(0..<4, toLength: 3), 0..<3)
    }

    func testAShortFieldIsLintedWhole() {
        let text = "one\ntwo\nthree"
        XCTAssertEqual(WritingSpan.region(of: text, caret: 0, limit: 50_000), 0..<13)
        XCTAssertEqual(WritingSpan.region(of: "", caret: 0, limit: 50_000), 0..<0)
    }

    func testALongFieldLintsAroundTheCaret() {
        // Ten paragraphs of "0000\n" (5 units each) plus a last line.
        let text = (0..<10).map { "p\($0)00\n" }.joined() + "last"
        let limit = 10
        // Caret in paragraph 5 ("p500\n" at units 25..<30): paragraphs 3 to 7.
        XCTAssertEqual(WritingSpan.region(of: text, caret: 27, limit: limit), 15..<40)
        // Near the start and the end the window clamps.
        XCTAssertEqual(WritingSpan.region(of: text, caret: 1, limit: limit), 0..<15)
        XCTAssertEqual(WritingSpan.region(of: text, caret: 52, limit: limit), 40..<54)
    }

    func testTheRegionCountsUTF16NotCharacters() {
        // Paragraphs joined: "😀\n" is 3 UTF-16 units (surrogate pair + break).
        let text = "😀\n한국어\nok"
        let limit = 5
        // Caret in the Korean paragraph (units 3..<7): all three paragraphs.
        let region = WritingSpan.region(of: text, caret: 5, limit: limit)
        XCTAssertEqual(region, 0..<(text as NSString).length)
        XCTAssertEqual((text as NSString).length, 9)
    }

    func testACaretOnALineBreakBelongsToTheNextParagraph() {
        let text = "aaaa\nbbbb\ncccc\ndddd\neeee\nffff"
        // The caret at unit 5 is right on the first break: the second
        // paragraph is where typing would land, so the window centres there.
        XCTAssertEqual(WritingSpan.region(of: text, caret: 5, limit: 10), 0..<20)
    }
}
