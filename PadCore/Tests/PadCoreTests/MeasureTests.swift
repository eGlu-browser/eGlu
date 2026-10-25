import XCTest
@testable import PadCore

final class MeasureTests: XCTestCase {
    /// The details message's body becomes MeasureDetails, the "Now:" of a
    /// note read from it as the spec writes it.
    func testDetailsAndCurrent() throws {
        let details = try XCTUnwrap(MeasureDetails(body: [
            "kind": "details", "tag": "button", "id": "", "classes": ["inner", "primary"],
            "width": 96, "height": 40, "x": 120, "y": 340,
            "margin": ["top": 0, "right": 0, "bottom": 0, "left": 0],
            "padding": ["top": 8, "right": 16, "bottom": 8, "left": 16],
            "border": ["top": 0, "right": 0, "bottom": 0, "left": 0],
            "display": "block", "gap": ["row": "normal", "column": "normal"],
            "font": ["family": "Inter", "size": "15px", "weight": "600",
                     "lineHeight": "20px", "letterSpacing": "normal"],
            "color": "#ffffff", "background": "#2563eb", "radius": "8px",
            "name": "button.primary", "text": "Sign up", "ref": 1,
        ]))
        XCTAssertEqual(details.padding.text, "8px 16px 8px 16px")
        XCTAssertEqual(details.current, "padding 8px 16px 8px 16px; Inter 15px/20px 600; #ffffff on #2563eb; radius 8px")
        // Not a details message: nothing.
        XCTAssertNil(MeasureDetails(body: ["kind": "ended"]))
    }

    /// The notes read as plain text an assistant can act on: headed by the
    /// page and its viewport, each numbered, named, placed, sized and told.
    func testNotesText() throws {
        let details = MeasureDetails(body: [
            "kind": "details", "tag": "button", "classes": ["primary"],
            "width": 96, "height": 40, "x": 120, "y": 340,
            "padding": ["top": 8, "right": 16, "bottom": 8, "left": 16],
            "border": [:], "margin": [:],
            "font": ["family": "Inter", "size": "15px", "weight": "600", "lineHeight": "20px"],
            "color": "#ffffff", "background": "#2563eb", "radius": "8px",
            "name": "button.primary", "text": "Sign up", "ref": 1,
        ])!
        let note = MeasureNote(number: 1, details: details, note: "Wider for thumbs.")
        let text = MeasureNotes.text(page: "https://shop.example/p", viewport: "1440 × 900 at 100%", notes: [note])
        XCTAssertEqual(text, """
            Notes on https://shop.example/p
            Viewport: 1440 × 900 at 100%
            1. button.primary "Sign up", at 120, 340, 96 by 40
               Note: Wider for thumbs.
               Now: padding 8px 16px 8px 16px; Inter 15px/20px 600; #ffffff on #2563eb; radius 8px
            """)
    }

    /// A distance message, both kinds: between facing sides, and the insets
    /// of one inside another.
    func testDistance() throws {
        let apart = try XCTUnwrap(MeasureDistance(body: [
            "kind": "distance", "target": "div#aside", "inside": false, "dx": 24.0, "dy": 88.0,
        ]))
        XCTAssertFalse(apart.inside)
        XCTAssertEqual(apart.dx, 24)
        XCTAssertEqual(apart.dy, 88)
        let held = try XCTUnwrap(MeasureDistance(body: [
            "kind": "distance", "target": "div", "inside": true,
            "insets": ["top": 8, "right": 20, "bottom": 30, "left": 12],
        ]))
        XCTAssertTrue(held.inside)
        XCTAssertEqual(held.insets.left, 12)
        XCTAssertNil(MeasureDistance(body: ["kind": "details"]))
    }

    /// The guide settings become the script's argument and back out of
    /// preferences.
    func testGuides() {
        var preferences = Preferences()
        preferences.measureColumns = 8
        preferences.measureRow = 4
        let guides = MeasureGuides(preferences: preferences)
        XCTAssertEqual(guides.columns, 8)
        XCTAssertEqual(guides.argument["row"] as? Double, 4)
        XCTAssertEqual(guides.argument["rulers"] as? Bool, true)
    }
}
