import XCTest
@testable import PadCore

final class SettingsRoutingTests: XCTestCase {
    func testEveryOfferedSearchDestinationHasAReachableCategory() {
        for phone in [false, true] {
            for anchor in SettingsAnchor.allCases where anchor.isOffered(phone: phone) {
                XCTAssertTrue(anchor.group.isOffered(padLayout: !phone, keyboard: false),
                              "Search result \(anchor) must open a visible Settings category")
            }
        }
    }

    func testShortcutsHaveTheirOwnPageAndAppearWhenAKeyboardConnects() {
        XCTAssertEqual(SettingsAnchor.shortcuts.group, .shortcuts)
        XCTAssertEqual(SettingsAnchor.allCases.filter { $0.group == .shortcuts }, [.shortcuts])
        XCTAssertFalse(SettingsGroup.shortcuts.isOffered(padLayout: false, keyboard: false))
        XCTAssertTrue(SettingsGroup.shortcuts.isOffered(padLayout: false, keyboard: true))
        XCTAssertTrue(SettingsGroup.input.isOffered(padLayout: false, keyboard: true))
    }

    /// Developer mode and the diagnostics panel's switch are one group, the
    /// last, offered everywhere; the diagnostics' own row is gated where it
    /// is offered (Device.offers), not by the group.
    func testDeveloperGroupHoldsDiagnostics() {
        XCTAssertEqual(SettingsAnchor.diagnostics.group, .developer)
        XCTAssertEqual(SettingsAnchor.developer.group, .developer)
        XCTAssertEqual(SettingsGroup.allCases.last, .developer)
        XCTAssertTrue(SettingsGroup.developer.isOffered(padLayout: false, keyboard: false))
        XCTAssertEqual(SettingsGroup.allCases.filter {
            $0.isOffered(padLayout: true, keyboard: false)
        }.count, 8)
    }
}
