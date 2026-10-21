import XCTest
@testable import PadCore

final class ColorSchemeHintTests: XCTestCase {
    private let search = URL(string: "https://www.google.com/search?q=glass")!

    func testAResponseAsksByAcceptCHOrCriticalCH() {
        XCTAssertTrue(ColorSchemeHint.isAsked(acceptCH: "Sec-CH-Prefers-Color-Scheme"))
        XCTAssertTrue(ColorSchemeHint.isAsked(acceptCH: "Sec-CH-UA-Platform, sec-ch-prefers-color-scheme ,Downlink"))
        XCTAssertTrue(ColorSchemeHint.isAsked(acceptCH: nil, criticalCH: "Sec-CH-Prefers-Color-Scheme"))
        XCTAssertFalse(ColorSchemeHint.isAsked(acceptCH: "Sec-CH-Prefers-Reduced-Motion"))
        XCTAssertFalse(ColorSchemeHint.isAsked(acceptCH: nil))
    }

    func testNothingIsSentToAHostThatHasNotAsked() {
        let hint = ColorSchemeHint()
        XCTAssertNil(hint.missing(url: search, method: "GET", headers: [:], dark: true))
    }

    func testAPageThatCameLightOnADarkScreenIsAskedForAgainOnce() {
        var hint = ColorSchemeHint()
        let again = hint.answered(url: search, acceptCH: "Sec-CH-Prefers-Color-Scheme", criticalCH: nil,
                                  requestCarried: false, repeatable: true, dark: true)
        XCTAssertEqual(again, "dark")
        // The request that came again with it is answered as it should be.
        XCTAssertNil(hint.answered(url: search, acceptCH: "Sec-CH-Prefers-Color-Scheme", criticalCH: nil,
                                   requestCarried: true, repeatable: true, dark: true))
    }

    func testOnALightScreenTheLightPageStandsAndTheHostIsKept() {
        var hint = ColorSchemeHint()
        XCTAssertNil(hint.answered(url: search, acceptCH: "Sec-CH-Prefers-Color-Scheme", criticalCH: nil,
                                   requestCarried: false, repeatable: true, dark: false))
        XCTAssertEqual(hint.missing(url: search, method: "GET", headers: nil, dark: false), "light")
        XCTAssertEqual(hint.missing(url: search, method: "GET", headers: nil, dark: true), "dark")
    }

    func testAFormSentOrAStepBackIsNeverSentTwice() {
        var hint = ColorSchemeHint()
        XCTAssertNil(hint.answered(url: search, acceptCH: "Sec-CH-Prefers-Color-Scheme", criticalCH: nil,
                                   requestCarried: false, repeatable: false, dark: true))
        XCTAssertNil(hint.missing(url: search, method: "POST", headers: [:], dark: true))
    }

    func testARequestWithTheHintGoesAsItIs() {
        var hint = ColorSchemeHint()
        _ = hint.answered(url: search, acceptCH: "Sec-CH-Prefers-Color-Scheme", criticalCH: nil,
                          requestCarried: true, repeatable: true, dark: true)
        XCTAssertNil(hint.missing(url: search, method: "GET", headers: ["sec-ch-prefers-color-scheme": "dark"], dark: true))
    }

    func testTheHintIsKeptByHostNotBySite() {
        var hint = ColorSchemeHint()
        _ = hint.answered(url: search, acceptCH: "Sec-CH-Prefers-Color-Scheme", criticalCH: nil,
                          requestCarried: false, repeatable: true, dark: false)
        XCTAssertNil(hint.missing(url: URL(string: "https://mail.google.com/")!, method: "GET", headers: [:], dark: true))
        XCTAssertNil(hint.missing(url: URL(string: "data:text/html,x")!, method: "GET", headers: [:], dark: true))
    }
}
