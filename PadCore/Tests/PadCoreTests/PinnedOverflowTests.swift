import XCTest
@testable import PadCore

/// Pinned tabs past their share of the row go behind a button.
final class PinnedOverflowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_500_000)

    private func pinned(_ count: Int) -> [TabRecord] {
        (0..<count).map { n in
            TabRecord(url: URL(string: "https://site\(n).example"), title: "Site \(n)",
                      shown: now.addingTimeInterval(Double(-n) * 60), pinned: URL(string: "https://site\(n).example"))
        }
    }

    func testAllShowWhileTheyFit() {
        let tabs = pinned(4)
        let split = PinnedOverflow.split(tabs, current: tabs[0].id, live: [], room: 1000, tile: 36, gap: 4)
        XCTAssertEqual(split.shown.count, 4)
        XCTAssertTrue(split.hidden.isEmpty)
    }

    func testUnopenedAndOldestGoFirstAndTheOneOnScreenStays() {
        let tabs = pinned(12)
        // 30% of 600 is 180: four places of 36 and 4, so three tiles and the button.
        let live: Set<UUID> = [tabs[11].id, tabs[5].id]
        let split = PinnedOverflow.split(tabs, current: tabs[9].id, live: live, room: 600, tile: 36, gap: 4)
        XCTAssertEqual(split.shown.map(\.title), ["Site 5", "Site 9", "Site 11"], "the one on screen, then the open ones; in their order")
        XCTAssertEqual(split.hidden.count, 9)
        XCTAssertEqual(split.hidden.first?.title, "Site 0", "behind the button in their order too")

        let unopened = PinnedOverflow.split(tabs, current: nil, live: [], room: 600, tile: 36, gap: 4)
        XCTAssertEqual(unopened.shown.map(\.title), ["Site 0", "Site 1", "Site 2"], "none open: the ones seen last")
    }

    func testTheTabOnScreenStaysWhenThereIsRoomForNoneElse() {
        let tabs = pinned(5)
        let split = PinnedOverflow.split(tabs, current: tabs[4].id, live: [], room: 100, tile: 36, gap: 4)
        XCTAssertEqual(split.shown.map(\.title), ["Site 4"])
        XCTAssertEqual(split.hidden.count, 4)
    }
}
