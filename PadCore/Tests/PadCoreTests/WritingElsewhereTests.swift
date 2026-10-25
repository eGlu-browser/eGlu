import XCTest
@testable import PadCore

final class CaretSettleTests: XCTestCase {
    private let lints = [0..<3, 10..<15]

    /// A tracker whose caret moved to `caret` at `time`, after an arrival
    /// elsewhere in the field.
    private func movedIn(to caret: Int, at time: TimeInterval = 0) -> CaretSettle {
        var settle = CaretSettle(caret: 7)
        settle.set(lints: lints, at: time)
        settle.moved(to: caret, at: time, textChanged: false)
        return settle
    }

    func testAVisitAfterTheCaretRests() {
        var settle = CaretSettle(caret: 7)
        XCTAssertNil(settle.set(lints: lints, at: 0))
        XCTAssertNil(settle.moved(to: 1, at: 0, textChanged: false))
        XCTAssertEqual(settle.motion, .moved)
        XCTAssertNil(settle.tick(at: 0.10))
        XCTAssertNil(settle.visited)
        XCTAssertEqual(settle.tick(at: 0.16), .visit(0))
        XCTAssertEqual(settle.visited, 0)
    }

    func testAVisitFiresOnTheNextReadToo() {
        var settle = movedIn(to: 1)
        // The caret stayed through the settle window.
        XCTAssertEqual(settle.moved(to: 1, at: 0.20, textChanged: false), .visit(0))
    }

    func testMovingFromLintToLintEndsTheFirstVisit() {
        var settle = movedIn(to: 1)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertEqual(settle.moved(to: 12, at: 0.30, textChanged: false), .leave)
        XCTAssertEqual(settle.tick(at: 0.50), .visit(1))
    }

    func testLeavingTheLintsEndsTheVisit() {
        var settle = movedIn(to: 1)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertEqual(settle.moved(to: 8, at: 0.30, textChanged: false), .leave)
        XCTAssertNil(settle.tick(at: 1.0))
    }

    func testTypingHidesTheVisitAndOpensNothing() {
        var settle = movedIn(to: 1)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertEqual(settle.moved(to: 2, at: 0.25, textChanged: true), .leave)
        // The caret catching up with the typing is still typing.
        XCTAssertNil(settle.moved(to: 3, at: 0.30, textChanged: false))
        XCTAssertNil(settle.tick(at: 1.0))
    }

    func testASelectionEndsTheVisit() {
        var settle = movedIn(to: 1)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertEqual(settle.moved(to: nil, at: 0.30, textChanged: false), .leave)
    }

    func testACaretRightAfterAWordIsInIt() {
        var settle = movedIn(to: 3)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
    }

    func testARelintWithTheSameRangeKeepsTheVisit() {
        var settle = movedIn(to: 1)
        XCTAssertEqual(settle.tick(at: 0.20), .visit(0))
        XCTAssertNil(settle.set(lints: lints, at: 0.30))
        XCTAssertEqual(settle.set(lints: [0..<4, 10..<15], at: 0.40), .leave)
    }

    // caret_tracker.rs: arriving in a field shows its lints and opens nothing.

    func testArrivingInAFieldOpensNothing() {
        var settle = CaretSettle(caret: 1)
        XCTAssertNil(settle.set(lints: lints, at: 0))
        // The same caret read again is still the arrival.
        XCTAssertNil(settle.moved(to: 1, at: 0.05, textChanged: false))
        XCTAssertNil(settle.tick(at: 1.0))
        XCTAssertEqual(settle.motion, .arrived)
        XCTAssertFalse(settle.isTyping(in: 0..<3))
    }

    func testLintsArrivingUnderARestingCaretOpenAfterAMove() {
        var settle = CaretSettle(caret: 7)
        settle.moved(to: 1, at: 0, textChanged: false)
        // The caret has rested long enough already: it opens at once.
        XCTAssertEqual(settle.set(lints: lints, at: 0.30), .visit(0))

        var early = CaretSettle(caret: 7)
        early.moved(to: 1, at: 0, textChanged: false)
        XCTAssertNil(early.set(lints: lints, at: 0.05))
        XCTAssertEqual(early.tick(at: 0.20), .visit(0))
    }

    func testLintsArrivingAfterTypingOpenNothing() {
        var settle = CaretSettle(caret: 0)
        settle.moved(to: 3, at: 0, textChanged: true)
        XCTAssertNil(settle.set(lints: lints, at: 0.30))
        XCTAssertNil(settle.tick(at: 1.0))
    }

    // caret_tracker.rs: the word being typed is hidden until the caret moves on.

    func testTheWordBeingTypedIsHidden() {
        var settle = CaretSettle(caret: 2)
        settle.moved(to: 3, at: 0, textChanged: true)
        XCTAssertTrue(settle.isTyping(in: 0..<3))
        XCTAssertFalse(settle.isTyping(in: 10..<15))
    }

    func testAWordShowsOnceTheCaretMovesOn() {
        var settle = CaretSettle(caret: 3)
        settle.moved(to: 4, at: 0, textChanged: true)
        XCTAssertFalse(settle.isTyping(in: 0..<3))
    }

    func testNoCaretHidesNothing() {
        var settle = CaretSettle(caret: 3)
        settle.moved(to: nil, at: 0, textChanged: true)
        XCTAssertFalse(settle.isTyping(in: 0..<3))
    }

    func testTypingThenMovingTheCaret() {
        var settle = CaretSettle(caret: 3)
        XCTAssertEqual(settle.motion, .arrived)
        settle.moved(to: 4, at: 0.1, textChanged: true)
        XCTAssertEqual(settle.motion, .typed)
        // A read with nothing new keeps the last answer.
        settle.moved(to: 4, at: 0.4, textChanged: false)
        XCTAssertEqual(settle.motion, .typed)
        settle.moved(to: 1, at: 0.5, textChanged: false)
        XCTAssertEqual(settle.motion, .moved)
        settle.moved(to: 2, at: 0.6, textChanged: true)
        XCTAssertEqual(settle.motion, .typed)
    }

    func testACaretCatchingUpWithTypingIsStillTyping() {
        var settle = CaretSettle(caret: 2)
        // The app reports the new text first and the caret one read later.
        settle.moved(to: 2, at: 0.016, textChanged: true)
        settle.moved(to: 3, at: 0.032, textChanged: false)
        XCTAssertEqual(settle.motion, .typed)
        // Moving the caret once things settle counts.
        settle.moved(to: 1, at: 0.4, textChanged: false)
        XCTAssertEqual(settle.motion, .moved)
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

    func testTheListIsTheCuratedTheSeenAndTheChosen() {
        let listed = WritingApps.listed(seen: ["com.example.seen"], choices: ["com.example.chosen": false])
        XCTAssertTrue(WritingApps.curated.isSubset(of: listed))
        XCTAssertTrue(listed.contains("com.example.seen"))
        XCTAssertTrue(listed.contains("com.example.chosen"))
        XCTAssertFalse(listed.contains("com.example.other"))
    }

    func testRemovingASeenAppForgetsItAndItsChoice() {
        var seen: Set<String> = ["com.example.seen", "com.example.kept"]
        var choices = ["com.example.seen": true, "com.example.kept": false]
        XCTAssertTrue(WritingApps.canRemove("com.example.seen", choices: choices))
        WritingApps.remove("com.example.seen", seen: &seen, choices: &choices)
        XCTAssertEqual(seen, ["com.example.kept"])
        XCTAssertEqual(choices, ["com.example.kept": false])
        XCTAssertFalse(WritingApps.listed(seen: seen, choices: choices).contains("com.example.seen"))
        // Seen again, it is back, off as a new app is.
        seen.insert("com.example.seen")
        XCTAssertTrue(WritingApps.listed(seen: seen, choices: choices).contains("com.example.seen"))
        XCTAssertFalse(WritingApps.isOn("com.example.seen", choices: choices, newApps: false))
    }

    func testRemovingAnAppOnlyChosenTakesItOff() {
        var seen: Set<String> = []
        var choices = ["com.example.chosen": true]
        WritingApps.remove("com.example.chosen", seen: &seen, choices: &choices)
        XCTAssertTrue(choices.isEmpty)
        XCTAssertFalse(WritingApps.listed(seen: seen, choices: choices).contains("com.example.chosen"))
    }

    func testARemovedCuratedAppComesBackAsCurated() {
        var seen: Set<String> = ["com.apple.mail"]
        var choices = ["com.apple.mail": false]
        XCTAssertTrue(WritingApps.canRemove("com.apple.mail", choices: choices))
        WritingApps.remove("com.apple.mail", seen: &seen, choices: &choices)
        XCTAssertTrue(WritingApps.listed(seen: seen, choices: choices).contains("com.apple.mail"))
        XCTAssertTrue(WritingApps.isOn("com.apple.mail", choices: choices, newApps: false))
        // At its default already, there is nothing to take off.
        XCTAssertFalse(WritingApps.canRemove("com.apple.mail", choices: choices))
    }
}

final class WritingSpanTests: XCTestCase {
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

    func testACaretOutsideTheCheckedPartAsksForAnotherRun() {
        let text = (0..<10).map { "p\($0)00\n" }.joined() + "last"
        let length = text.utf16.count
        let region = WritingSpan.region(of: text, caret: 27, limit: 10)
        XCTAssertTrue(WritingSpan.covers(region, caret: 27, length: length))
        XCTAssertTrue(WritingSpan.covers(region, caret: 15, length: length))
        // Right after the region's last break is the next paragraph.
        XCTAssertFalse(WritingSpan.covers(region, caret: region.upperBound, length: length))
        XCTAssertFalse(WritingSpan.covers(region, caret: 2, length: length))
        // The end of the text belongs to the last paragraph.
        let tail = WritingSpan.region(of: text, caret: length, limit: 10)
        XCTAssertTrue(WritingSpan.covers(tail, caret: length, length: length))
        // A short field is checked whole: every caret is in it.
        XCTAssertTrue(WritingSpan.covers(0..<5, caret: 5, length: 5))
    }

    // Lints on a text change: moved with their words, or dropped.

    func testAnEditIsWhatTheTextsDoNotShare() {
        // " big" at 3 or "big " at 4: both ends are kept.
        XCTAssertEqual(WritingSpan.edit(from: "the cat", to: "the big cat"),
                       WritingSpan.Edit(replaced: 4..<4, leftmost: 3..<3, length: 4))
        XCTAssertEqual(WritingSpan.edit(from: "the big cat", to: "the cat"),
                       WritingSpan.Edit(replaced: 4..<8, leftmost: 3..<7, length: 0))
        XCTAssertEqual(WritingSpan.edit(from: "a teh b", to: "a the b"),
                       WritingSpan.Edit(replaced: 3..<5, length: 2))
        XCTAssertEqual(WritingSpan.edit(from: "", to: "hi"),
                       WritingSpan.Edit(replaced: 0..<0, length: 2))
    }

    func testTypingRepeatedCharactersBeforeAWordMovesItsLint() {
        // "a " went in at the start, or after the first "a ": the lint on
        // "teh" moves either way.
        let insert = WritingSpan.edit(from: "a teh", to: "a a teh")
        XCTAssertEqual(WritingSpan.shift(2..<5, by: insert), 4..<7)
        let delete = WritingSpan.edit(from: "a a teh", to: "a teh")
        XCTAssertEqual(WritingSpan.shift(4..<7, by: delete), 2..<5)
        let space = WritingSpan.edit(from: " teh", to: "  teh")
        XCTAssertEqual(WritingSpan.shift(1..<4, by: space), 2..<5)
    }

    func testTypingAboveAFlaggedWordMovesItsLint() {
        let old = "one\nteh"
        let new = "one more\nteh"
        let edit = WritingSpan.edit(from: old, to: new)
        // "teh" was at 4..<7; five units went in before it.
        XCTAssertEqual(WritingSpan.shift(4..<7, by: edit), 9..<12)
        XCTAssertEqual((new as NSString).substring(with: NSRange(location: 9, length: 3)), "teh")
    }

    func testALintBeforeTheEditStays() {
        let edit = WritingSpan.edit(from: "teh cat", to: "teh cats")
        XCTAssertEqual(WritingSpan.shift(0..<3, by: edit), 0..<3)
    }

    func testALintTheEditTouchesGoes() {
        // Typed onto the end of the word: another word now.
        XCTAssertNil(WritingSpan.shift(0..<3, by: WritingSpan.edit(from: "teh", to: "tehs")))
        // Typed into it.
        XCTAssertNil(WritingSpan.shift(0..<3, by: WritingSpan.edit(from: "teh", to: "tseh")))
        // Typed right before it.
        XCTAssertNil(WritingSpan.shift(2..<5, by: WritingSpan.edit(from: "a teh", to: "a xteh")))
    }

    func testShiftingCountsUTF16AfterEmojiAndKorean() {
        // "😀" is two units, each Hangul syllable one.
        let old = "teh"
        let new = "😀 한국어 teh"
        let edit = WritingSpan.edit(from: old, to: new)
        let moved = WritingSpan.shift(0..<3, by: edit)
        XCTAssertNil(moved, "typed right before the word")

        let before = "x teh"
        let after = "😀한 x teh"
        let shifted = WritingSpan.shift(2..<5, by: WritingSpan.edit(from: before, to: after))
        XCTAssertEqual(shifted, 6..<9)
        XCTAssertEqual((after as NSString).substring(with: NSRange(location: 6, length: 3)), "teh")
    }

    func testNoEditMovesNothing() {
        let edit = WritingSpan.edit(from: "same", to: "same")
        XCTAssertEqual(WritingSpan.shift(0..<4, by: edit), 0..<4)
    }
}

final class FieldEditTests: XCTestCase {
    // text_selection.rs's tests.

    func testTypesTextInPiecesWithoutSplittingCharacters() {
        XCTAssertEqual(FieldEdit.typingChunks(""), [])
        XCTAssertEqual(FieldEdit.typingChunks("the"), [Array("the".utf16)])

        let long = String(repeating: "a", count: 19) + "😀" + "b"
        let chunks = FieldEdit.typingChunks(long) ?? []
        // The emoji's two units would make 21, so it starts the next piece.
        XCTAssertEqual(chunks.first?.count, 19)
        XCTAssertEqual(chunks.dropFirst().first, Array("😀b".utf16))
        XCTAssertEqual(chunks.flatMap { $0 }, Array(long.utf16))
    }

    func testKoreanIsTypedWhole() {
        let text = String(repeating: "한국어", count: 10)
        let chunks = FieldEdit.typingChunks(text) ?? []
        XCTAssertEqual(chunks.map(\.count), [20, 10])
        XCTAssertEqual(chunks.flatMap { $0 }, Array(text.utf16))
    }

    func testNeverTypesLineBreaksOrTabs() {
        XCTAssertNil(FieldEdit.typingChunks("one\ntwo"))
        XCTAssertNil(FieldEdit.typingChunks("one\r\ntwo"))
        XCTAssertNil(FieldEdit.typingChunks("one\ttwo"))
        XCTAssertNil(FieldEdit.typingChunks("one\u{2028}two"))
    }

    private func range(_ location: Int, _ length: Int) -> NSRange {
        NSRange(location: location, length: length)
    }

    func testKeepsACaretBeforeTheEdit() {
        XCTAssertEqual(FieldEdit.selection(range(2, 0), after: range(5, 3), insertedLength: 4), range(2, 0))
    }

    func testShiftsACaretAfterTheEdit() {
        XCTAssertEqual(FieldEdit.selection(range(10, 0), after: range(5, 3), insertedLength: 4), range(11, 0))
        XCTAssertEqual(FieldEdit.selection(range(10, 2), after: range(5, 3), insertedLength: 1), range(8, 2))
    }

    func testMovesACaretInsideTheEditToItsEnd() {
        XCTAssertEqual(FieldEdit.selection(range(6, 0), after: range(5, 3), insertedLength: 4), range(9, 0))
    }

    func testMovesACaretAtTheStartOfTheEditToItsEnd() {
        XCTAssertEqual(FieldEdit.selection(range(5, 0), after: range(5, 3), insertedLength: 4), range(9, 0))
        // An insertion: the caret ends up after the inserted text, as if typed.
        XCTAssertEqual(FieldEdit.selection(range(5, 0), after: range(5, 0), insertedLength: 1), range(6, 0))
    }

    func testKeepsASelectionThatEndsWhereTheEditStarts() {
        XCTAssertEqual(FieldEdit.selection(range(1, 4), after: range(5, 3), insertedLength: 4), range(1, 4))
    }

    func testACaretRightAtTheEndOfTheEditMovesWithIt() {
        XCTAssertEqual(FieldEdit.selection(range(8, 0), after: range(5, 3), insertedLength: 4), range(9, 0))
    }
}
