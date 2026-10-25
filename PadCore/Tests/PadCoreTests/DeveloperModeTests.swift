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
}
