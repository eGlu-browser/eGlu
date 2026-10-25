import Foundation
import Testing
@testable import PadCore

@Suite("App icon")
struct AppIconTests {
    /// The repository's root, where App/, Mac/ and project.yml are.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // PadCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // PadCore
        .deletingLastPathComponent()   // the root

    private static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    @Test func settingsOrder() {
        #expect(AppIcon.allCases.map(\.rawValue)
                == ["eGlu", "Globe", "Designer", "Engineer", "Signal", "Vista", "Hardcover", "Punk", "Astro"])
    }

    @Test func keptByName() {
        for icon in AppIcon.allCases {
            #expect(AppIcon(alternateName: icon.alternateName) == icon)
        }
        #expect(AppIcon.eGlu.alternateName == nil)
        #expect(AppIcon(alternateName: nil) == .eGlu)
        // A name from before the icons were renamed, and the app's own name,
        // which no alternate is kept by.
        #expect(AppIcon(alternateName: "Diazo") == nil)
        #expect(AppIcon(alternateName: "eGlu") == nil)
    }

    @Test func titles() throws {
        #expect(AppIcon.eGlu.title == "eGlu")
        #expect(AppIcon.astro.title == "Astro")
        // Each name is in both languages' strings, so none falls back to the key by accident.
        let path = try #require(BrowserText.resourceBundle.path(forResource: "ko", ofType: "lproj"))
        let korean = try #require(Bundle(path: path))
        for icon in AppIcon.allCases where icon != .eGlu {
            #expect(korean.localizedString(forKey: icon.rawValue, value: "missing", table: nil) != "missing", "\(icon)")
        }
        #expect(korean.localizedString(forKey: "Globe", value: nil, table: nil) == "지구본")
    }

    /// Every icon is compiled for the iPhone and iPad, has its preview in
    /// their Settings, and has its pictures in the Mac's: one missing would
    /// show an empty square, or no icon at all.
    @Test func everyIconHasItsFiles() throws {
        let project = try String(contentsOf: Self.root.appendingPathComponent("project.yml"), encoding: .utf8)
        let line = try #require(project.split(separator: "\n").first { $0.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES:") })
        let compiled = Set(line.split(separator: ":")[1].split(separator: " ").map(String.init))
        #expect(compiled == Set(AppIcon.allCases.compactMap(\.alternateName)))

        #expect(Self.exists("Shared/eGlu.icon/icon.json"))
        for icon in AppIcon.allCases {
            if let name = icon.alternateName {
                #expect(Self.exists("App/\(name).icon/icon.json"), "\(icon)")
            }
            let preview = "App/Assets.xcassets/IconPreviews/IconPreview\(icon.alternateName ?? "Eglu").imageset"
            #expect(Self.exists("\(preview)/light.png") && Self.exists("\(preview)/dark.png"), "\(icon)")
            let mac = "Mac/Assets.xcassets/AppIcons/AppIcon-\(icon.rawValue).imageset"
            #expect(Self.exists("\(mac)/light.png") && Self.exists("\(mac)/dark.png"), "\(icon)")
        }
    }
}
