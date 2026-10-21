import AppKit
import PadCore
import WebKit

/// Updates from the Chrome Web Store, and extensions loaded from a folder
/// (Docs/ExtensionsDesign.md, section 3).
extension Extensions {
    // MARK: Updates

    /// Whether the daily check is on: Settings › Extensions, on unless turned off.
    static var checksForUpdates: Bool {
        get { UserDefaults.standard.object(forKey: "extensionUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "extensionUpdates") }
    }

    private static let checkedKey = "extensionsChecked"

    /// When the store was last asked.
    static var lastChecked: Date? { UserDefaults.standard.object(forKey: checkedKey) as? Date }

    /// Asked every hour whether a day's check is due (20 hours since the
    /// last), so an app left open for days keeps checking. (Search)
    func startUpdates() -> Timer {
        let clock = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { Task { await self?.checkForUpdates() } }
        }
        clock.tolerance = 5 * 60
        Task { await checkForUpdates() }
        return clock
    }

    /// The store asked whether anything installed from it has a newer
    /// version; each one fetched, checked as at install, and put in place.
    /// One that asks for more than it was allowed is asked about first.
    /// `now`: Check Now, whatever the time or the switch. The number of
    /// extensions updated.
    @discardableResult
    func checkForUpdates(now: Bool = false) async -> Int {
        guard now || Self.checksForUpdates else { return 0 }
        guard now || Date().timeIntervalSince(Self.lastChecked ?? .distantPast) > 20 * 60 * 60 else { return 0 }
        let items = installed.filter { $0.source == .store }.compactMap { item in
            ExtensionVersion(item.version).map { (id: item.id, version: $0) }
        }
        guard !items.isEmpty else { return 0 }
        UserDefaults.standard.set(Date(), forKey: Self.checkedKey)
        var updated = 0
        for url in ExtensionStore.updateCheckURLs(for: items) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            for update in ExtensionUpdateReply.parse(data) where update.status == .newer {
                if await apply(update) { updated += 1 }
            }
        }
        return updated
    }

    private func apply(_ update: ExtensionUpdate) async -> Bool {
        guard let item = installed.first(where: { $0.id == update.id && $0.source == .store }),
              let current = ExtensionVersion(item.version), let offered = update.version, offered > current else { return false }
        do {
            let crx = try await download(item.id)
            let archive = try CRXFile.archive(of: crx, id: item.id, fromStore: true)
            guard let manifestData = ZipFile.file(in: archive, matching: { $0 == "manifest.json" }) else { throw Refused.noManifest }
            let manifest = try ExtensionManifest(json: manifestData)
            guard let version = ExtensionVersion(manifest.version), version > current else { return false }
            // Removed, turned off or changed while it was fetched: not now.
            guard installed.first(where: { $0.id == item.id }) == item else { return false }
            let wants = manifest.grants
            if let had = item.granted, !Set(wants).isSubset(of: Set(had)) {
                guard await askToUpdate(item, wanting: Set(wants).subtracting(had).sorted()) else { return false }
                guard installed.first(where: { $0.id == item.id }) == item else { return false }
            }
            let name = manifest.name.hasPrefix("__MSG_") ? item.name : manifest.name
            try keep(archive, id: item.id, name: name, version: version.description, source: .store,
                     access: item.siteAccess, spaces: item.spaces, granted: wants)
            return true
        } catch {
            NSLog("Safience: the update of extension \(item.id) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// An update that wants more: asked in a sheet, as at install.
    private func askToUpdate(_ item: Installed, wanting more: [String]) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "An update to \u{201C}\(item.name)\u{201D} asks for more."
        let sites = more.filter { $0.hasPrefix("site:") }.map { String($0.dropFirst(5)) }
        let apis = more.filter { !$0.hasPrefix("site:") }
        var lines: [String] = []
        if !apis.isEmpty { lines.append("It asks for: " + apis.joined(separator: ", ") + ".") }
        if !sites.isEmpty { lines.append("It wants to read and change: " + sites.joined(separator: ", ") + ".") }
        lines.append("Until you update it, the version you have keeps working.")
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Not Now")
        return await present(alert, in: Session.shared.frontWindow) == .alertFirstButtonReturn
    }

    // MARK: Loading from a folder

    /// Load Unpacked: a developer's folder, copied in as it is now. Its id
    /// is its path's, as Chrome makes one, so Reload finds it again and it
    /// can never be, or take the place of, a store extension.
    func loadUnpacked(in window: WindowModel?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose an extension's folder: the one with its manifest.json."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            do {
                let path = folder.standardizedFileURL.path
                let id = ExtensionID.id(forUnpackedPath: path)
                try await offer(try await Self.zipped(folder), id: id, source: .unpacked, in: window, folder: path)
            } catch {
                tell(error, in: window)
            }
        }
    }

    /// The folder read again, for an unpacked extension; in its place, with
    /// its data and where it is on.
    func reload(_ id: String) {
        guard let item = installed.first(where: { $0.id == id }), item.source == .unpacked, let path = item.folder else { return }
        Task {
            do {
                let archive = try await Self.zipped(URL(fileURLWithPath: path, isDirectory: true))
                guard let manifestData = ZipFile.file(in: archive, matching: { $0 == "manifest.json" }) else { throw Refused.noManifest }
                let manifest = try ExtensionManifest(json: manifestData)
                guard let version = ExtensionVersion(manifest.version)?.description else { throw Refused.badVersion }
                guard installed.first(where: { $0.id == id }) == item else { return }
                try keep(archive, id: id, name: manifest.name.hasPrefix("__MSG_") ? item.name : manifest.name, version: version,
                         source: .unpacked, access: item.siteAccess, spaces: item.spaces, granted: manifest.grants, folder: path)
            } catch {
                tell(error, in: Session.shared.frontWindow)
            }
        }
    }

    /// A folder as a ZIP with its contents at the top, by ditto, the Mac's own.
    static func zipped(_ folder: URL) async throws -> Data {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) else {
            throw Refused.noManifest
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("safience-unpacked-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: out) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", folder.path, out.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { done in
            process.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { done.resume(throwing: error) }
        }
        guard status == 0 else { throw Refused.notChecked("The folder couldn't be read.") }
        return try Data(contentsOf: out)
    }
}
