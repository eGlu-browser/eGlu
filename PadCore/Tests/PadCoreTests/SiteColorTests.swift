import XCTest
@testable import PadCore

final class SiteColorTests: XCTestCase {
    func testAverageOfOpaquePixels() throws {
        // Two pixels, RGBA: pure red and pure blue.
        let color = try XCTUnwrap(SiteColor.average(rgba: [255, 0, 0, 255, 0, 0, 255, 255]))
        XCTAssertEqual(color.red, 0.5, accuracy: 0.01)
        XCTAssertEqual(color.green, 0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.5, accuracy: 0.01)
    }

    func testSeeThroughPixelsDontCount() throws {
        let color = try XCTUnwrap(SiteColor.average(rgba: [255, 255, 255, 255, 0, 0, 0, 0]))
        XCTAssertEqual(color.red, 1, accuracy: 0.01)
        XCTAssertNil(SiteColor.average(rgba: [0, 0, 0, 0]))
        XCTAssertNil(SiteColor.average(rgba: []))
        XCTAssertNil(SiteColor.average(rgba: [1, 2, 3]))
    }

    func testAShadesDifferenceIsTheSameGroundAndAChangeOfInkNeverIs() {
        let white = SiteColor(red: 1, green: 1, blue: 1)
        XCTAssertTrue(white.isNear(SiteColor(red: 0.98, green: 0.97, blue: 0.99)))
        XCTAssertFalse(white.isNear(SiteColor(red: 0.9, green: 1, blue: 1)), "a tint you can see")
        XCTAssertFalse(white.isNear(SiteColor(red: 0.1, green: 0.1, blue: 0.1)))
        // Either side of where the ink turns, however close: the bar's controls change.
        var grey = 0.0
        while !SiteColor(red: grey, green: grey, blue: grey).isDark || SiteColor(red: grey + 0.01, green: grey + 0.01, blue: grey + 0.01).isDark {
            grey += 0.01
        }
        let dark = SiteColor(red: grey, green: grey, blue: grey), light = SiteColor(red: grey + 0.01, green: grey + 0.01, blue: grey + 0.01)
        XCTAssertTrue(dark.isDark && !light.isDark)
        XCTAssertFalse(dark.isNear(light))
    }

    func testDarkColoursGetLightText() {
        XCTAssertTrue(SiteColor(red: 0.12, green: 0.12, blue: 0.12).isDark)      // Figma's dark UI
        XCTAssertTrue(SiteColor(red: 0.29, green: 0.08, blue: 0.29).isDark)      // Slack's aubergine
        XCTAssertFalse(SiteColor(red: 1, green: 1, blue: 1).isDark)
        XCTAssertFalse(SiteColor(red: 0.96, green: 0.96, blue: 0.96).isDark)
        XCTAssertFalse(SiteColor(red: 1, green: 0.8, blue: 0).isDark)            // a bright yellow
    }
}
