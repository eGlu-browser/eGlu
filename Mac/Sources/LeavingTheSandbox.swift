import Foundation

/// Safience for Mac left the App Sandbox on 21 October 2026, to be a DMG
/// rather than a Mac App Store app, so that extensions can reach the desktop
/// apps that go with them (Docs/ExtensionsDesign.md, section 3).
///
/// A sandboxed app's files are inside its container, ~/Library/Containers/
/// <bundle id>/Data/Library; the same app outside the sandbox looks in
/// ~/Library, and WebKit, outside the sandbox, files its stores under the
/// bundle identifier as well. So the first launch outside it copies over,
/// once: the app's folder in Application Support (the workspace, the filter
/// lists), WebKit's stores (each space's sign-ins and site data) and its
/// compiled blocking rules, and the settings. The container is left as it
/// was: a sandboxed build run again finds everything where it left it.
///
/// Each item is copied whole into a folder beside where it goes, then
/// renamed into place, and marked done; one that didn't come over is tried
/// again at the next launch. A launch in between may have made its own
/// folder there (a fresh workspace, say): that one is set aside, not
/// copied over, and not taken for the item having come over.
enum LeavingTheSandbox {
    private static let doneKey = "leftTheSandbox"
    private static let itemsKey = "leftTheSandbox.items"

    static func move() {
        let defaults = UserDefaults.standard
        // Still in the sandbox (a build signed with the old entitlements):
        // its files are where it looks.
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil,
              !defaults.bool(forKey: doneKey),
              let bundle = Bundle.main.bundleIdentifier
        else { return }
        let files = FileManager.default
        let library = files.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        let container = library.appendingPathComponent("Containers/\(bundle)/Data/Library", isDirectory: true)
        guard files.fileExists(atPath: container.path) else {
            defaults.set(true, forKey: doneKey)
            return
        }

        // In the container, and where the same thing goes outside it.
        let items = [
            ("Application Support/Safience", "Application Support/Safience"),
            ("WebKit/WebsiteDataStore", "WebKit/\(bundle)/WebsiteDataStore"),
            ("WebKit/ContentRuleLists", "WebKit/\(bundle)/ContentRuleLists"),
        ]
        var done = Set(defaults.stringArray(forKey: itemsKey) ?? [])
        for (inContainer, outside) in items where !done.contains(inContainer) {
            let from = container.appendingPathComponent(inContainer)
            let to = library.appendingPathComponent(outside)
            guard files.fileExists(atPath: from.path) else {
                done.insert(inContainer)
                continue
            }
            do {
                try files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staging = to.deletingLastPathComponent().appendingPathComponent(to.lastPathComponent + ".moving")
                try? files.removeItem(at: staging)
                try files.copyItem(at: from, to: staging)
                if files.fileExists(atPath: to.path) {
                    let aside = to.deletingLastPathComponent()
                        .appendingPathComponent(to.lastPathComponent + " (made before the move, \(Int(Date().timeIntervalSince1970)))")
                    try files.moveItem(at: to, to: aside)
                }
                try files.moveItem(at: staging, to: to)
                done.insert(inContainer)
            } catch {
                NSLog("Safience: couldn't copy \(inContainer) out of the sandbox's container: \(error.localizedDescription)")
            }
        }
        defaults.set(done.sorted(), forKey: itemsKey)

        // The settings: each one the container had, unless set here already.
        let plist = container.appendingPathComponent("Preferences/\(bundle).plist")
        if let data = try? Data(contentsOf: plist),
           let settings = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in settings where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        if done.count == items.count { defaults.set(true, forKey: doneKey) }
    }
}
