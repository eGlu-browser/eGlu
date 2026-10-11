import XCTest
@testable import PadCore

final class ShortcutTests: XCTestCase {
    /// ⌃⌥ for every command but the few on keys every browser keeps for itself.
    func testEveryChordIsControlOptionButTheBrowsersOwnAndNamesOneCommand() {
        XCTAssertTrue(Shortcuts.isUnambiguous)
        for command in Command.allCases {
            let chord = Shortcuts.chord(for: command)
            XCTAssertNotNil(chord, command.rawValue)
            XCTAssertEqual(chord?.base == .controlOption, !Shortcuts.reserved.contains(command), command.rawValue)
        }
    }

    func testLabels() {
        XCTAssertEqual(Shortcuts.chord(for: .everything)?.label, "⌃⌥K")
        XCTAssertEqual(Shortcuts.chord(for: .newSpace)?.label, "⌃⌥⇧N")
        XCTAssertEqual(Shortcuts.chord(for: .nextSpace)?.label, "⌃⌥↓")
        XCTAssertEqual(Shortcuts.tabNumbers.first?.label, "⌃⌥1")
    }

    /// The browser's own keys, as Chrome and Safari have them, in Apple's order.
    func testBrowsersOwnKeys() {
        XCTAssertEqual(Shortcuts.chord(for: .newTab)?.label, "⌘T")
        XCTAssertEqual(Shortcuts.chord(for: .reopenTab)?.label, "⇧⌘T")
        XCTAssertEqual(Shortcuts.chord(for: .closeTab)?.label, "⌘W")
        XCTAssertEqual(Shortcuts.chord(for: .newWindow)?.label, "⌘N")
        XCTAssertEqual(Shortcuts.chord(for: .closeWindow)?.label, "⇧⌘W")
        XCTAssertEqual(Shortcuts.chord(for: .nextTab)?.label, "⌃⇥")
        XCTAssertEqual(Shortcuts.chord(for: .previousTab)?.label, "⌃⇧⇥")
    }

    func testEveryCommandHasATitle() {
        for command in Command.allCases {
            XCTAssertFalse(command.title.isEmpty)
        }
    }

    /// The keys one by one, as a cheat sheet draws them, are the label's.
    func testCaps() {
        XCTAssertEqual(Shortcuts.chord(for: .newSpace)?.caps, ["⌃", "⌥", "⇧", "N"])
        XCTAssertEqual(Shortcuts.chord(for: .reopenTab)?.caps, ["⇧", "⌘", "T"])
        XCTAssertEqual(Shortcuts.chord(for: .previousTab)?.caps, ["⌃", "⇧", "⇥"])
        for chord in Array(Shortcuts.chords.values) + Shortcuts.tabNumbers {
            XCTAssertEqual(chord.caps.joined(), chord.label)
        }
    }

    /// Every command is in one menu, and so in the cheat sheet, once.
    func testEveryCommandIsInOneGroup() {
        let grouped = ShortcutGroup.allCases.flatMap(\.commands)
        XCTAssertEqual(grouped.count, Command.allCases.count)
        XCTAssertEqual(Set(grouped), Set(Command.allCases))
    }
}

final class DestinationTests: XCTestCase {
    func testAddressesGoThere() {
        XCTAssertEqual(Destination.url(for: "figma.com", engine: "google")?.absoluteString, "https://figma.com")
        XCTAssertEqual(Destination.url(for: " https://www.figma.com/files ", engine: "google")?.absoluteString, "https://www.figma.com/files")
        XCTAssertEqual(Destination.url(for: "localhost:3000", engine: "google")?.absoluteString, "http://localhost:3000")
        XCTAssertEqual(Destination.url(for: "0.0.0.0:5173", engine: "google")?.absoluteString, "http://localhost:5173")
    }

    func testWordsAreSearched() {
        XCTAssertEqual(Destination.url(for: "auto layout tips", engine: "google")?.absoluteString,
                       "https://www.google.com/search?q=auto%20layout%20tips")
        XCTAssertEqual(Destination.url(for: "figma", engine: "duckduckgo")?.absoluteString, "https://duckduckgo.com/?q=figma")
        XCTAssertEqual(Destination.url(for: "figma", engine: "nonsense")?.host(), "www.google.com")
        XCTAssertNil(Destination.url(for: "   ", engine: "google"))
    }

    func testEnginesOfferedLeaveOutCustom() {
        let ids = Destination.engines.map(\.id)
        XCTAssertTrue(ids.contains("google"))
        XCTAssertFalse(ids.contains("custom"))
    }

    func testRegistrablePartOfAHost() {
        XCTAssertEqual(Destination.registrable("www.figma.com"), "figma.com")
        XCTAssertEqual(Destination.registrable("accounts.google.com"), "google.com")
        XCTAssertEqual(Destination.registrable("acme.okta.com"), "okta.com")
        XCTAssertEqual(Destination.registrable("news.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(Destination.registrable("someone.github.io"), "someone.github.io")
        XCTAssertEqual(Destination.registrable("localhost"), "localhost")
    }
}
