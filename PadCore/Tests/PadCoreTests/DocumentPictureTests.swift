import CoreGraphics
import XCTest
@testable import PadCore

final class DocumentPictureTests: XCTestCase {
    func testOnlyListedSitesGetTheAPI() {
        XCTAssertTrue(DocumentPicture.covers(URL(string: "https://meet.google.com/abc-defg-hij")))
        XCTAssertFalse(DocumentPicture.covers(URL(string: "https://www.google.com/")))
        XCTAssertFalse(DocumentPicture.covers(URL(string: "https://example.com/")))
        XCTAssertFalse(DocumentPicture.covers(nil))
        // A test build's own page, and never a hands-off one, whatever is added.
        XCTAssertTrue(DocumentPicture.covers(URL(string: "http://127.0.0.1:8000/Tests/picture.html"), extra: ["127.0.0.1"]))
        XCTAssertFalse(DocumentPicture.covers(URL(string: "https://accounts.google.com/"), extra: ["accounts.google.com"]))
    }

    func testTheMarkersAddressIsReadAndNoOther() {
        XCTAssertEqual(DocumentPicture.Request(url: URL(string: "about:blank#safience-picture")), DocumentPicture.Request())
        XCTAssertEqual(DocumentPicture.Request(url: URL(string: "about:blank#safience-picture&noreturn&initial")),
                       DocumentPicture.Request(returnsToOpener: false, initialPlacement: true))
        XCTAssertEqual(DocumentPicture.Request(url: URL(string: "ABOUT:BLANK#safience-picture&initial")),
                       DocumentPicture.Request(initialPlacement: true))
        for other in ["about:blank", "about:blank#other", "about:blank#safience-pictures", "about:srcdoc#safience-picture",
                      "https://meet.google.com/#safience-picture", "about:blank?x#safience-picture"] {
            XCTAssertNil(DocumentPicture.Request(url: URL(string: other)), other)
        }
        XCTAssertNil(DocumentPicture.Request(url: nil))
    }

    /// The URL WebKit hands over is an NSURL's, which gives no fragment for an
    /// `about:` address; one parsed by Swift does. Both must read the same.
    func testTheMarkerIsReadFromWebKitsKindOfURLToo() throws {
        let fromWebKit = try XCTUnwrap(NSURL(string: "about:blank#safience-picture&noreturn")) as URL
        XCTAssertNil(fromWebKit.fragment, "if NSURL parses the fragment now, this test no longer covers the case")
        XCTAssertEqual(DocumentPicture.Request(url: fromWebKit), DocumentPicture.Request(returnsToOpener: false))
        XCTAssertNil(DocumentPicture.Request(url: NSURL(string: "about:blank#other").map { $0 as URL }))
    }

    func testTheSizeAskedForIsKeptWithinTheScreen() {
        let room = CGSize(width: 1440, height: 900)
        XCTAssertEqual(DocumentPicture.size(width: 400, height: 300, within: room), CGSize(width: 400, height: 300))
        XCTAssertEqual(DocumentPicture.size(width: 10, height: 10, within: room), DocumentPicture.smallest)
        XCTAssertEqual(DocumentPicture.size(width: 5000, height: 5000, within: room), CGSize(width: 1152, height: 720))
        XCTAssertEqual(DocumentPicture.size(width: 320.4, height: 180.6, within: room), CGSize(width: 320, height: 181))
    }

    func testNoSizeOrHalfASizeIsTheStandardOne() {
        let room = CGSize(width: 1440, height: 900)
        XCTAssertEqual(DocumentPicture.size(width: nil, height: nil, within: room), DocumentPicture.standardSize)
        XCTAssertEqual(DocumentPicture.size(width: 600, height: nil, within: room), DocumentPicture.standardSize)
        XCTAssertEqual(DocumentPicture.size(width: 0, height: 0, within: room), DocumentPicture.standardSize)
    }

    func testATinyScreenStillGetsTheSmallestWindow() {
        XCTAssertEqual(DocumentPicture.size(width: 400, height: 300, within: CGSize(width: 200, height: 100)), DocumentPicture.smallest)
    }

    func testItFirstOpensInTheLowerRightCorner() {
        let room = CGRect(x: 0, y: 40, width: 1440, height: 835)
        XCTAssertEqual(DocumentPicture.origin(for: CGSize(width: 480, height: 270), in: room), CGPoint(x: 936, y: 64))
        // A window wider than the room keeps its left edge on the screen.
        XCTAssertEqual(DocumentPicture.origin(for: CGSize(width: 2000, height: 270), in: room).x, 0)
    }
}

final class PictureScriptTests: XCTestCase {
    func testTheScriptShipsAndOpensAtTheMarker() {
        XCTAssertTrue(Scripts.picture.contains("documentPictureInPicture"))
        XCTAssertTrue(Scripts.picture.contains("const marker = '\(DocumentPicture.marker)'"))
        // What DocumentPicture.Request reads is what the script writes.
        for part in ["&noreturn", "&initial"] { XCTAssertTrue(Scripts.picture.contains(part), part) }
        XCTAssertFalse(Scripts.picture.contains("document.cookie"))
    }
}
