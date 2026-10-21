import XCTest
@testable import PadCore

final class ExtensionStoreTests: XCTestCase {
    private let darkReader = "eimadpbcbfnmbkopoojfekhnkhdbieeh"

    func testAStorePageNamesItsExtensionByItsAddressOnly() throws {
        let page = try XCTUnwrap(URL(string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReader)?hl=en"))
        XCTAssertEqual(ExtensionStore.id(ofPage: page), darkReader)
        XCTAssertEqual(ExtensionStore.id(ofPage: try XCTUnwrap(URL(string: "https://chromewebstore.google.com/detail/\(darkReader)/reviews"))), darkReader)
        XCTAssertEqual(ExtensionStore.id(ofPage: try XCTUnwrap(URL(string: "https://chrome.google.com/webstore/detail/dark-reader/\(darkReader)"))), darkReader)
        // Not over http, not with a name before the host, not another site.
        XCTAssertNil(ExtensionStore.id(ofPage: try XCTUnwrap(URL(string: "http://chromewebstore.google.com/detail/x/\(darkReader)"))))
        XCTAssertNil(ExtensionStore.id(ofPage: try XCTUnwrap(URL(string: "https://me@chromewebstore.google.com/detail/x/\(darkReader)"))))
        XCTAssertNil(ExtensionStore.id(ofPage: try XCTUnwrap(URL(string: "https://chromewebstore.google.com.example.com/detail/x/\(darkReader)"))))
        XCTAssertNil(ExtensionStore.id(ofPage: try XCTUnwrap(URL(string: "https://chromewebstore.google.com/search/\(darkReader)"))))
    }

    func testANameThatLooksLikeAnIDIsntTheID() throws {
        // The page shows the listing whose id comes after the name.
        let name = String(repeating: "a", count: 32)
        XCTAssertEqual(ExtensionStore.id(ofPage: try XCTUnwrap(URL(string: "https://chromewebstore.google.com/detail/\(name)/\(darkReader)"))), darkReader)
    }

    func testAnIDIsFoundInWhateverIsPasted() {
        XCTAssertEqual(ExtensionID.first(in: "  \(darkReader.uppercased())  "), darkReader)
        XCTAssertEqual(ExtensionID.first(in: "https://chromewebstore.google.com/detail/dark-reader/\(darkReader)"), darkReader)
        XCTAssertNil(ExtensionID.first(in: "x" + darkReader), "inside a longer word")
        XCTAssertNil(ExtensionID.first(in: "no id here"))
    }

    func testThePackageAddressAsksForCRX3() throws {
        let url = ExtensionStore.packageURL(for: darkReader)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host(), "clients2.google.com")
        XCTAssertEqual(items.first { $0.name == "response" }?.value, "redirect")
        XCTAssertEqual(items.first { $0.name == "acceptformat" }?.value, "crx3")
        XCTAssertEqual(items.first { $0.name == "x" }?.value, "id=\(darkReader)&installsource=ondemand&uc")
    }

    func testTheUpdateCheckAsksForManyAtOnceAndSplitsLongLists() throws {
        let installed = (0..<60).map { n in (id: ExtensionID.letters([UInt8](repeating: UInt8(n), count: 16)), version: ExtensionVersion("1.0.\(n)")!) }
        let urls = ExtensionStore.updateCheckURLs(for: installed)
        XCTAssertGreaterThan(urls.count, 1)
        XCTAssertTrue(urls.allSatisfy { $0.absoluteString.count <= 2000 })
        let asked = urls.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "x" } ?? [] }
        XCTAssertEqual(asked.count, 60, "every extension once")
        XCTAssertEqual(asked.first?.value, "id=\(installed[0].id)&v=1.0.0&uc")
        XCTAssertNil(urls.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "response" } },
                     "a check gets XML, not a redirect to a file")
    }

    func testVersionsCompareAsChromeDoes() throws {
        func v(_ text: String) throws -> ExtensionVersion { try XCTUnwrap(ExtensionVersion(text), text) }
        XCTAssertLessThan(try v("1.2.9"), try v("1.10"))
        XCTAssertEqual(try v("1.2"), try v("1.2.0.0"))
        XCTAssertEqual(Set([try v("1.2"), try v("1.2.0")]).count, 1)
        XCTAssertLessThan(try v("4.9.110"), try v("2025.10.19.0"))
        XCTAssertEqual(try v("1.02").parts, [1, 2], "a leading zero is fine after the first")
        for bad in ["", "01.2", "1.2.3.4.5", "1..2", "1.-2", "+1", "1.2a", " 1", "4294967296"] {
            XCTAssertNil(ExtensionVersion(bad), bad)
        }
    }

    func testOnlyGooglesHostsMayHandOverAPackage() throws {
        XCTAssertTrue(ExtensionStore.isPackageHost(try XCTUnwrap(URL(string: "https://clients2.googleusercontent.com/crx/blobs/a/b.crx"))))
        XCTAssertTrue(ExtensionStore.isPackageHost(try XCTUnwrap(URL(string: "https://edgedl.me.gvt1.com/edgedl/x.crx"))))
        XCTAssertFalse(ExtensionStore.isPackageHost(try XCTUnwrap(URL(string: "http://clients2.googleusercontent.com/x.crx"))))
        XCTAssertFalse(ExtensionStore.isPackageHost(try XCTUnwrap(URL(string: "https://notgoogle.com/x.crx"))))
        XCTAssertFalse(ExtensionStore.isPackageHost(try XCTUnwrap(URL(string: "https://google.com.evil.example/x.crx"))))
    }

    func testTheUpdateReplyGivesWhatIsNewerWhatIsCurrentAndWhatIsGone() {
        let reply = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gupdate xmlns="http://www.google.com/update2/response" protocol="2.0" server="prod">
          <daystart elapsed_days="7233" elapsed_seconds="44000"/>
          <app appid="\(darkReader)" cohort="1::" status="ok">
            <updatecheck codebase="https://clients2.googleusercontent.com/crx/blobs/AV/X.crx" fp="1.ab" hash_sha256="ABCDEF" protocol="2.0" size="891234" status="ok" version="4.9.110"/>
          </app>
          <app appid="ddkjiahejlhfcafbddmgiahcphecmpfh" status="ok">
            <updatecheck status="noupdate"/>
          </app>
          <app appid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" status="error-unknownApplication"/>
          <app appid="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" status="ok">
            <updatecheck codebase="https://example.com/x.crx" status="ok" version="2.0"/>
          </app>
        </gupdate>
        """
        let updates = ExtensionUpdateReply.parse(Data(reply.utf8))
        XCTAssertEqual(updates.count, 4)
        XCTAssertEqual(updates[0].status, .newer)
        XCTAssertEqual(updates[0].version, ExtensionVersion("4.9.110"))
        XCTAssertEqual(updates[0].sha256, "abcdef")
        XCTAssertEqual(updates[0].size, 891_234)
        XCTAssertEqual(updates[1].status, .current)
        XCTAssertEqual(updates[2].status, .refused("error-unknownApplication"))
        XCTAssertEqual(updates[3].status, .refused("ok"), "a package from anywhere but Google is not taken")
        XCTAssertNil(updates[3].package)
    }

    func testAReplyWithItsNamespaceUnderAPrefixReadsTheSame() {
        let reply = """
        <g:gupdate xmlns:g="http://www.google.com/update2/response" protocol="2.0">
          <g:app appid="\(darkReader)" status="ok"><g:updatecheck status="noupdate"/></g:app>
        </g:gupdate>
        """
        XCTAssertEqual(ExtensionUpdateReply.parse(Data(reply.utf8)).map(\.status), [.current])
        let elsewhere = #"<gupdate xmlns="http://example.com/" protocol="2.0"><app appid="\#(darkReader)"><updatecheck status="noupdate"/></app></gupdate>"#
        XCTAssertEqual(ExtensionUpdateReply.parse(Data(elsewhere.utf8)), [], "not Google's namespace")
        let old = #"<gupdate xmlns="http://www.google.com/update2/response" protocol="3.0"><app appid="\#(darkReader)"><updatecheck status="noupdate"/></app></gupdate>"#
        XCTAssertEqual(ExtensionUpdateReply.parse(Data(old.utf8)), [], "another protocol")
    }

    func testAReplyThatIsntTheStoresGivesNothing() {
        XCTAssertEqual(ExtensionUpdateReply.parse(Data("<html><body>Sorry</body></html>".utf8)), [])
        XCTAssertEqual(ExtensionUpdateReply.parse(Data("not xml".utf8)), [])
    }
}
