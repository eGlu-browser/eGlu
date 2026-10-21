import XCTest
@testable import PadCore

/// The tabs along the top: sharing the row, the one on screen wider where it is the address.
final class TabWidthsTests: XCTestCase {
    func testTabsShareTheRowBetweenTheirBounds() {
        XCTAssertEqual(TabWidths.widths(count: 4, room: 812, gap: 4, address: false).each, 200, "an even share")
        XCTAssertEqual(TabWidths.widths(count: 2, room: 1000, gap: 4, address: false).each, TabWidths.widest)
        XCTAssertEqual(TabWidths.widths(count: 20, room: 800, gap: 4, address: false).each, TabWidths.narrowest, "past that, it scrolls")
    }

    func testTheTabThatIsTheAddressHasRoomForIt() {
        let few = TabWidths.widths(count: 3, room: 900, gap: 4, address: true)
        XCTAssertEqual(few.current, 420, "half as wide again as 297, up to its widest")
        XCTAssertEqual(few.each, 236, "the rest share what is left: the row filled")
        let many = TabWidths.widths(count: 12, room: 900, gap: 4, address: true)
        XCTAssertEqual(many.current, TabWidths.addressNarrowest)
        XCTAssertEqual(many.each, TabWidths.narrowest)
        XCTAssertEqual(TabWidths.widths(count: 1, room: 300, gap: 4, address: true).current, 300, "alone, never past the row")
        XCTAssertEqual(TabWidths.widths(count: 0, room: 300, gap: 4, address: true).current, 0)
    }
}
