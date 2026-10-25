import XCTest
@testable import PadCore

final class DeveloperModeTests: XCTestCase {
    /// This machine and the local network, where developer mode turns on
    /// by itself.
    func testIsLocal() {
        XCTAssertTrue(Address.isLocal(host: "localhost"))
        XCTAssertTrue(Address.isLocal(host: "app.localhost"))
        XCTAssertTrue(Address.isLocal(host: "printer.local"))
        XCTAssertTrue(Address.isLocal(host: "127.0.0.1"))
        XCTAssertTrue(Address.isLocal(host: "0.0.0.0"))
        XCTAssertTrue(Address.isLocal(host: "::1"))
        XCTAssertTrue(Address.isLocal(host: "[::1]"))
        XCTAssertTrue(Address.isLocal(host: "192.168.1.20"))
        XCTAssertTrue(Address.isLocal(host: "10.0.0.4"))
        XCTAssertTrue(Address.isLocal(host: "172.16.0.1"))
        XCTAssertFalse(Address.isLocal(host: "172.32.0.1"))
        XCTAssertFalse(Address.isLocal(host: "example.com"))
        XCTAssertFalse(Address.isLocal(host: "localhostal.com"))
        XCTAssertTrue(Address.isLocal(host: "LOCALHOST"))
        XCTAssertTrue(Address.isLocal(host: "127.0.0.2"))
        XCTAssertTrue(Address.isLocal(host: "169.254.10.1"))
        // Names that only start like a private address are somebody's site.
        XCTAssertFalse(Address.isLocal(host: "10.example.com"))
        XCTAssertFalse(Address.isLocal(host: "192.168.example.com"))
        XCTAssertFalse(Address.isLocal(host: "172.16.example.com"))
        XCTAssertFalse(Address.isLocal(host: "10.0.0.256"))
        XCTAssertFalse(Address.isLocal(host: "11.0.0.1"))
        XCTAssertFalse(Address.isLocal(host: "0.1.2.3"))
        // IPv6: this machine, every address, the unique local range and a link's own.
        XCTAssertTrue(Address.isLocal(host: "::"))
        XCTAssertTrue(Address.isLocal(host: "fd12:3456:789a::1"))
        XCTAssertTrue(Address.isLocal(host: "[fc00::1]"))
        XCTAssertTrue(Address.isLocal(host: "fe80::1"))
        XCTAssertTrue(Address.isLocal(host: "fe80::1%en0"))
        XCTAssertTrue(Address.isLocal(host: "[FEBF::1]"))
        XCTAssertFalse(Address.isLocal(host: "fec0::1"))
        XCTAssertFalse(Address.isLocal(host: "2001:db8::1"))
        XCTAssertFalse(Address.isLocal(host: "[2606:4700::1111]"))
        XCTAssertFalse(Address.isLocal(host: "fd.example.com"))
    }

    /// What is typed as a local address gets http, a name that only looks
    /// like one https.
    func testTypedLocalAddresses() {
        XCTAssertEqual(Address.url(from: "10.0.0.4:8080")?.absoluteString, "http://10.0.0.4:8080")
        XCTAssertEqual(Address.url(from: "10.example.com")?.absoluteString, "https://10.example.com")
        XCTAssertEqual(Address.url(from: "printer.local")?.absoluteString, "http://printer.local")
    }

    /// A local site has developer mode on, any other site off, until the
    /// site itself has chosen.
    func testIsOn() {
        let local = URL(string: "http://localhost:5173/app")!
        XCTAssertTrue(DeveloperMode.isOn(local, choices: [:], local: true))
        XCTAssertFalse(DeveloperMode.isOn(local, choices: [:], local: false))
        // Chosen for the site, the choice stands, either way.
        XCTAssertFalse(DeveloperMode.isOn(local, choices: ["localhost": false], local: true))
        XCTAssertTrue(DeveloperMode.isOn(local, choices: ["localhost": true], local: false))
        let remote = URL(string: "https://example.com/page")!
        XCTAssertFalse(DeveloperMode.isOn(remote, choices: [:], local: true))
        XCTAssertTrue(DeveloperMode.isOn(remote, choices: ["example.com": true], local: true))
        // The site's key is its host without www., as its other choices'.
        XCTAssertTrue(DeveloperMode.isOn(URL(string: "https://www.example.com")!,
                                         choices: ["example.com": true], local: false))
        XCTAssertFalse(DeveloperMode.isOn(nil, choices: [:], local: true))
        XCTAssertFalse(DeveloperMode.isOn(URL(string: "about:blank")!, choices: [:], local: true))
    }

    /// The settings round-trip and take their defaults where none are saved.
    func testPreferences() throws {
        var preferences = Preferences()
        XCTAssertEqual(preferences.developerSites, [:])
        XCTAssertTrue(preferences.formatJSON)
        XCTAssertEqual(preferences.developerKeys, .controlOption)
        XCTAssertTrue(preferences.developerLocal)

        preferences.developerSites = ["example.com": true]
        preferences.formatJSON = false
        preferences.developerKeys = .optionCommand
        preferences.developerLocal = false
        let data = try JSONEncoder().encode(preferences)
        let back = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(back, preferences)

        let fresh = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertTrue(fresh.formatJSON)
        XCTAssertEqual(fresh.developerKeys, .controlOption)
    }

    /// The six developer commands: five move with the keys setting, the
    /// site's switch stays put on ⌃⌥⇧V.
    func testDeveloperCommands() {
        XCTAssertEqual(Shortcuts.chord(for: .inspector)?.label, "⌃⌥I")
        XCTAssertEqual(Shortcuts.chord(for: .console)?.label, "⌃⌥J")
        XCTAssertEqual(Shortcuts.chord(for: .selectElement)?.label, "⌃⌥C")
        XCTAssertEqual(Shortcuts.chord(for: .elementPicture)?.label, "⌃⌥E")
        XCTAssertEqual(Shortcuts.chord(for: .reloadOrigin)?.label, "⌃⌥⇧R")
        XCTAssertEqual(Shortcuts.chord(for: .developerMode)?.label, "⌃⌥⇧V")
        XCTAssertEqual(Shortcuts.developer, [.inspector, .console, .selectElement, .elementPicture, .reloadOrigin])
        XCTAssertEqual(ShortcutGroup.developer.commands,
                       [.inspector, .console, .selectElement, .elementPicture, .reloadOrigin, .developerMode])
    }

    /// A response's MIME type is JSON itself or a +json kind.
    func testIsJSON() {
        XCTAssertTrue(DeveloperMode.isJSON(mimeType: "application/json"))
        XCTAssertTrue(DeveloperMode.isJSON(mimeType: "application/activity+json"))
        XCTAssertTrue(DeveloperMode.isJSON(mimeType: "Application/JSON"))
        XCTAssertFalse(DeveloperMode.isJSON(mimeType: "text/jsonx"))
        XCTAssertFalse(DeveloperMode.isJSON(mimeType: "text/html"))
        XCTAssertFalse(DeveloperMode.isJSON(mimeType: nil))
    }

    /// The picked element's rectangle in the view's points: as it is at
    /// 100%, scaled where a CSS pixel takes more or fewer points, moved by
    /// where a pinch has the visible part start, clipped to the view.
    func testPickedRect() {
        let view = CGSize(width: 800, height: 600)
        let plain: [String: Any] = ["x": 100.0, "y": 50.0, "width": 200.0, "height": 40.0,
                                    "viewportX": 0.0, "viewportY": 0.0, "viewportWidth": 800.0]
        XCTAssertEqual(DeveloperMode.pickedRect(plain, view: view), CGRect(x: 84, y: 34, width: 232, height: 72))
        // Zoomed to 200%: the page is 400 CSS pixels wide in 800 points.
        var zoomed = plain
        zoomed["viewportWidth"] = 400.0
        XCTAssertEqual(DeveloperMode.pickedRect(zoomed, view: view), CGRect(x: 184, y: 84, width: 432, height: 112))
        // Pinched in and moved along: the visible part starts at 50, 20.
        var pinched = zoomed
        pinched["viewportX"] = 50.0
        pinched["viewportY"] = 20.0
        XCTAssertEqual(DeveloperMode.pickedRect(pinched, view: view), CGRect(x: 84, y: 44, width: 432, height: 112))
        // A desktop page scaled down to fit: 1600 CSS pixels in 800 points.
        var desktop = plain
        desktop["viewportWidth"] = 1600.0
        XCTAssertEqual(DeveloperMode.pickedRect(desktop, view: view), CGRect(x: 34, y: 9, width: 132, height: 52))
        // Partly off screen: clipped; wholly off: nothing.
        var edge = plain
        edge["x"] = 700.0
        XCTAssertEqual(DeveloperMode.pickedRect(edge, view: view), CGRect(x: 684, y: 34, width: 116, height: 72))
        edge["x"] = 2000.0
        XCTAssertNil(DeveloperMode.pickedRect(edge, view: view))
        // Escape, and an answer without a viewport (taken as the view's width).
        XCTAssertNil(DeveloperMode.pickedRect(nil, view: view))
        XCTAssertNil(DeveloperMode.pickedRect(NSNull(), view: view))
        let bare: [String: Any] = ["x": 10, "y": 10, "width": 10, "height": 10]
        XCTAssertEqual(DeveloperMode.pickedRect(bare, view: view, margin: 0), CGRect(x: 10, y: 10, width: 10, height: 10))
    }

    /// The JSON view's button has the app's word written in, and the
    /// scripts are there to run.
    func testDeveloperScripts() {
        XCTAssertFalse(Scripts.jsonView.contains(Scripts.wordsMark))
        XCTAssertTrue(Scripts.jsonView.contains(#"{"raw":"Raw"}"#))
        XCTAssertTrue(Scripts.elementPick.contains("visualViewport"))
    }

    /// The text that asks for the Mac's local servers, and which ports it names.
    func testLocalServerDigits() {
        XCTAssertEqual(DeveloperMode.localServerDigits("local"), "")
        XCTAssertEqual(DeveloperMode.localServerDigits(" Localhost "), "")
        XCTAssertEqual(DeveloperMode.localServerDigits(":"), "")
        XCTAssertEqual(DeveloperMode.localServerDigits(":51"), "51")
        XCTAssertEqual(DeveloperMode.localServerDigits("localhost:5173"), "5173")
        XCTAssertEqual(DeveloperMode.localServerDigits("80"), "80")
        XCTAssertNil(DeveloperMode.localServerDigits(""))
        XCTAssertNil(DeveloperMode.localServerDigits("locale"))
        XCTAssertNil(DeveloperMode.localServerDigits("localhost:abc"))
        XCTAssertNil(DeveloperMode.localServerDigits(":5a"))
        XCTAssertNil(DeveloperMode.localServerDigits("123456"))
        XCTAssertNil(DeveloperMode.localServerDigits("٣٠٠٠"))
        XCTAssertNil(DeveloperMode.localServerDigits("example.com"))
    }
}
