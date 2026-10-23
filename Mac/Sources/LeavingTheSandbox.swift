import Foundation
import PadCore

/// The legacy container stays intact. Existing outside data is never replaced.
/// Directory checkpoints and staged files let an interrupted move resume.
enum LeavingTheSandbox {
    private static let doneKey = "leftTheSandbox"
    private static let itemsKey = "leftTheSandbox.items"

    struct Request: Sendable {
        let library: URL
        let bundle: String
        let completed: Set<String>
    }

    static func request() -> Request? {
        let defaults = UserDefaults.standard
        guard Session.dataRootOverride == nil,
              ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil,
              !defaults.bool(forKey: doneKey), let bundle = Bundle.main.bundleIdentifier else { return nil }
        return Request(library: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true),
                       bundle: bundle, completed: Set(defaults.stringArray(forKey: itemsKey) ?? []))
    }

    static func finish(_ request: Request, result: LegacyDataMigration.Result) {
        let defaults = UserDefaults.standard
        let plist = request.library.appendingPathComponent("Containers/\(request.bundle)/Data/Library/Preferences/\(request.bundle).plist")
        if let data = try? Data(contentsOf: plist),
           let settings = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in settings where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        }
        defaults.set(result.completed.sorted(), forKey: itemsKey)
        defaults.set(true, forKey: doneKey)
    }
}
