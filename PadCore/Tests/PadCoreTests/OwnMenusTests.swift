import XCTest
@testable import PadCore

final class OwnMenusTests: XCTestCase {
    func testABuiltInSiteCoversItsHostAndWhatIsUnderIt() {
        let preferences = Preferences()
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "figma.com"))
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "www.figma.com"))
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "embed.figma.com"))
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "acme.atlassian.net"))
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: "notfigma.com"), "a suffix of letters is another site")
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: "en.wikipedia.org"))
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: nil))
    }

    func testAnAppsHostLeavesTheRestOfItsCompanyAlone() {
        let preferences = Preferences()
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "docs.google.com"))
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "mail.google.com"))
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: "www.google.com"), "search results are links like any others")
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: "github.com"))
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "github.dev"))
    }

    func testTheListHasNoHostTwiceAndNoneThatIsNotOne() {
        let hosts = OwnMenus.builtIn.map(\.host)
        XCTAssertEqual(Set(hosts).count, hosts.count)
        for host in hosts {
            XCTAssertEqual(OwnMenus.host(typed: host), host, "\(host) is a plain host, lowercased, without www.")
        }
        XCTAssertFalse(hosts.contains("google.com"))
        XCTAssertFalse(hosts.contains("microsoft.com"))
    }

    func testABuiltInSiteCanBeLetGoAndTakenBack() {
        var preferences = Preferences()
        preferences.setKeepsOwnMenus(false, onHost: "www.figma.com")
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: "figma.com"))
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: "embed.figma.com"), "answered for the site as a whole")
        XCTAssertEqual(preferences.ownMenuSites, ["figma.com": false])
        preferences.setKeepsOwnMenus(true, onHost: "figma.com")
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "figma.com"))
        XCTAssertTrue(preferences.ownMenuSites.isEmpty, "what the list says anyway isn't kept")
    }

    func testASiteOfOnesOwnIsAddedAndRemoved() {
        var preferences = Preferences()
        preferences.setKeepsOwnMenus(true, onHost: "www.example.com")
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "example.com"))
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "app.example.com"), "what is under it too")
        XCTAssertEqual(preferences.addedOwnMenuSites, ["example.com"])
        preferences.setKeepsOwnMenus(false, onHost: "example.com")
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: "example.com"))
        XCTAssertTrue(preferences.ownMenuSites.isEmpty)
        XCTAssertTrue(preferences.addedOwnMenuSites.isEmpty)
    }

    func testTheNearestChoiceWinsAndABroaderOneReplacesThoseUnderIt() {
        var preferences = Preferences()
        preferences.setKeepsOwnMenus(true, onHost: "example.com")
        preferences.ownMenuSites["plain.example.com"] = false
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: "plain.example.com"))
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "app.example.com"))
        preferences.setKeepsOwnMenus(true, onHost: "example.com")
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "plain.example.com"), "the whole site was answered again")
    }

    func testAHostUnderASiteOfOnesOwnCanBeLetGoByItself() {
        var preferences = Preferences()
        preferences.setKeepsOwnMenus(true, onHost: "example.com")
        // From the page's menu, on a part of the site that has no menus of its own.
        preferences.setKeepsOwnMenus(false, onHost: "plain.example.com")
        XCTAssertFalse(preferences.keepsOwnMenus(onHost: "plain.example.com"))
        XCTAssertTrue(preferences.keepsOwnMenus(onHost: "app.example.com"))
        XCTAssertEqual(preferences.ownMenuSites, ["example.com": true, "plain.example.com": false])
        preferences.setKeepsOwnMenus(true, onHost: "plain.example.com")
        XCTAssertEqual(preferences.ownMenuSites, ["example.com": true], "back to what the site above it says")
        // Taking the site away takes what was chosen under it too.
        preferences.setKeepsOwnMenus(false, onHost: "plain.example.com")
        preferences.setKeepsOwnMenus(false, onHost: "example.com")
        XCTAssertTrue(preferences.ownMenuSites.isEmpty)
    }

    func testWhatIsTypedBecomesAHostOrNothing() {
        XCTAssertEqual(OwnMenus.host(typed: " https://WWW.Example.com/app?x=1 "), "example.com")
        XCTAssertEqual(OwnMenus.host(typed: "app.example.com"), "app.example.com")
        XCTAssertNil(OwnMenus.host(typed: "example"))
        XCTAssertNil(OwnMenus.host(typed: "two words.com"))
        XCTAssertNil(OwnMenus.host(typed: ""))
    }

    func testChoicesAreSavedAndOlderSettingsStillRead() throws {
        var preferences = Preferences()
        preferences.setKeepsOwnMenus(true, onHost: "example.com")
        preferences.setKeepsOwnMenus(false, onHost: "figma.com")
        let read = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(read.ownMenuSites, ["example.com": true, "figma.com": false])
        let older = try JSONDecoder().decode(Preferences.self, from: Data(#"{"tabBar":false}"#.utf8))
        XCTAssertTrue(older.ownMenuSites.isEmpty)
        XCTAssertFalse(older.tabBar)
    }
}
