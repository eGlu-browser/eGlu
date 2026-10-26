@testable import PadCore
import XCTest

final class ExtensionKeyTests: XCTestCase {
    func testAManifestsSuggestionAsChromeReadsItOnAMac() throws {
        let alt = try XCTUnwrap(ExtensionKey(manifest: "Alt+Shift+Y"))
        XCTAssertEqual(alt.shown, "\u{2325}\u{21E7}Y")
        XCTAssertEqual(ExtensionKey(manifest: "Ctrl+Shift+K")?.modifiers, [.command, .shift])
        XCTAssertEqual(ExtensionKey(manifest: "Command+Period")?.key, ".")
        XCTAssertEqual(ExtensionKey(manifest: "MacCtrl+Comma")?.modifiers, [.control])
        XCTAssertNil(ExtensionKey(manifest: "MediaPlayPause"))
        XCTAssertNil(ExtensionKey(manifest: "Shift+Y"), "a key needs ⌘, ⌥ or ⌃")
        XCTAssertNil(ExtensionKey(manifest: "Alt+Up"))
    }

    func testKeptAndReadBack() throws {
        for key in [ExtensionKey(key: "y", modifiers: [.option, .shift]), ExtensionKey(key: "+", modifiers: [.command]),
                    ExtensionKey(key: "1", modifiers: [.control, .command])] {
            let key = try XCTUnwrap(key)
            XCTAssertEqual(ExtensionKey(stored: key.stored), key, key.stored)
        }
        XCTAssertNil(ExtensionKey(stored: "hyper+y"))
        XCTAssertNil(ExtensionKey(key: "ab", modifiers: [.command]))
    }

    func testTheMacsAndEglusWindowKeysAreNeverAnExtensions() throws {
        for (key, modifiers) in [("q", ExtensionKey.Modifiers.command), ("w", [.command]), ("t", [.command, .shift]), ("n", [.command, .option]),
                                 ("q", [.command, .shift]), ("q", [.command, .option, .shift]), ("q", [.command, .control]), ("h", [.command])] {
            XCTAssertTrue(try XCTUnwrap(ExtensionKey(key: key, modifiers: modifiers)).isReserved, "\(modifiers) \(key)")
        }
        XCTAssertFalse(try XCTUnwrap(ExtensionKey(key: "y", modifiers: [.option, .shift])).isReserved)
        XCTAssertFalse(try XCTUnwrap(ExtensionKey(key: "k", modifiers: [.command, .shift])).isReserved)
    }

    func testSuggestionsAndTheDeveloperMenusKeys() throws {
        XCTAssertEqual(ExtensionKey(suggestedKey: ["default": "Ctrl+Shift+Y", "mac": "MacCtrl+Shift+Y"])?.modifiers, [.control, .shift])
        XCTAssertEqual(ExtensionKey(suggestedKey: ["default": "Alt+Shift+Y"])?.modifiers, [.option, .shift])
        XCTAssertEqual(ExtensionKey(suggestedKey: "Alt+K")?.key, "k")
        XCTAssertNil(ExtensionKey(suggestedKey: nil))
        for (key, modifiers) in [("i", [.control, .option]), ("i", [.command, .option]), ("r", [.control, .option, .shift]),
                                 ("j", [.command, .option]), ("m", [.control, .option])] as [(String, ExtensionKey.Modifiers)] {
            XCTAssertTrue(try XCTUnwrap(ExtensionKey(key: key, modifiers: modifiers)).isReserved, key)
        }
        XCTAssertFalse(try XCTUnwrap(ExtensionKey(key: "y", modifiers: [.option, .shift])).isReserved)
    }

    func testCommandsAManifestDeclares() {
        let manifest = Data(#"{"name": "x", "version": "1", "manifest_version": 3, "default_locale": "en", "commands": {"run": {"description": "__MSG_run__", "suggested_key": {"default": "Alt+Shift+R"}}, "_execute_action": {}}}"#.utf8)
        let commands = ExtensionManifest.commands(json: manifest, in: Data(), untitled: "Tool", locale: "en")
        XCTAssertEqual(commands.map(\.id), ["_execute_action", "run"])
        XCTAssertEqual(commands.first?.title, "Tool", "no description: the name given")
        XCTAssertEqual(commands.last?.suggested?.stored, "opt+shift+r")
    }
}
