@testable import PadCore
import XCTest

/// "Use your Apple passwords?" under a sign-in box: off by default, offered
/// once per site, never again after two unanswered or one ✕, never where it
/// must not be. Search's ApplePasswordsOfferTests (github.com/driceroland/Search,
/// MIT), for eGlu's rules: no accounts of its own, no private tabs.
final class ApplePasswordsOfferTests: XCTestCase {
    private var suite = ""
    private var store: UserDefaults!

    override func setUp() {
        suite = "eglu-apple-offer-\(getpid())-\(UUID().uuidString)"
        store = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suite)
    }

    private let page = URL(string: "https://accounts.example.com/login")!
    /// As a person would have it: the switch off, the helper there.
    private let person = ApplePasswordsOffer.Settings(appleOn: false, helper: true)

    private func field(_ url: URL? = nil, frame: String? = nil, passwords: Bool = true) -> ApplePasswordsOffer.Field {
        .init(page: url ?? page, frameHost: frame, passwords: passwords)
    }

    func testOfferedOnAnHttpsPage() {
        let offer = ApplePasswordsOffer(store: store)
        XCTAssertEqual(offer.site(for: field(), person), "example.com")
        // A frame of the page's own site is the page's.
        XCTAssertEqual(offer.site(for: field(frame: "login.example.com"), person), "example.com")
    }

    func testNeverWhereItMustNotBe() {
        let offer = ApplePasswordsOffer(store: store)
        XCTAssertNil(offer.site(for: field(URL(string: "http://accounts.example.com/login")), person), "http")
        XCTAssertNil(offer.site(for: field(frame: "auth.other.test"), person), "a frame of another site")
        XCTAssertNil(offer.site(for: field(passwords: false), person), "a box for passkeys alone")
        XCTAssertNil(offer.site(for: field(URL(string: "file:///tmp/login.html")), person))
        XCTAssertNil(offer.site(for: field(URL(string: "chrome-extension://abc/popup.html")), person))
        XCTAssertNil(offer.site(for: field(), .init(appleOn: true, helper: true)), "already on")
        XCTAssertNil(offer.site(for: field(), .init(appleOn: false, helper: false)), "no helper, or a build that may not run it")
        XCTAssertTrue(offer.offered.isEmpty, "asking writes nothing down")
    }

    func testOncePerSite() {
        let offer = ApplePasswordsOffer(store: store)
        offer.shown(on: "example.com")
        XCTAssertNil(offer.site(for: field(), person))
        XCTAssertNil(offer.site(for: field(URL(string: "https://www.example.com/")), person), "the same site, another host")
        XCTAssertEqual(offer.site(for: field(URL(string: "https://bank.test/")), person), "bank.test")
    }

    func testTwiceUnansweredAndItStops() {
        let offer = ApplePasswordsOffer(store: store)
        offer.unanswered()
        XCTAssertFalse(offer.retired)
        XCTAssertEqual(offer.site(for: field(), person), "example.com")
        offer.unanswered()
        XCTAssertTrue(offer.retired)
        XCTAssertNil(offer.site(for: field(URL(string: "https://bank.test/")), person))
    }

    func testTheCrossStopsItAtOnce() {
        let offer = ApplePasswordsOffer(store: store)
        offer.dismissed()
        XCTAssertTrue(offer.retired)
        XCTAssertNil(offer.site(for: field(), person))
        offer.forget()
        XCTAssertEqual(offer.site(for: field(), person), "example.com")
    }
}
