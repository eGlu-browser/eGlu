import XCTest
@testable import PadCore

final class DownloadNameTests: XCTestCase {
    func testAFreeNameIsTheSitesOwn() {
        XCTAssertEqual(DownloadName.free(for: "report.pdf") { _ in false }, "report.pdf")
    }

    func testATakenNameGetsANumberBeforeItsExtension() {
        let taken: Set = ["report.pdf", "report 2.pdf"]
        XCTAssertEqual(DownloadName.free(for: "report.pdf") { taken.contains($0) }, "report 3.pdf")
        XCTAssertEqual(DownloadName.free(for: "notes") { $0 == "notes" }, "notes 2")
    }

    func testTwoDownloadsOfOneNameGetTwoNames() {
        // The first one's file doesn't exist yet: its name is held for it.
        var given: Set<String> = []
        let first = DownloadName.free(for: "photo.jpg") { given.contains($0) }
        given.insert(first)
        let second = DownloadName.free(for: "photo.jpg") { given.contains($0) }
        XCTAssertEqual([first, second], ["photo.jpg", "photo 2.jpg"])
    }

    func testNamesTheFileSystemTakesForOneAreOne() {
        XCTAssertEqual(DownloadName.key("Report.pdf"), DownloadName.key("report.PDF"))
        XCTAssertEqual(DownloadName.key("caf\u{E9}.txt"), DownloadName.key("cafe\u{301}.txt"))
        let held = Set(["Report.pdf"].map(DownloadName.key))
        XCTAssertEqual(DownloadName.free(for: "report.pdf") { held.contains(DownloadName.key($0)) }, "report 2.pdf")
    }

    func testAPathTheSiteWroteIsCutToItsName() {
        XCTAssertEqual(DownloadName.free(for: "../../etc/passwd") { _ in false }, "passwd")
        XCTAssertEqual(DownloadName.free(for: "") { _ in false }, "Download")
        XCTAssertEqual(DownloadName.free(for: "..") { _ in false }, "Download")
    }
}
