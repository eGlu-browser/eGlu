import XCTest
@testable import PadCore

final class WritingPreferenceTests: XCTestCase {
    func testTheWritingOtherAppsSettingsDefaultToOff() throws {
        let old = try XCTUnwrap(#"{"writing":true}"#.data(using: .utf8))
        let preferences = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertFalse(preferences.writingOtherApps)
        XCTAssertEqual(preferences.writingApps, [:])
        XCTAssertFalse(preferences.writingNewApps)
    }

    func testTheWritingOtherAppsSettingsRoundTrip() throws {
        var preferences = Preferences()
        preferences.writingOtherApps = true
        preferences.writingApps = ["com.apple.TextEdit": false, "com.example.any": true]
        preferences.writingNewApps = true
        let data = try JSONEncoder().encode(preferences)
        let read = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(read, preferences)
    }
}
