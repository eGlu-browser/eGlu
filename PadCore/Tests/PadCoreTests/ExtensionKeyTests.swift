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
}
