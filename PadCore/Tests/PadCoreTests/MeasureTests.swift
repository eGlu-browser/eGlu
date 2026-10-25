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
            "color": "rgb(255, 255, 255)", "background": "rgb(37, 99, 235)", "radius": "8px",
            "name": "button.primary", "text": "Sign up", "ref": 1,
        ]))
        XCTAssertEqual(details.padding.text, "8px 16px")
        XCTAssertEqual(details.current, "padding 8px 16px; Inter 15px/20px 600; #ffffff on #2563eb; radius 8px")
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
            "color": "rgb(255, 255, 255)", "background": "rgb(37, 99, 235)", "radius": "8px",
            "name": "button.primary", "text": "Sign up", "ref": 1,
        ])!
        let note = MeasureNote(number: 1, details: details, note: "make the padding 12 pixels on each side")
        var other = MeasureNote(number: 2, details: details, note: "a darker blue")
        other.name = "#cta"
        other.text = ""
        let window = MeasureNotes.window(width: 1440, height: 900, zoom: 1)
        let text = MeasureNotes.text(page: "https://example.com/pricing", viewport: window, notes: [other, note])
        XCTAssertEqual(text, """
            Page: https://example.com/pricing
            Window: 1440 by 900, at 100%

            1. button.primary "Sign up", at 120, 340, 96 by 40
               Note: make the padding 12 pixels on each side
               Now: padding 8px 16px; Inter 15px/20px 600; #ffffff on #2563eb; radius 8px

            2. #cta, at 120, 340, 96 by 40
               Note: a darker blue
               Now: padding 8px 16px; Inter 15px/20px 600; #ffffff on #2563eb; radius 8px
            """)
        XCTAssertEqual(MeasureNotes.window(width: 1280.4, height: 720, zoom: 1.25), "1280 by 720, at 125%")
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

    /// Padding and margins as short as CSS's shorthand writes them.
    func testSidesShorthand() {
        typealias Sides = MeasureDetails.Sides
        XCTAssertEqual(Sides(top: 8, right: 8, bottom: 8, left: 8).text, "8px")
        XCTAssertEqual(Sides(top: 8, right: 16, bottom: 8, left: 16).text, "8px 16px")
        XCTAssertEqual(Sides(top: 8, right: 16, bottom: 4, left: 16).text, "8px 16px 4px")
        XCTAssertEqual(Sides(top: 1, right: 2, bottom: 3, left: 4).text, "1px 2px 3px 4px")
        XCTAssertEqual(Sides(top: 0, right: 0, bottom: 0, left: 0).text, "")
        XCTAssertEqual(Sides(top: 0.5, right: 0.5, bottom: 0.5, left: 0.5).text, "0.5px")
    }

    /// A computed colour in hex; none at all is transparent; one with an
    /// alpha, or in another space, as it came.
    func testColoursAsDesignersWriteThem() {
        XCTAssertEqual(MeasureColour.css("rgb(37, 99, 235)"), "#2563eb")
        XCTAssertEqual(MeasureColour.css("rgba(255, 255, 255, 1)"), "#ffffff")
        XCTAssertEqual(MeasureColour.css("rgba(0, 0, 0, 0)"), "transparent")
        XCTAssertEqual(MeasureColour.css("rgba(0, 0, 0, 0.5)"), "rgba(0, 0, 0, 0.5)")
        XCTAssertEqual(MeasureColour.css("color(display-p3 1 0 0)"), "color(display-p3 1 0 0)")
        XCTAssertEqual(MeasureColour.css("#abcdef"), "#abcdef")
        var details = MeasureDetails()
        details.color = "rgb(0, 0, 0)"
        details.background = "rgba(0, 0, 0, 0)"
        XCTAssertEqual(details.current, "#000000")
    }
}
